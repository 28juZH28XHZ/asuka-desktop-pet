#requires -Version 5.1
# 明日香桌宠 (Asuka Desktop Pet)
# 独立 Windows 桌面宠物：WPF 透明置顶窗口 + 精灵动画 + DeepSeek API 聊天/余额 + DSH 权限请求气泡。
# 由 DeepSeek Harness 生成。素材来自 waynewayne893/asuka-desktop-pet 交付包。

param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 让进程感知高 DPI，否则 125% 缩放时窗口会被系统放大并挪出屏幕
try {
  if (-not ('DpiHelper' -as [type])) {
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class DpiHelper { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern uint GetDpiForWindow(System.IntPtr hwnd); }'
  }
  [void][DpiHelper]::SetProcessDPIAware()
} catch { }

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:AssetsDir = Join-Path $script:AppDir 'assets'
$script:CfgPath = Join-Path $script:AppDir 'config.json'
$script:LogPath = Join-Path $script:AppDir 'pet.log'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:TmpDir = Join-Path $env:TEMP 'asuka-pet'
$script:CellW = 192
$script:CellH = 208
$script:RowFrames = @(6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8)

New-Item -ItemType Directory -Force -Path $script:TmpDir | Out-Null

function Write-Log([string]$Message) {
  try {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    [IO.File]::AppendAllText($script:LogPath, $line + "`r`n", $script:Utf8NoBom)
  } catch { }
}

# ---------- 单实例 ----------
$createdNew = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\AsukaDesktopPet.SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
  Write-Log 'another instance is running, exit'
  exit 0
}

# ---------- 配置 ----------
$script:Defaults = [ordered]@{
  form      = 'school'
  scale     = 1.25
  x         = $null
  y         = $null
  topmost   = $true
  model     = 'deepseek-chat'
  historyLimit = 8
  mailboxDir = 'data\mailbox'
  persona   = '你叫明日香，是《新世纪福音战士》里的惣流·明日香·兰格雷，现在作为桌宠住在用户的 Windows 电脑桌面上。你自信、傲娇、嘴硬心软，叫用户“笨蛋”。回复要简短口语化，1 到 3 句话，可以吐槽但不要恶意辱骂，用中文回答。'
}

$script:Cfg = $null
function Load-Config {
  $cfg = @{}
  foreach ($k in $script:Defaults.Keys) { $cfg[$k] = $script:Defaults[$k] }
  if (Test-Path $script:CfgPath) {
    try {
      $raw = Get-Content -Path $script:CfgPath -Raw -Encoding UTF8
      $saved = $raw | ConvertFrom-Json
      foreach ($k in $script:Defaults.Keys) {
        if ($null -ne $saved.PSObject.Properties[$k]) { $cfg[$k] = $saved.PSObject.Properties[$k].Value }
      }
    } catch { Write-Log ('config load failed: ' + $_.Exception.Message) }
  }
  $script:Cfg = $cfg
}

function Save-Config {
  try {
    $obj = [ordered]@{}
    foreach ($k in $script:Defaults.Keys) { $obj[$k] = $script:Cfg[$k] }
    $json = ($obj | ConvertTo-Json -Depth 5)
    [IO.File]::WriteAllText($script:CfgPath, $json, $script:Utf8NoBom)
  } catch { Write-Log ('config save failed: ' + $_.Exception.Message) }
}

Load-Config

# ---------- Node / DSH 路径 ----------
$nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCmd) { $nodeCmd = Get-Command node -ErrorAction SilentlyContinue }
$script:Node = $null
if ($nodeCmd) { $script:Node = $nodeCmd.Source }
$script:NetJs = Join-Path $script:AppDir 'lib\net.js'

