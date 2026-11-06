' Asuka desk pet launcher - starts the PowerShell WPF pet without a console window.
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\AsukaPet.ps1"
If Not fso.FileExists(ps1) Then
  MsgBox "AsukaPet.ps1 not found next to this launcher.", 16, "Asuka Pet"
  WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
CreateObject("WScript.Shell").Run cmd, 0, False
