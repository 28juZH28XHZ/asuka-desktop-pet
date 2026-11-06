# Repair: when DeepSeek Harness's Windows sandbox marks the workspace folder as
# Low integrity, every file inside inherits the Low label. Windows then treats
# those files as untrusted downloads: shortcuts show "Open File - Security
# Warning" on every launch and desktop icons may render blank.
#
# This script restores the Desktop tree to Medium integrity and removes the
# sandbox ACL entries that the Low-integrity sandbox leaves behind.
#
# Run it from a normal (non-sandboxed) PowerShell window. If the folder is not
# writable from your account, run it as Administrator.

$ErrorActionPreference = 'Continue'
$desk = Join-Path $env:USERPROFILE 'Desktop'

function Show-State([string]$label) {
  "== $label =="
  icacls $desk | Select-String -Pattern 'Mandatory Label|S-1-4-|DENY'
}

Show-State 'BEFORE'

icacls $desk /setintegritylevel "(OI)(CI)M" 2>&1 | Out-Null
"folder label set to Medium"

$rootItems = @(Get-ChildItem -LiteralPath $desk -Force -ErrorAction SilentlyContinue)
foreach ($item in $rootItems) {
  if ($item.PSIsContainer) {
    icacls $item.FullName /setintegritylevel "(OI)(CI)M" 2>&1 | Out-Null
  } else {
    icacls $item.FullName /setintegritylevel M 2>&1 | Out-Null
  }
}
"processed $($rootItems.Count) root items"

# Remove any leftover sandbox S-1-4-* ACEs and the deny-delete entry.
$sandboxSids = @()
icacls $desk 2>&1 | ForEach-Object { if ($_ -match '(S-1-4-\d[\d-]+)') { $sandboxSids += $Matches[1] } }
foreach ($sid in ($sandboxSids | Select-Object -Unique)) {
  icacls $desk /remove:g $sid /T /C /Q 2>&1 | Out-Null
}
icacls $desk /remove:d Everyone /T /C /Q 2>&1 | Out-Null
"sandbox ACL entries removed"

Show-State 'AFTER'

foreach ($p in @((Join-Path $desk 'BitzNet.lnk'), (Join-Path $desk 'asuka-desktop-pet'))) {
  if (Test-Path -LiteralPath $p) {
    icacls $p 2>&1 | Select-String -Pattern 'Mandatory Label' | ForEach-Object { $p + ' -> ' + $_.Line.Trim() }
  }
}

# Rebuild the icon cache so blank icons come back:
#   taskkill /f /im explorer.exe
#   del "%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db"
#   start explorer.exe