$script:DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$script:Mailbox = Join-Path $script:AppDir 'data\mailbox'
if ($script:Cfg.mailboxDir) {
  $md = [string]$script:Cfg.mailboxDir
  if ([IO.Path]::IsPathRooted($md)) { $script:Mailbox = $md } else { $script:Mailbox = Join-Path $script:AppDir $md }
}
$script:ReqDir = Join-Path $script:Mailbox 'requests'
$script:DecDir = Join-Path $script:Mailbox 'decisions'
$script:HbPath = Join-Path $script:Mailbox 'heartbeat.json'
New-Item -ItemType Directory -Force -Path $script:ReqDir, $script:DecDir | Out-Null
Get-ChildItem -Path $script:ReqDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $script:DecDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# ---------- 图集 ----------
function Load-Sheet([string]$Path) {
  $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
  $bmp.BeginInit()
  $bmp.UriSource = New-Object System.Uri ($Path)
  $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
  $bmp.EndInit()
  $bmp.Freeze()
  $rows = New-Object System.Collections.ArrayList
  for ($r = 0; $r -lt $script:RowFrames.Count; $r++) {
    $count = $script:RowFrames[$r]
    $frames = New-Object System.Collections.ArrayList
    for ($c = 0; $c -lt $count; $c++) {
      $rect = New-Object System.Windows.Int32Rect -ArgumentList ($c * $script:CellW), ($r * $script:CellH), $script:CellW, $script:CellH
      $crop = New-Object System.Windows.Media.Imaging.CroppedBitmap -ArgumentList $bmp, $rect
      $crop.Freeze()
      [void]$frames.Add($crop)
    }
    [void]$rows.Add($frames.ToArray())
  }
  return $rows.ToArray()
}

$script:Sheets = @{
  school = (Load-Sheet (Join-Path $script:AssetsDir 'school.png'))
  work   = (Load-Sheet (Join-Path $script:AssetsDir 'work.png'))
}

# ---------- 动画状态 ----------
$script:AnimStates = @{
  idle  = @{ row = 0; speed = 140; loop = $true }
  walk  = @{ row = 1; speed = 110; loop = $true }
  run   = @{ row = 2; speed = 90;  loop = $true }
  wave  = @{ row = 3; speed = 170; loop = $false; next = 'idle' }
  jump  = @{ row = 4; speed = 120; loop = $false; next = 'idle' }
  dance = @{ row = 5; speed = 130; loop = $false; next = 'idle' }
}
$script:animName = 'idle'
$script:animIdx = 0
$script:animElapsed = 0

# ---------- UI ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AsukaPet" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize"
        Width="380" SizeToContent="Height" FontFamily="Microsoft YaHei UI" FontSize="13">
  <Window.ContextMenu>
    <ContextMenu x:Name="petMenu">
      <MenuItem x:Name="miSchool" Header="校服形态" IsCheckable="True" IsChecked="True"/>
      <MenuItem x:Name="miWork" Header="战斗服形态" IsCheckable="True"/>
      <Separator/>
      <MenuItem x:Name="miChat" Header="和明日香聊天…"/>
      <MenuItem x:Name="miBalance" Header="查看 DSH 余额"/>
      <MenuItem x:Name="miWave" Header="看她一眼"/>
      <Separator/>
      <MenuItem x:Name="miTop" Header="总在最前" IsCheckable="True" IsChecked="True"/>
      <MenuItem x:Name="miSize" Header="大小">
        <MenuItem x:Name="miSize100" Header="100%"/>
        <MenuItem x:Name="miSize125" Header="125%"/>
        <MenuItem x:Name="miSize150" Header="150%"/>
        <MenuItem x:Name="miSize175" Header="175%"/>
      </MenuItem>
      <Separator/>
      <MenuItem x:Name="miExit" Header="退出"/>
    </ContextMenu>
  </Window.ContextMenu>
  <StackPanel Margin="6">
    <Border x:Name="bubble" Visibility="Collapsed" Background="#FBF7F5" CornerRadius="14" BorderBrush="#E8B4BC" BorderThickness="1" Padding="12,10" MaxWidth="360" HorizontalAlignment="Center" Margin="0,0,0,2">
      <Border.Effect>
        <DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.22" Color="#333333"/>
      </Border.Effect>
      <StackPanel>
        <Grid Margin="0,0,0,3">
          <TextBlock x:Name="bubbleTitle" Text="明日香" FontSize="11" FontWeight="Bold" Foreground="#B03A48" HorizontalAlignment="Left"/>
          <Button x:Name="btnCloseBubble" Content="✕" FontSize="10" Foreground="#9A7F84" Background="Transparent" BorderThickness="0" Padding="4,0" HorizontalAlignment="Right" VerticalAlignment="Center" Cursor="Hand"/>
        </Grid>
        <TextBlock x:Name="bubbleText" TextWrapping="Wrap" Foreground="#2B2B2B" MaxWidth="330" LineHeight="19"/>
        <StackPanel x:Name="bubbleButtons" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,9,0,0" Visibility="Collapsed">
          <Button x:Name="btnAllow" Content="允许" Padding="14,3" Margin="0,0,6,0" Background="#1F9D55" Foreground="White" BorderThickness="0"/>
          <Button x:Name="btnDeny" Content="拒绝" Padding="14,3" Background="#D64545" Foreground="White" BorderThickness="0"/>
        </StackPanel>
        <StackPanel x:Name="chatRow" Orientation="Horizontal" Margin="0,9,0,0" Visibility="Collapsed">
          <TextBox x:Name="chatBox" Width="236" Padding="4,3" BorderBrush="#CCB3B8" VerticalContentAlignment="Center"/>
          <Button x:Name="sendBtn" Content="发送" Padding="12,3" Margin="6,0,0,0" Background="#B03A48" Foreground="White" BorderThickness="0"/>
        </StackPanel>
      </StackPanel>
    </Border>
    <Image x:Name="sprite" Width="240" Height="260" Stretch="Fill"
           RenderOptions.BitmapScalingMode="HighQuality" Cursor="Hand"/>
  </StackPanel>
