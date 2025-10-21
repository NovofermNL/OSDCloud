kun je hem even checken op fouten 

#################################################################
#   [PreOS] Update Module
#################################################################
Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host  -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force   

#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion = "Windows 11"
    OSBuild = "24H2"
    OSEdition = "Pro"
    OSLanguage = "nl-nl"
    OSLicense = "Retail"
    ZTI = $true
    Firmware = $false
    SkipAutopilot = $false
}
Start-OSDCloud @Params


#################################################################
Write-SectionHeader "Download Script files"
#################################################################

Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Remove-AppX.ps1' -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "C:\Windows\Setup\scripts\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Copy-Start.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\OSUpdate.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\New-ComputerName.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Deploy-RunOnceTask-OSUpdate.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Deploy-RunOnceTask-OSUpdate.ps1' -Encoding utf8BOM -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/refs/heads/main/SetupCompleteFiles/Update-Firmware.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Update-Firmware.ps1' -Encoding ascii -Force

#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Prod/OSDCloud/Custom-Tweaks.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Custom-Tweaks.ps1' -Encoding ascii -Force
#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Dev/OSD-CleanUp.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\OSD-CleanUp.ps1' -Encoding ascii -Force

#=================================================
Write-SectionHeader "[PostOS] Define Specialize Phase"
#=================================================
$UnattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>nl-NL</SystemLocale>
            <UILanguage>nl-NL</UILanguage>
            <UserLocale>nl-NL</UserLocale>
        </component>
    </settings>
</unattend>
'@ 
# Get-OSDGather -Property IsWinPE
Block-WinOS

if (-NOT (Test-Path 'C:\Windows\Panther')) {
    New-Item -Path 'C:\Windows\Panther'-ItemType Directory -Force -ErrorAction Stop | Out-Null
}

$Panther = 'C:\Windows\Panther'
$UnattendPath = "$Panther\Unattend.xml"
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-DarkGrayHost "Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath"
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null
#endregion

#================================================
Write-SectionHeader "[PostOS] OOBE CMD Command Line"
#================================================
$OOBECMD = @'
@echo off
:: OOBE fase verwijder standaard apps en wijzig start-menu
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\scripts\Remove-AppX.ps1
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\scripts\Copy-Start.ps1
'@
$OOBECMD | Out-File -FilePath 'C:\Windows\Setup\scripts\oobe.cmd' -Encoding ascii -Force


#================================================
Write-SectionHeader "Maak SetupComplete file"
#================================================
$SetupComplete = @'
@echo off
:: Setup logging
for /f %%a in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyy-MM-dd-HHmmss')"') do set logname=%%a-Cleanup-Script.log
set logfolder=C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD
set logfile=%logfolder%\%logname%

:: Zorg dat logmap bestaat
if not exist "%logfolder%" mkdir "%logfolder%"

:: Zet drive naar C:
C:

reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v SearchOnTaskbarMode /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" /v ExcludeHttpsRootDomain /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f

:: ===== DEFAULT USER-PROFIEL =====
echo === Default user tweaks laden %date% %time% === >> "%logfile%"
reg load HKU\DefUser "C:\Users\Default\NTUSER.DAT" >> "%logfile%" 2>&1

reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >> "%logfile%" 2>&1
reg add "HKU\DefUser\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f >> "%logfile%" 2>&1
reg unload HKU\DefUser >> "%logfile%" 2>&1

echo === Default user tweaks klaar %date% %time% === >> "%logfile%"

:: ===== Cleanup logs en folders =====
echo === Start Cleanup %date% %time% === >> "%logfile%"
if exist "C:\Windows\Temp" (
    copy /Y "C:\Windows\Temp\*.log" "%logfolder%" >> "%logfile%" 2>&1
)
if exist "C:\Temp" (
    copy /Y "C:\Temp\*.log" "%logfolder%" >> "%logfile%" 2>&1
)
if exist "C:\OSDCloud\Logs" (
    copy /Y "C:\OSDCloud\Logs\*.log" "%logfolder%" >> "%logfile%" 2>&1
)
if exist "C:\ProgramData\OSDeploy" (
    copy /Y "C:\ProgramData\OSDeploy\*.log" "%logfolder%" >> "%logfile%" 2>&1
)

for %%D in (
    "C:\OSDCloud"
    "C:\Drivers"
    "C:\Intel"
    "C:\ProgramData\OSDeploy"
) do (
    if exist %%D (
        echo Removing folder %%D >> "%logfile%"
        rmdir /S /Q %%D >> "%logfile%" 2>&1
    )
)

:: ===== Post-install acties =====
echo Starten van Copy-Start.ps1 >> "%logfile%"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\Copy-Start.ps1" >> "%logfile%" 2>&1
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\Update-Firmware.ps1.ps1" >> "%logfile%" 2>&1
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\OSUpdate.ps1" >> "%logfile%" 2>&1

echo Starten van Create-OSUpdateTask.ps1 >> "%logfile%"
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\Create-OSUpdateTask.ps1" >> "%logfile%" 2>&1

::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\New-ComputerName.ps1" >> "%logfile%" 2>&1

::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\Create-ScheduledTask.ps1" >> "%logfile%" 2>&1

echo === SetupComplete Afgerond %date% %time% === >> "%logfile%"

exit /b 0
'@

# Schrijf het SetupComplete script weg
$SetupComplete | Out-File -FilePath 'C:\Windows\Setup\scripts\SetupComplete.cmd' -Encoding ascii -Force

# Herstart na 20 seconden
Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
Start-Sleep -Seconds 20
wpeutil reboot
