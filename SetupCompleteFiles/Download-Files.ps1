

$ScriptDir = "C:\Windows\Setup\Scripts"

Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" | Out-File -FilePath "$ScriptDir\Remove-AppX.ps1" -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "$ScriptDir\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1" | Out-File -FilePath "$ScriptDir\Copy-Start.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\OSUpdate.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" | Out-File -FilePath "$ScriptDir\New-ComputerName.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Deploy-RunOnceTask-OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\Deploy-RunOnceTask-OSUpdate.ps1"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Update-Firmware.ps1" | Out-File -FilePath "$ScriptDir\Update-Firmware.ps1" -Encoding ascii -Force