</Window>
'@

$script:app = New-Object System.Windows.Application
$script:win = [Windows.Markup.XamlReader]::Parse($xaml)
$script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$script:app.MainWindow = $script:win

$bubble = $script:win.FindName('bubble')
$bubbleTitle = $script:win.FindName('bubbleTitle')
$bubbleText = $script:win.FindName('bubbleText')
$bubbleButtons = $script:win.FindName('bubbleButtons')
$btnAllow = $script:win.FindName('btnAllow')
$btnDeny = $script:win.FindName('btnDeny')
$btnCloseBubble = $script:win.FindName('btnCloseBubble')
$chatRow = $script:win.FindName('chatRow')
$chatBox = $script:win.FindName('chatBox')
$sendBtn = $script:win.FindName('sendBtn')
$sprite = $script:win.FindName('sprite')
$miSchool = $script:win.FindName('miSchool')
$miWork = $script:win.FindName('miWork')
$miChat = $script:win.FindName('miChat')
$miBalance = $script:win.FindName('miBalance')
$miWave = $script:win.FindName('miWave')
$miTop = $script:win.FindName('miTop')
$miSize100 = $script:win.FindName('miSize100')
$miSize125 = $script:win.FindName('miSize125')
$miSize150 = $script:win.FindName('miSize150')
$miSize175 = $script:win.FindName('miSize175')
$miExit = $script:win.FindName('miExit')

$script:miTop.IsChecked = [bool]$script:Cfg.topmost
$script:win.Topmost = [bool]$script:Cfg.topmost
$script:miSchool.IsChecked = ($script:Cfg.form -eq 'school')
$script:miWork.IsChecked = ($script:Cfg.form -eq 'work')

$script:sprite.Width = $script:CellW * [double]$script:Cfg.scale
$script:sprite.Height = $script:CellH * [double]$script:Cfg.scale

# ---------- 界面状态 ----------
$script:currentApproval = $null
$script:approvalQueue = New-Object System.Collections.ArrayList
$script:chatHistory = New-Object System.Collections.ArrayList
$script:netBusy = $false
$script:pending = $null
$script:chatActive = $false
$script:hideAt = $null
$script:tray = $null

function Show-Frame {
  $state = $script:AnimStates[$script:animName]
  $frames = $script:Sheets[$script:Cfg.form][$state.row]
  if ($script:animIdx -ge $frames.Count) { $script:animIdx = 0 }
  $script:sprite.Source = $frames[$script:animIdx]
}

