Write-Host -ForegroundColor Yellow "Starten van installatie Windows 11 25H2 NL"

# TLS 1.2 afdwingen voor alle webrequests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
# Standaard instellingen (voor Non-HP apparaten)
$HPTPMUpdate               = $false
$HPBIOSUpdate              = $false
$HPCMSLDrivers             = $false
$WindowsUpdateDriversEnabled = $true   # Standaard AAN

try {
    # Laad de benodigde OSDCloud functies
    Invoke-Expression (Invoke-RestMethod -Uri 'functions.osdcloud.com') | Out-Null

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $Manufacturer = $cs.Manufacturer

    if ($Manufacturer -match 'HP' -or $Manufacturer -match 'Hewlett-Packard') {
        $HPEnterprise = Test-HPIASupport

        if ($HPEnterprise) {
            $Model = $cs.Model
            Write-Host -ForegroundColor Cyan "HP device gedetecteerd ($Model). Dynamische updates bepalen..."

            Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1') | Out-Null
            osdcloud-InstallModuleHPCMSL | Out-Null

            $TPM  = osdcloud-HPTPMDetermine
            $BIOS = osdcloud-HPBIOSDetermine

            $HPCMSLDrivers             = $true
            $WindowsUpdateDriversEnabled = $false

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
        else {
            Write-Host -ForegroundColor DarkGray "HP gedetecteerd, maar geen HPIA-ondersteuning. Standaard driverlogica wordt gebruikt."
        }
    }
    else {
        Write-Host -ForegroundColor DarkGray "Geen HP/HPIA-ondersteuning gedetecteerd. Gebruikt standaard driverlogica."
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij dynamische HP-detectie/HPIA: $($_.Exception.Message). Gebruikt standaard driverlogica."

    $HPTPMUpdate               = $true
    $HPBIOSUpdate              = $true
    $HPCMSLDrivers             = $true
    $WindowsUpdateDriversEnabled = $true
}

#################################################################
#   Global.MyOSDCloud
#################################################################

$Global:MyOSDCloud = [ordered]@{
    Restart                 = [bool]$false
    RecoveryPartition       = [bool]$true
    OEMActivation           = [bool]$true
    WindowsUpdate           = [bool]$false
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
    OSBuild       = '25H2'     # Aangepast zodat dit overeenkomt met je banner
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
#    [PostOS] Unattend (oobeSystem locale)"
#=================================================

Write-Host -ForegroundColor Green "Plaatsen UnattendXml"

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

#================================================
#    [PostOS] OOBE CMD Command Line
#================================================
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
REM reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v ForceClassicControlPanel /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f


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

reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f
reg add "HKU\DefUser\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f
reg add "HKU\DefaultUser\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /d "" /f

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

# Schrijf het SetupComplete script weg
#$SetupComplete | Out-File -FilePath "$ScriptDir\SetupComplete.cmd" -Encoding ascii -Force
$SetupComplete | Out-File -FilePath "C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd" -Encoding ascii -Force 

Write-Host -ForegroundColor Green "Deployment Voltooid"
# Herstart na 20 seconden
#Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
#Start-Sleep -Seconds 20
wpeutil reboot
