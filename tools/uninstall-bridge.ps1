# 卸载明日香桌宠的权限桥插件（恢复 profile 备份），并删除快捷方式。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dshHome = Join-Path $env:USERPROFILE '.dsh'
$profileDir = Join-Path $dshHome 'profiles\desktop'
$pluginDst = Join-Path $dshHome 'plugins\dsh-asuka-pet-bridge'
$linkPath = Join-Path $profileDir 'node_modules\dsh-asuka-pet-bridge'
$pkgPath = Join-Path $profileDir 'package.json'

$backups = @(Get-ChildItem (Join-Path $root 'backup') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
if ($backups.Count -eq 0) { throw '找不到备份目录，无法恢复 profile' }
$latest = $backups[0].FullName

Copy-Item -Path (Join-Path $latest 'package.json') -Destination $pkgPath -Force
Copy-Item -Path (Join-Path $latest 'cordis.patch.yml') -Destination (Join-Path $profileDir 'cordis.patch.yml') -Force
if (Test-Path $linkPath) { Remove-Item -Path $linkPath -Recurse -Force }
if (Test-Path $pluginDst) { Remove-Item -Path $pluginDst -Recurse -Force }

$wsh = New-Object -ComObject WScript.Shell
foreach ($lnk in @(
  (Join-Path $env:USERPROFILE 'Desktop\明日香桌宠.lnk'),
  (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\明日香桌宠.lnk')
)) {
  if (Test-Path $lnk) { Remove-Item $lnk -Force }
}

"已从 $(Split-Path $latest -Leaf) 恢复 profile，并移除插件与快捷方式。重启 DeepSeek Harness 生效。"