function Set-Anim([string]$Name) {
  if (-not $script:AnimStates.ContainsKey($Name)) { $Name = 'idle' }
  $script:animName = $Name
  $script:animIdx = 0
  $script:animElapsed = 0
  Show-Frame
}

function Tick-Anim {
  try {
    $state = $script:AnimStates[$script:animName]
    $script:animElapsed += 100
    if ($script:animElapsed -ge $state.speed) {
      $script:animElapsed = 0
      $script:animIdx++
      $frames = $script:Sheets[$script:Cfg.form][$state.row]
      if ($script:animIdx -ge $frames.Count) {
        if ($state.loop) { $script:animIdx = 0 }
        else { Set-Anim $state.next; return }
      }
      Show-Frame
    }
  } catch { Write-Log ('anim tick failed: ' + $_.Exception.Message) }
}

function Show-Bubble([string]$Title, [string]$Text) {
  $script:bubbleTitle.Text = $Title
  $script:bubbleText.Text = $Text
  $script:bubble.Visibility = 'Visible'
}

function Hide-Bubble {
  $script:bubble.Visibility = 'Collapsed'
  $script:bubbleButtons.Visibility = 'Collapsed'
  $script:chatRow.Visibility = 'Collapsed'
  $script:chatActive = $false
  $script:hideAt = $null
}

function Save-Position {
  $script:Cfg.x = [double]$script:win.Left
  $script:Cfg.y = [double]$script:win.Top
  Save-Config
}

function Set-Form([string]$Form) {
  if ($Form -ne 'school' -and $Form -ne 'work') { return }
  $script:Cfg.form = $Form
  $script:miSchool.IsChecked = ($Form -eq 'school')
  $script:miWork.IsChecked = ($Form -eq 'work')
  Save-Config
  Set-Anim 'wave'
}

function Set-Scale([double]$Scale) {
  $script:Cfg.scale = $Scale
  $script:sprite.Width = $script:CellW * $Scale
  $script:sprite.Height = $script:CellH * $Scale
  Save-Config
}

# ---------- 网络调用 ----------
function Start-NetCall([hashtable]$Payload, [string]$Tag) {
  if (-not $script:Node) {
    Show-Bubble '明日香' '找不到 Node.js，联网功能用不了。'
    return
  }
  $script:netBusy = $true
  $id = [guid]::NewGuid().ToString('N')
  $reqFile = Join-Path $script:TmpDir ($id + '.req.json')
  $respFile = Join-Path $script:TmpDir ($id + '.resp.json')
  try {
    [IO.File]::WriteAllText($reqFile, ($Payload | ConvertTo-Json -Depth 10 -Compress), $script:Utf8NoBom)
  } catch {
    Write-Log ('write request failed: ' + $_.Exception.Message)
    $script:netBusy = $false
    return
  }
  $argList = @('"' + $script:NetJs + '"', '"' + $reqFile + '"', '"' + $respFile + '"')
  try {
    $proc = Start-Process -FilePath $script:Node -ArgumentList $argList -WindowStyle Hidden -PassThru
  } catch {
    Write-Log ('spawn node failed: ' + $_.Exception.Message)
    $script:netBusy = $false
    Show-Bubble '明日香' '启动 Node 失败，看看 pet.log。'
    return
  }
  $script:pending = @{ id = $id; resp = $respFile; req = $reqFile; tag = $Tag; started = Get-Date; proc = $proc }
}

function Format-Wallets($List) {
  $parts = @()
  foreach ($w in @($List)) {
    if ($null -eq $w) { continue }
    $currency = [string]$w.currency
    $sym = switch ($currency) { 'CNY' { [char]0x00A5 } 'USD' { '$' } default { $currency + ' ' } }
    $value = 0.0
    try { $value = [double]::Parse([string]$w.balance, [Globalization.CultureInfo]::InvariantCulture) } catch { }
    $parts += ($sym + $value.ToString('0.00'))
  }
  if ($parts.Count -eq 0) { return '—' }
  return ($parts -join '   ')
}

