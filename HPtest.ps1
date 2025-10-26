Write-Host -ForegroundColor Yellow "Starten van installatie Windows 11 24H2 NL"

#################################################################
#   [PreOS] Update Module
#################################################################
Write-Host -ForegroundColor Green "Updaten OSD PowerShell Module"

# NuGet-provider en PSGallery vertrouwen (handig in WinPE/clean)
try { Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null }
catch { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }

try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch {}

Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importeren OSD PowerShell Module"
Import-Module OSD -Force

#################################################################
#   Global.MyOSDCloud
#################################################################

$Global:MyOSDCloud = [ordered]@{
    Restart               = [bool]$False
    RecoveryPartition     = [bool]$true
    OEMActivation         = [bool]$false
    WindowsUpdate         = [bool]$true
    WindowsUpdateDrivers  = [bool]$true
    WindowsDefenderUpdate = [bool]$true
    SetTimeZone           = [bool]$true
    ClearDiskConfirm      = [bool]$False
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$true
}


#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion     = "Windows 11"
    OSBuild       = "24H2"
    OSEdition     = "Pro"
    OSLanguage    = "nl-nl"
    OSLicense     = "Retail"
    ZTI           = $true
    Firmware      = $true
    SkipAutopilot = $false
}
Start-OSDCloud @Params

#################################################################
#   [PostOS] Zorg dat doelmappen bestaan
#################################################################
$ScriptDir = 'C:\Windows\Setup\Scripts'
if (-not (Test-Path $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
}

$Panther = 'C:\Windows\Panther'
if (-not (Test-Path $Panther)) {
    New-Item -ItemType Directory -Path $Panther -Force | Out-Null
}

#################################################################
#   [PostOS] Download Files 
#################################################################

Write-Host -ForegroundColor Green "Download scripts voor OOBE-fase"

New-Item -ItemType Directory -Path 'C:\Windows\Setup\scripts' -Force | Out-Null

Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" | Out-File -FilePath "$ScriptDir\Remove-AppX.ps1" -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "$ScriptDir\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1" | Out-File -FilePath "$ScriptDir\Copy-Start.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\OSUpdate.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" | Out-File -FilePath "$ScriptDir\New-ComputerName.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Deploy-RunOnceTask-OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\Deploy-RunOnceTask-OSUpdate.ps1"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Update-Firmware.ps1" | Out-File -FilePath "$ScriptDir\Update-Firmware.ps1" -Encoding ascii -Force

#=================================================
#    [PostOS] Unattend (oobeSystem locale)"
#=================================================

Write-Host -ForegroundColor Green "Plaatsen UnattendXml"

$UnattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>0409:00020409</InputLocale>
      <UserLocale>nl-NL</UserLocale>
    </component>
  </settings>
</unattend>
'@

# Voorkom draaien in volwaardige Windows
Block-WinOS

$UnattendPath = Join-Path $Panther 'Unattend.xml'
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-Host "Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath"
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null

#================================================
#    [PostOS] OOBE CMD Command Line
#================================================
$OOBECMD = @'
@echo off
:: OOBE fase: verwijder standaard apps
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Remove-AppX.ps1
'@
$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force

#================================================
#    [PostOS] SetupComplete
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
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v ForceClassicControlPanel /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f


:: ===== DEFAULT USER-PROFIEL =====
echo === Default user tweaks laden %date% %time% === >> "%logfile%"
reg load HKU\DefUser "C:\Users\Default\NTUSER.DAT" >> "%logfile%" 2>&1
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >> "%logfile%" 2>&1
reg add "HKU\DefUser\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f >> "%logfile%" 2>&1
reg unload HKU\DefUser >> "%logfile%" 2>&1
echo === Default user tweaks klaar %date% %time% === >> "%logfile%"

:: ===== Cleanup logs en folders =====
echo === Start Cleanup %date% %time% === >> "%logfile%"
if exist "C:\Windows\Temp" copy /Y "C:\Windows\Temp\*.log" "%logfolder%" >> "%logfile%" 2>&1
if exist "C:\Temp" copy /Y "C:\Temp\*.log" "%logfolder%" >> "%logfile%" 2>&1
if exist "C:\OSDCloud\Logs" copy /Y "C:\OSDCloud\Logs\*.log" "%logfolder%" >> "%logfile%" 2>&1
if exist "C:\ProgramData\OSDeploy" copy /Y "C:\ProgramData\OSDeploy\*.log" "%logfolder%" >> "%logfile%" 2>&1

for %%D in ("C:\OSDCloud" "C:\Drivers" "C:\Intel" "C:\ProgramData\OSDeploy") do (
  if exist %%D (
    echo Removing folder %%D >> "%logfile%"
    rmdir /S /Q %%D >> "%logfile%" 2>&1
  )
)

:: ===== Post-install acties =====
echo Starten van Copy-Start.ps1 >> "%logfile%"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Copy-Start.ps1" >> "%logfile%" 2>&1

echo Starten van Update-Firmware.ps1 >> "%logfile%"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Deploy-RunOnceTask-OSUpdate" >> "%logfile%" 2>&1

echo Starten van OSUpdate.ps1 >> "%logfile%"
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\OSUpdate.ps1" >> "%logfile%" 2>&1

echo === SetupComplete Afgerond %date% %time% === >> "%logfile%"

exit /b 0
'@

# Schrijf het SetupComplete script weg
$SetupComplete | Out-File -FilePath "$ScriptDir\SetupComplete.cmd" -Encoding ascii -Force

#################################################################
#   [PreOS] HP updates (HPIA/BIOS/TPM) – alleen op HP devices
#################################################################
try {
    $Product = Get-MyComputerProduct
    $Model   = Get-MyComputerModel

    if (Test-HPIASupport) {
        Write-Host -ForegroundColor Cyan "HP device gedetecteerd. HPIA/BIOS/TPM updates inschakelen"

        # Altijd BIOS en TPM updates toestaan op HP
        $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true
        $Global:MyOSDCloud.HPTPMUpdate  = [bool]$true

        # HPIA all enable, behalve bij uitzonderingen
        if ($Product -ne '83B2' -and $Model -notmatch 'zbook') {
            $Global:MyOSDCloud.HPIAALL = [bool]$false
        } else {
            Write-Host -ForegroundColor DarkYellow "HPIAALL overgeslagen voor model/product: $Model / $Product"
        }

        # Optioneel: CMSL latest driver pack forceren (nu uit)
         $Global:MyOSDCloud.HPCMSLDriverPackLatest = [bool]$true
    }
    else {
        Write-Host -ForegroundColor DarkGray "Geen HP/HPIA-ondersteuning gedetecteerd. HP-specifieke updates worden niet geactiveerd"
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij HP-detectie/HPIA: $($_.Exception.Message)"
}

#=======================================================================
#  [PostOS] Driver Management voor Microsoft Surface devices
#=======================================================================

try {
    $Product = Get-MyComputerProduct

    if ($Product -match 'Surface') {
        Write-Host -ForegroundColor Cyan "Surface gedetecteerd ($Product) – Surface driver script uitvoeren"
        Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Surface/MicrosoftSurfaceDriverIssue.ps1').Content
    }
    else {
        Write-Host -ForegroundColor DarkGray "Geen Surface gedetecteerd (Product: $Product) – Surface script overgeslagen"
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij Surface-detectie of uitvoering: $($_.Exception.Message)"
}


# Herstart na 20 seconden
#Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
#Start-Sleep -Seconds 20
#wpeutil reboot
