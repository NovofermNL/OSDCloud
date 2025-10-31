
$ScriptDir = 'C:\Windows\Setup\Scripts'
if (-not (Test-Path $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
}
<#
$Panther = 'C:\Windows\Panther'
if (-not (Test-Path $Panther)) {
    New-Item -ItemType Directory -Path $Panther -Force | Out-Null
}
#>

$SetupCompleFiles = 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles'


Write-Host -ForegroundColor Green "Download scripts voor OOBE-fase"

# Zorg dat de scripts-map bestaat vóór het wegschrijven
#New-Item -ItemType Directory -Path 'C:\Windows\Setup\scripts' -Force | Out-Null

Invoke-RestMethod $SetupCompleFiles/Remove-Appx.ps1 | Out-File -FilePath "$ScriptDir\Remove-AppX.ps1" -Encoding ascii -Force
Invoke-RestMethod $SetupCompleFiles/Copy-Start.ps1 | Out-File -FilePath "$ScriptDir\Copy-Start.ps1" -Encoding ascii -Force
Invoke-RestMethod $SetupCompleFiles/OSUpdate.ps1 | Out-File -FilePath "$ScriptDir\OSUpdate.ps1" -Encoding ascii -Force
Invoke-RestMethod $SetupCompleFiles/New-ComputerName.ps1 | Out-File -FilePath "$ScriptDir\New-ComputerName.ps1" -Encoding ascii -Force
Invoke-RestMethod $SetupCompleFiles/Deploy-RunOnceTask-OSUpdate.ps1 | Out-File -FilePath "$ScriptDir\Deploy-RunOnceTask-OSUpdate.ps1"
Invoke-RestMethod $SetupCompleFiles/Update-Firmware.ps1 | Out-File -FilePath "$ScriptDir\Update-Firmware.ps1" -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "$ScriptDir\start2.bin"