function Handle-NetError([string]$Message) {
  $text = '……出错了：' + $Message
  if ($Message -like '*凭据*' -or $Message -like '*登录*' -or $Message -like '*401*') {
    $text = 'DSH 的登录状态好像过期了，去 DeepSeek Harness 里重新登录一下？'
  }
  if ($text.Length -gt 220) { $text = $text.Substring(0, 220) + '…' }
  Show-Bubble '明日香' $text
  Set-Anim 'jump'
  $script:hideAt = (Get-Date).AddSeconds(8)
}

function Finish-Net($Pending, $Data) {
  try {
    Remove-Item -Path $Pending.req -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $Pending.resp -Force -ErrorAction SilentlyContinue
    $script:pending = $null
    $script:netBusy = $false
    if ($null -eq $Data) { Handle-NetError '超时了，没收到回复。'; return }
    if (-not $Data.ok) { Handle-NetError ([string]$Data.error); return }

    if ($Data.kind -eq 'balance') {
      $wallets = @($Data.normal)
      $pick = $wallets | Where-Object { [string]$_.currency -eq 'CNY' } | Select-Object -First 1
      if ($null -eq $pick) { $pick = $wallets | Select-Object -First 1 }
      $text = '当前余额：' + (Format-Wallets @($pick))
      Show-Bubble 'DSH 余额' $text
      Set-Anim 'wave'
      $script:hideAt = (Get-Date).AddSeconds(10)
      return
    }

    if ($Data.kind -eq 'chat') {
      $reply = [string]$Data.text
      if ($reply -eq '') { $reply = '……（她没说话，可能在想事情）' }
      [void]$script:chatHistory.Add(@{ role = 'assistant'; content = $reply })
      while ($script:chatHistory.Count -gt ([int]$script:Cfg.historyLimit * 2)) { $script:chatHistory.RemoveAt(0) }
      $script:bubbleTitle.Text = '明日香'
      $script:bubbleText.Text = $reply
      $script:bubble.Visibility = 'Visible'
      $script:chatRow.Visibility = 'Visible'
      $script:chatActive = $true
      $script:hideAt = $null
      Set-Anim 'dance'
    }
  } catch { Write-Log ('finish net failed: ' + $_.Exception.Message) }
}

function Check-NetResult {
  if (-not $script:pending) { return }
  $p = $script:pending
  if (Test-Path $p.resp) {
    $data = $null
    try { $data = Get-Content -Path $p.resp -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $data = $null }
    Finish-Net $p $data
    return
  }
  if (((Get-Date) - $p.started).TotalSeconds -gt 55) { Finish-Net $p $null }
}

function Query-Balance {
  if ($script:netBusy) { return }
  if (-not $script:Node) { Show-Bubble '明日香' '找不到 Node.js，查不了余额。'; return }
  Show-Bubble 'DSH 余额' '正在查……'
  Start-NetCall -Payload @{ kind = 'balance' } -Tag 'balance'
}

function Open-Chat {
  if ($script:chatActive -and $script:bubble.Visibility -eq 'Visible') {
    $script:chatBox.Focus()
    return
  }
  Show-Bubble '明日香' '又有什么事？说吧，我听着呢。'
  $script:bubbleButtons.Visibility = 'Collapsed'
  $script:chatRow.Visibility = 'Visible'
  $script:chatActive = $true
  $script:hideAt = $null
  $script:chatBox.Text = ''
  try { $script:win.Activate() } catch { }
  $script:chatBox.Focus()
  Set-Anim 'wave'
}

function Send-Chat {
  if ($script:netBusy) { return }
  $text = $script:chatBox.Text.Trim()
  if ($text -eq '') { return }
  $script:chatBox.Clear()
  [void]$script:chatHistory.Add(@{ role = 'user'; content = $text })
  while ($script:chatHistory.Count -gt ([int]$script:Cfg.historyLimit * 2)) { $script:chatHistory.RemoveAt(0) }
  $messages = New-Object System.Collections.ArrayList
  [void]$messages.Add(@{ role = 'system'; content = [string]$script:Cfg.persona })
  foreach ($m in $script:chatHistory) { [void]$messages.Add($m) }
  $script:bubbleText.Text = '唔……让我想想。'
  $script:bubbleButtons.Visibility = 'Collapsed'
  Start-NetCall -Payload @{ kind = 'chat'; model = [string]$script:Cfg.model; messages = $messages.ToArray() } -Tag 'chat'
}

