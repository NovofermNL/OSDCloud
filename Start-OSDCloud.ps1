Write-Host -ForegroundColor Yellow "Starten van installatie Windows 11 25H2 NL"

# TLS 1.2 en 1.3 afdwingen voor alle webrequests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

#################################################################
#   [PreOS] Update Module
#################################################################
Write-Host -ForegroundColor Green "Updaten OSD PowerShell Module"
Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importeren OSD PowerShell Module"
Import-Module OSD -Force

#################################################################
#   [PreOS] Dynamische HP Configuratie bepalen
#################################################################
$HPTPMUpdate                 = $false
$HPBIOSUpdate                = $false
$HPCMSLDrivers               = $false
$WindowsUpdateDriversEnabled = $true

try {
    Invoke-Expression (Invoke-RestMethod -Uri 'functions.osdcloud.com') | Out-Null

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $Manufacturer = $cs.Manufacturer

    if ($Manufacturer -match 'HP|Hewlett-Packard') {
        if (Get-Command Test-HPIASupport -ErrorAction SilentlyContinue) {
            $HPEnterprise = Test-HPIASupport

            if ($HPEnterprise) {
                $Model = $cs.Model
                Write-Host -ForegroundColor Cyan "HP device gedetecteerd ($Model). Dynamische updates bepalen..."

                Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1') | Out-Null
                osdcloud-InstallModuleHPCMSL | Out-Null

                $TPM  = osdcloud-HPTPMDetermine
                $BIOS = osdcloud-HPBIOSDetermine

                $HPCMSLDrivers               = $true
                $WindowsUpdateDriversEnabled = $true

                if ($TPM) {
                    Write-Host -ForegroundColor Yellow "HP Update TPM Firmware vereist."
                    $HPTPMUpdate = $true
                }

                if ($BIOS -ne $false) {
                    $LatestVer  = (Get-HPBIOSUpdates -Latest).ver
                    $CurrentVer = Get-HPBIOSVersion
                    Write-Host -ForegroundColor Yellow "HP Update System Firmware vereist (van $CurrentVer naar $LatestVer)."
                    $HPBIOSUpdate = $true
                }
                else {
                    $CurrentVer = Get-HPBIOSVersion
                    Write-Host -ForegroundColor Green "HP System Firmware is al actueel: $CurrentVer"
                }
            }
        }
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij dynamische HP-detectie: $($_.Exception.Message)."
}

#################################################################
#   Global.MyOSDCloud
#################################################################
$Global:MyOSDCloud = [ordered]@{
    Restart                 = [bool]$true
    RecoveryPartition       = [bool]$true
    OEMActivation           = [bool]$true
    WindowsUpdate           = [bool]$true
    WindowsUpdateDrivers    = [bool]$WindowsUpdateDriversEnabled
    WindowsDefenderUpdate   = [bool]$false
    SetTimeZone             = [bool]$true
    ClearDiskConfirm        = [bool]$false
    ShutdownSetupComplete   = [bool]$false
    SyncMSUpCatDriverUSB    = [bool]$true
    CheckSHA1               = [bool]$true
    HPBIOSUpdate            = [bool]$HPBIOSUpdate
    HPTPMUpdate             = [bool]$HPTPMUpdate
    HPIAALL                 = [bool]$false
    HPCMSLDriverPackLatest  = [bool]$HPCMSLDrivers
}

#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion     = 'Windows 11'
    OSBuild       = '25H2'
    OSEdition     = 'Pro'
    OSLanguage    = 'nl-nl'
    OSLicense     = 'Retail'
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
Invoke-WebPSScript -Uri 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Tasks/Download-GitFiles.ps1'

#=================================================
#    [PostOS] Unattend (oobeSystem locale)
#=================================================
$UnattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
      processorArchitecture="amd64"
      publicKeyToken="31bf3856ad364e35"
      language="neutral"
      versionScope="nonSxS"
      xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>00413:00020409</InputLocale>
      <SystemLocale>nl-NL</SystemLocale>
      <UserLocale>nl-NL</UserLocale>
      <UILanguage>nl-NL</UILanguage>
      <UILanguageFallback>nl-NL</UILanguageFallback>
    </component>
  </settings>
</unattend>
"@

Block-WinOS
$UnattendPath = Join-Path $Panther 'Unattend.xml'
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null

#================================================
#    [PostOS] OOBE CMD Command Line
#================================================
$OOBECMD = @'
@echo off
:: OOBE Scripts
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Remove-AppX.ps1
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Copy-Start.ps1"

:: Privacy, Telemetrie & Systeem optimalisaties (Machine niveau)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" /v DisableInventory /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v ForceClassicControlPanel /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f

:: ===== DEFAULT USER PROFIEL (Voor instellingen per gebruiker) =====
reg load HKU\DefUser "C:\Users\Default\NTUSER.DAT"

:: Klassiek Rechtermuisknop Menu
reg add "HKU\DefUser\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve

:: UI Optimalisaties & Visuele Effecten (Performance mode)
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f
reg add "HKU\DefUser\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f

reg unload HKU\DefUser
exit /b 0
'@
$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force

#================================================
#    [PostOS] SetupComplete
#================================================
$SetupComplete = @'
@echo off
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Create-RunOnce-OSUpdate.ps1"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Create-RunOnce-CleanUp.ps1"
exit /b 0
'@

$SetupComplete | Out-File -FilePath "$ScriptDir\SetupComplete.cmd" -Encoding ascii -Force 

Write-Host -ForegroundColor Green "Deployment Voltooid"
wpeutil reboot
