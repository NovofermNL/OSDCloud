Write-Host -ForegroundColor Yellow "Starten van installatie Windows 11 25H2 NL"

#################################################################
#   TLS configuratie
#################################################################

# TLS 1.2 afdwingen, TLS 1.3 alleen als beschikbaar op het systeem
try {
    $TlsProtocol = [Net.SecurityProtocolType]::Tls12

    if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
        $TlsProtocol = $TlsProtocol -bor [Net.SecurityProtocolType]::Tls13
    }

    [Net.ServicePointManager]::SecurityProtocol = $TlsProtocol
}
catch {
    Write-Host -ForegroundColor DarkYellow "TLS configuratie kon niet volledig worden toegepast: $($_.Exception.Message)"
}

#################################################################
#   [PreOS] Update Module
#################################################################

Write-Host -ForegroundColor Green "Voorbereiden PowerShellGet / PSGallery"

try {
    Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null
}
catch {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
}
catch {
    Write-Host -ForegroundColor DarkYellow "PSGallery kon niet als Trusted worden ingesteld: $($_.Exception.Message)"
}

Write-Host -ForegroundColor Green "Updaten OSD PowerShell Module"
Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importeren OSD PowerShell Module"
Import-Module OSD -Force

#################################################################
#   OSDCloud functies laden
#################################################################

try {
    Invoke-Expression (Invoke-RestMethod -Uri 'https://functions.osdcloud.com') | Out-Null
}
catch {
    Write-Host -ForegroundColor Red "OSDCloud functies konden niet worden geladen: $($_.Exception.Message)"
}

#################################################################
#   Global.MyOSDCloud - Basisconfiguratie voor alle machines
#################################################################

$Global:MyOSDCloud = [ordered]@{
    Restart               = [bool]$false
    RecoveryPartition     = [bool]$true
    OEMActivation         = [bool]$true

    # Standaardgedrag voor niet-HP en HP zonder HPIA-support:
    # Windows updates + drivers via Windows Update
    WindowsUpdate         = [bool]$true
    WindowsUpdateDrivers  = [bool]$true

    WindowsDefenderUpdate = [bool]$false
    SetTimeZone           = [bool]$true
    ClearDiskConfirm      = [bool]$false
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$false
}

#################################################################
#   [PreOS] HP Detectie en HP-specifieke OSDCloud instellingen
#################################################################