# ---------- 权限请求 ----------
function Check-Approvals {
  if ($script:currentApproval) { return }
  $files = @(Get-ChildItem -Path $script:ReqDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
  if ($files.Count -eq 0) { return }
  $file = $files[0]
  $req = $null
  try { $req = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
  if ($null -eq $req -or [string]::IsNullOrWhiteSpace([string]$req.id)) {
    Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
    return
  }
  $script:currentApproval = [pscustomobject]@{ id = [string]$req.id; path = $file.FullName }
  $tool = [string]$req.toolName
  $reason = ''
  if ($null -ne $req.displayReason) {
    if ($req.displayReason -is [string]) { $reason = [string]$req.displayReason }
    elseif ($req.displayReason.zh) { $reason = [string]$req.displayReason.zh }
    elseif ($req.displayReason.en) { $reason = [string]$req.displayReason.en }
  }
  if ($reason -eq '' -and $req.reason) { $reason = [string]$req.reason }
  Write-Log ('approval request: id=' + [string]$req.id + ' tool=' + $tool + ' reason=' + $reason)
  $text = 'DSH 想执行一个需要授权的操作。' + "`n工具：" + $tool
  if ($reason -ne '') { $text += "`n原因：" + $reason }
  Show-Bubble '权限请求' $text
  $script:bubbleButtons.Visibility = 'Visible'
  $script:btnAllow.IsEnabled = $true
  $script:btnDeny.IsEnabled = $true
  $script:chatRow.Visibility = 'Collapsed'
  $script:chatActive = $false
  $script:hideAt = $null
  Set-Anim 'jump'
}

function Complete-Approval([string]$Decision) {
  if (-not $script:currentApproval) { return }
  $id = $script:currentApproval.id
  Write-Log ('approval decision: id=' + $id + ' decision=' + $Decision)
  $payload = @{ id = $id; decision = $Decision; ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() } | ConvertTo-Json -Compress
  try { [IO.File]::WriteAllText((Join-Path $script:DecDir ($id + '.json')), $payload, $script:Utf8NoBom) } catch { Write-Log ('write decision failed: ' + $_.Exception.Message) }
  Remove-Item -Path $script:currentApproval.path -Force -ErrorAction SilentlyContinue
  $script:currentApproval = $null
  $script:bubbleButtons.Visibility = 'Collapsed'
  if ($Decision -eq 'allow') {
    $script:bubbleText.Text = '哼，这次就按你说的办。'
    Set-Anim 'wave'
  } else {
    $script:bubbleText.Text = '驳回。自己想清楚再来。'
    Set-Anim 'jump'
  }
  $script:hideAt = (Get-Date).AddSeconds(3)
}

# ---------- 轮询 ----------
function Write-Heartbeat {
  try {
    $json = '{"ts":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"pid":' + $PID + ',"form":"' + [string]$script:Cfg.form + '"}'
    [IO.File]::WriteAllText($script:HbPath, $json, $script:Utf8NoBom)
  } catch { }
}

function Tick-Poll {
  try {
    Write-Heartbeat
    Check-Approvals
    Check-NetResult
    # 请求被桥接端撤回（例如桌宠没及时作答、已超时转交给 DSH 自带卡片）时收起气泡
    if ($script:currentApproval -and -not (Test-Path -LiteralPath $script:currentApproval.path)) {
      Write-Log ('approval request withdrew: ' + $script:currentApproval.id)
      $script:currentApproval = $null
      $script:bubbleButtons.Visibility = 'Collapsed'
      if (-not $script:chatActive) { Hide-Bubble }
    }
    if ($script:hideAt -and (Get-Date) -ge $script:hideAt) {
      $script:hideAt = $null
      if (-not $script:currentApproval -and -not $script:chatActive) { Hide-Bubble }
    }
  } catch { Write-Log ('poll tick failed: ' + $_.Exception.Message) }
}

# ---------- 事件 ----------
$script:sprite.Add_MouseLeftButtonDown({
  param($sender, $e)
  if ($e.ClickCount -eq 2) { Open-Chat; return }
  try { $script:win.DragMove() } catch { }
  Save-Position
})

$script:btnAllow.Add_Click({ Complete-Approval 'allow' })
$script:btnDeny.Add_Click({ Complete-Approval 'deny' })
$script:btnCloseBubble.Add_Click({ Hide-Bubble })
$script:sendBtn.Add_Click({ Send-Chat })
$script:chatBox.Add_KeyDown({
  param($sender, $e)
  if ($e.Key -eq [System.Windows.Input.Key]::Enter) { Send-Chat; $e.Handled = $true }
  elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) { Hide-Bubble }
})

$script:miSchool.Add_Click({ Set-Form 'school' })
$script:miWork.Add_Click({ Set-Form 'work' })
$script:miChat.Add_Click({ Open-Chat })
$script:miBalance.Add_Click({ Query-Balance })
$script:miWave.Add_Click({ Set-Anim 'wave' })
$script:miTop.Add_Click({
  $script:Cfg.topmost = [bool]$script:miTop.IsChecked
  $script:win.Topmost = [bool]$script:Cfg.topmost
  Save-Config
})
$script:miSize100.Add_Click({ Set-Scale 1.0 })
$script:miSize125.Add_Click({ Set-Scale 1.25 })
$script:miSize150.Add_Click({ Set-Scale 1.5 })
$script:miSize175.Add_Click({ Set-Scale 1.75 })
$script:miExit.Add_Click({ $script:win.Close() })

$script:animTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:animTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:animTimer.Add_Tick({ Tick-Anim })
$script:animTimer.Start()

$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:pollTimer.Add_Tick({ Tick-Poll })
$script:pollTimer.Start()

$script:idleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:idleTimer.Interval = [TimeSpan]::FromMilliseconds(9000)
$script:idleTimer.Add_Tick({
  try {
    if ($script:animName -eq 'idle' -and $script:bubble.Visibility -ne 'Visible' -and -not $script:currentApproval) {
      $roll = Get-Random -Minimum 0 -Maximum 10
      if ($roll -lt 4) { Set-Anim 'wave' } elseif ($roll -lt 6) { Set-Anim 'jump' }
    }
  } catch { }
})
$script:idleTimer.Start()

# ---------- 位置与托盘 ----------
function Place-Window {
  try {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $w = $script:win.ActualWidth
    $h = $script:win.ActualHeight
    if ($w -le 0) { $w = 400 }
    if ($h -le 0) { $h = 400 }
    $scale = 1.0
    try {
      $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($script:win)).Handle
      if ($hwnd -ne [IntPtr]::Zero) {
        $dpi = [DpiHelper]::GetDpiForWindow($hwnd)
        if ($dpi -ge 96) { $scale = [double]$dpi / 96.0 }
      }
    } catch { }
    if ($scale -le 0.1) { $scale = 1.0 }
    $physW = $w * $scale
    $physH = $h * $scale
    $px = $screen.Right - $physW - 40
    $py = $screen.Bottom - $physH - 40
    if ($null -ne $script:Cfg.x -and $null -ne $script:Cfg.y) {
      $sx = [double]$script:Cfg.x * $scale
      $sy = [double]$script:Cfg.y * $scale
      if ($sx -gt ($screen.Left - 200) -and $sx -lt ($screen.Right - 60) -and $sy -gt ($screen.Top - 200) -and $sy -lt ($screen.Bottom - 60)) {
        $px = $sx
        $py = $sy
      }
    }
    if ($px + $physW -gt $screen.Right) { $px = $screen.Right - $physW - 20 }
    if ($py + $physH -gt $screen.Bottom) { $py = $screen.Bottom - $physH - 20 }
    if ($px -lt $screen.Left) { $px = $screen.Left }
    if ($py -lt $screen.Top) { $py = $screen.Top }
    $script:win.Left = $px / $scale
    $script:win.Top = $py / $scale
    Write-Log ('place: actual=' + $w + 'x' + $h + ' scale=' + $scale + ' screen=' + $screen + ' -> ' + $px + ',' + $py)
  } catch { Write-Log ('place failed: ' + $_.Exception.Message) }
}

