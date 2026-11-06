# 安装明日香桌宠的 DeepSeek Harness 权限桥插件 + 官方宠物素材包。
# 需要写入 %USERPROFILE%\.dsh 与 %USERPROFILE%\.codex；由主会话以授权方式运行。
# 所有被修改的文件都会先备份到 Desktop\asuka-desktop-pet\backup\ 下。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dshHome = Join-Path $env:USERPROFILE '.dsh'
$profileDir = Join-Path $dshHome 'profiles\desktop'
$pluginSrc = Join-Path $root 'pet\bridge'
$pluginDst = Join-Path $dshHome 'plugins\dsh-asuka-pet-bridge'
$pkgPath = Join-Path $profileDir 'package.json'
$patchPath = Join-Path $profileDir 'cordis.patch.yml'
$backupDir = Join-Path $root ('backup\profile-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$petDir = Join-Path $root 'pet'

if (-not (Test-Path $pkgPath)) { throw "找不到 DSH 桌面 profile：$pkgPath" }

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -Path $pkgPath -Destination (Join-Path $backupDir 'package.json') -Force
Copy-Item -Path $patchPath -Destination (Join-Path $backupDir 'cordis.patch.yml') -Force
"已备份 profile 到 $backupDir"

# 1) 复制插件到 DSH 插件目录
New-Item -ItemType Directory -Force -Path $pluginDst | Out-Null
& robocopy $pluginSrc $pluginDst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "复制插件失败 (robocopy $LASTEXITCODE)" }
"已复制插件到 $pluginDst"

# 2) node_modules 链接（和 dsh-github-connect 一样用 Junction）
$linkPath = Join-Path $profileDir 'node_modules\dsh-asuka-pet-bridge'
if (Test-Path $linkPath) { Remove-Item -Path $linkPath -Recurse -Force }
New-Item -ItemType Junction -Path $linkPath -Target $pluginDst | Out-Null
"已建立 node_modules Junction"

# 3) profile package.json：加依赖 + 加 bundle
$pkg = Get-Content -Path $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$linkSpec = 'link:' + ($pluginDst -replace '\\', '/')

$depProp = $pkg.dependencies.PSObject.Properties['dsh-asuka-pet-bridge']
if ($null -eq $depProp) {
  $pkg.dependencies | Add-Member -NotePropertyName 'dsh-asuka-pet-bridge' -NotePropertyValue $linkSpec -Force
} else {
  $depProp.Value = $linkSpec
}

$bundles = @($pkg.dsh.profile.bundles)
if ($bundles -notcontains 'dsh-asuka-pet-bridge') {
  $bundles += 'dsh-asuka-pet-bridge'
  $pkg.dsh.profile.bundles = $bundles
}

$json = $pkg | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($pkgPath, $json, (New-Object Text.UTF8Encoding($false)))
"已更新 profile package.json（依赖 + bundles）"

# 4) 官方宠物素材包 -> %USERPROFILE%\.codex\pets
$codexPets = Join-Path $env:USERPROFILE '.codex\pets'
New-Item -ItemType Directory -Force -Path $codexPets | Out-Null
$formA = Join-Path $root 'delivery\asuka-v2_20261026\asuka-school'
$formB = Join-Path $root 'delivery\asuka-v2_20261026\asuka-work'
foreach ($pair in @(@($formA, (Join-Path $codexPets 'asuka-school')), @($formB, (Join-Path $codexPets 'asuka-work')))) {
  New-Item -ItemType Directory -Force -Path $pair[1] | Out-Null
  & robocopy $pair[0] $pair[1] /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "复制宠物素材失败: $($pair[0])" }
  "已安装官方素材包 -> $($pair[1])"
}

# 5) 快捷方式：桌面 + 开始菜单
$vbs = Join-Path $petDir 'AsukaPet.vbs'
$icon = Join-Path $petDir 'assets\app.ico'
$wsh = New-Object -ComObject WScript.Shell
$targets = @(
  (Join-Path $env:USERPROFILE 'Desktop\明日香桌宠.lnk'),
  (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\明日香桌宠.lnk')
)
foreach ($lnkPath in $targets) {
  $lnk = $wsh.CreateShortcut($lnkPath)
  $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
  $lnk.Arguments = '"' + $vbs + '"'
  $lnk.WorkingDirectory = $petDir
  $lnk.IconLocation = $icon
  $lnk.Description = '明日香桌宠'
  $lnk.Save()
  "已创建快捷方式: $lnkPath"
}

"安装完成。重启 DeepSeek Harness 后，权限请求会先出现在桌宠气泡上。"