try {
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $Manufacturer   = $ComputerSystem.Manufacturer
    $Model          = $ComputerSystem.Model

    if ($Manufacturer -match 'HP|Hewlett-Packard') {
        Write-Host -ForegroundColor Cyan "HP fabrikant gedetecteerd: $Manufacturer - $Model"

        if (Get-Command Test-HPIASupport -ErrorAction SilentlyContinue) {
            $HPIASupported = Test-HPIASupport
        }
        else {
            $HPIASupported = $false
            Write-Host -ForegroundColor DarkYellow "Test-HPIASupport is niet beschikbaar. HP-specifieke configuratie wordt overgeslagen."
        }

        if ($HPIASupported) {
            Write-Host -ForegroundColor Cyan "HP/HPIA ondersteuning gedetecteerd. HP-specifieke configuratie bepalen..."

            try {
                Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1') | Out-Null
            }
            catch {
                Write-Host -ForegroundColor Red "HP device module kon niet worden geladen: $($_.Exception.Message)"
            }

            try {
                osdcloud-InstallModuleHPCMSL | Out-Null
            }
            catch {
                Write-Host -ForegroundColor Red "HPCMSL kon niet worden geïnstalleerd of geladen: $($_.Exception.Message)"
            }

            # HP-specifieke keys worden alleen toegevoegd bij ondersteunde HP-machines
            $Global:MyOSDCloud.HPIAALL                = [bool]$false
            $Global:MyOSDCloud.HPIADrivers            = [bool]$false
            $Global:MyOSDCloud.HPCMSLDriverPackLatest = [bool]$true

            # Voor ondersteunde HP-machines gebruiken we HP/HPCMSL driverpack
            # en dus géén Windows Update drivers
            $Global:MyOSDCloud.WindowsUpdateDrivers   = [bool]$false

            # Windows quality/cumulative updates blijven wel aan
            $Global:MyOSDCloud.WindowsUpdate          = [bool]$true

            # TPM firmware dynamisch bepalen
            try {
                $TPMRequired = osdcloud-HPTPMDetermine

                if ($TPMRequired) {
                    Write-Host -ForegroundColor Yellow "HP TPM Firmware update vereist."
                    $Global:MyOSDCloud.HPTPMUpdate = [bool]$true
                }
                else {
                    Write-Host -ForegroundColor Green "HP TPM Firmware update niet vereist."
                    $Global:MyOSDCloud.HPTPMUpdate = [bool]$false
                }
            }
            catch {
                Write-Host -ForegroundColor DarkYellow "TPM update controle mislukt: $($_.Exception.Message)"
                $Global:MyOSDCloud.HPTPMUpdate = [bool]$false
            }

            # BIOS firmware dynamisch bepalen
            try {
                $BIOSRequired = osdcloud-HPBIOSDetermine

                if ($BIOSRequired -ne $false) {
                    $CurrentBIOS = Get-HPBIOSVersion
                    $LatestBIOS  = (Get-HPBIOSUpdates -Latest).ver

                    Write-Host -ForegroundColor Yellow "HP BIOS update vereist: $CurrentBIOS naar $LatestBIOS"
                    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true
                }
                else {
                    $CurrentBIOS = Get-HPBIOSVersion
                    Write-Host -ForegroundColor Green "HP BIOS is al actueel: $CurrentBIOS"
                    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$false
                }
            }
            catch {
                Write-Host -ForegroundColor DarkYellow "BIOS update controle mislukt: $($_.Exception.Message)"
                $Global:MyOSDCloud.HPBIOSUpdate = [bool]$false
            }
        }
        else {
            Write-Host -ForegroundColor DarkGray "HP-machine gedetecteerd, maar geen HPIA-ondersteuning."
            Write-Host -ForegroundColor DarkGray "Standaard Windows Update + Windows Update drivers blijven actief."
        }
    }
    else {
        Write-Host -ForegroundColor DarkGray "Geen HP-machine gedetecteerd."
        Write-Host -ForegroundColor DarkGray "Windows Update + Windows Update drivers blijven actief."
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij HP-detectie: $($_.Exception.Message)"
    Write-Host -ForegroundColor DarkYellow "Fallback: Windows Update + Windows Update drivers blijven actief."
}

#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################

$Params = @{
    OSVersion     = 'Windows 11'
    OSBuild       = '25H2'
    OSEdition     = 'Pro'
    OSLanguage    = 'nl-nl'
    OSLicense     = 'Volume'
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

$SetupCompleteDir = 'C:\OSDCloud\Scripts\SetupComplete'
if (-not (Test-Path $SetupCompleteDir)) {
    New-Item -ItemType Directory -Path $SetupCompleteDir -Force | Out-Null
}

#################################################################
#   [PostOS] Download Files
#################################################################

Write-Host -ForegroundColor Green "Download scripts voor OOBE-fase"

try {
    Invoke-WebPSScript -Uri 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Tasks/Download-GitFiles.ps1'
}
catch {
    Write-Host -ForegroundColor Red "Download-GitFiles.ps1 kon niet worden uitgevoerd: $($_.Exception.Message)"
}

#################################################################
#   [PostOS] Unattend - oobeSystem locale
#################################################################

Write-Host -ForegroundColor Green "Plaatsen Unattend.xml"

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

# Voorkom draaien in volwaardige Windows
Block-WinOS

$UnattendPath = Join-Path $Panther 'Unattend.xml'
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-Host "Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath"
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null

#################################################################
#   [PostOS] OOBE CMD Command Line
#################################################################

$OOBECMD = @'
@echo off
:: OOBE

start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Remove-AppX.ps1
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Copy-Start.ps1"

reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v SearchOnTaskbarMode /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /t REG_DWORD /d 0 /f
REM reg add "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" /v ExcludeHttpsRootDomain /t REG_DWORD /d 1 /f
REM reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v ForceClassicControlPanel /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f

reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludelastknowngoodurl /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludescplookup /t REG_DWORD /d 0 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludehttpsrootdomain /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludehttpsautodiscoverdomain /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludehttpredirect /t REG_DWORD /d 0 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v excludesrvrecord /t REG_DWORD /d 0 /f
reg add "HKLM\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover" /v disableautodiscoverv2service /t REG_DWORD /d 0 /f

:: ===== VISUAL EFFECTS =====

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ControlAnimations" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\AnimateMinMax" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\TaskbarAnimations" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\DWMAeroPeekEnabled" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\MenuAnimation" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\TooltipAnimation" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\SelectionFade" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\DWMSaveThumbnailEnabled" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\CursorShadow" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ListviewShadow" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ThumbnailsOrIcon" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ListviewAlphaSelect" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\DragFullWindows" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ComboBoxAnimation" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\FontSmoothing" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\ListBoxSmoothScrolling" /v DefaultValue /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\DropShadow" /v DefaultValue /t REG_DWORD /d 0 /f

:: ===== DEFAULT USER PROFIEL =====

reg load HKU\DefUser "C:\Users\Default\NTUSER.DAT"

reg add "HKU\DefUser\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f
reg add "HKU\DefUser\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f

reg unload HKU\DefUser

exit /b 0
'@

$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force

#################################################################
#   [PostOS] SetupComplete
#################################################################

$SetupComplete = @'
@echo off

REM start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Create-RunOnce-OSUpdate.ps1"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Create-RunOnce-CleanUp.ps1"

exit /b 0
'@

$SetupComplete | Out-File -FilePath "$SetupCompleteDir\SetupComplete.cmd" -Encoding ascii -Force

#################################################################
#   Klaar
#################################################################

Write-Host -ForegroundColor Green "Deployment Voltooid"
wpeutil reboot