function Create-Tray {
  $iconPath = Join-Path $script:AssetsDir 'app.ico'
  if (-not (Test-Path $iconPath)) { return }
  try {
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = New-Object System.Drawing.Icon ($iconPath)
    $ni.Text = '明日香桌宠'
    $ni.Visible = $true
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemShow = $menu.Items.Add('显示 / 隐藏明日香')
    $itemQuit = $menu.Items.Add('退出')
    $ni.ContextMenuStrip = $menu
    $itemShow.Add_Click({
      if ($script:win.Visibility -eq 'Visible') { Hide-Bubble; $script:win.Hide() }
      else { $script:win.Show(); try { $script:win.Activate() } catch { } }
    })
    $itemQuit.Add_Click({ $script:win.Close() })
    $ni.Add_DoubleClick({ $script:win.Show(); try { $script:win.Activate() } catch { } })
    $script:tray = $ni
  } catch { Write-Log ('tray failed: ' + $_.Exception.Message) }
}

$script:win.Add_Loaded({
  try {
    $script:sprite.Width = $script:CellW * [double]$script:Cfg.scale
    $script:sprite.Height = $script:CellH * [double]$script:Cfg.scale
    Set-Anim 'idle'
    Create-Tray
    $script:lastHeight = $script:win.ActualHeight
    Show-Bubble '明日香' '……哼，总算把我装好了？右键点我可以换衣服、聊天、查余额。'
    $script:hideAt = (Get-Date).AddSeconds(12)
    $script:win.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{ Place-Window }) | Out-Null
    $script:win.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{ Place-Window }) | Out-Null
  } catch { Write-Log ('loaded handler failed: ' + $_.Exception.Message) }
})

