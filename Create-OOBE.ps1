#================================================
#    [PostOS] OOBE CMD Command Line
#================================================
$OOBECMD = @'
@echo off
:: OOBE fase: verwijder standaard apps
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Remove-AppX.ps1
'@
$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force