# 气泡出现/消失时窗口高度会变；改写 Top 让窗口底边（人物）保持不动
$script:win.Add_SizeChanged({
  try {
    $h = $script:win.ActualHeight
    if ($script:lastHeight -gt 0 -and [math]::Abs($h - $script:lastHeight) -gt 0.5) {
      $script:win.Top = $script:win.Top + ($script:lastHeight - $h)
    }
    $script:lastHeight = $h
  } catch { }
})
$script:lastHeight = 0

$script:win.Add_MouseRightButtonUp({ Write-Log 'right-button-up on window' })
$script:win.Add_MouseLeftButtonUp({ Write-Log 'left-button-up on window' })
$script:win.Add_PreviewMouseDown({
  param($sender, $e)
  try {
    $p = $e.GetPosition($script:win)
    Write-Log ('preview-mouse-down ' + $e.ChangedButton + ' at ' + [int]$p.X + ',' + [int]$p.Y)
  } catch { }
})
if ($script:win.ContextMenu) {
  $script:win.ContextMenu.Add_Opened({ Write-Log 'context menu opened' })
  $script:win.ContextMenu.Add_Closed({ Write-Log 'context menu closed' })
}

$script:win.Add_Closed({
  try {
    if ($script:tray) { $script:tray.Visible = $false; $script:tray.Dispose() }
    Remove-Item -Path $script:HbPath -Force -ErrorAction SilentlyContinue
    Save-Config
    $script:app.Shutdown()
  } catch { }
})

# ---------- 启动 ----------
Write-Log ('starting; node=' + [string]$script:Node + '; dshHome=' + $script:DshHome)
if (-not $script:Node) { Write-Log 'node not found; chat/balance disabled' }

try {
  [void]$script:app.Run($script:win)
} catch {
  Write-Log ('app run failed: ' + $_.Exception.Message)
} finally {
  try { $script:Mutex.ReleaseMutex() } catch { }
  $script:Mutex.Dispose()
  Write-Log 'stopped'
}
