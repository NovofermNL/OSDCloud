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
    WindowsDefenderUpdate = [bool]$false
    SetTimeZone           = [bool]$true
    ClearDiskConfirm      = [bool]$False
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$true
}

#=======================================================================
#  [PostOS] HP Driver/BIOS/TPM (HPIA) – Detectie en instellingen
#=======================================================================

try {
    $Product = Get-MyComputerProduct
    $Model   = Get-MyComputerModel

    if (Test-HPIASupport) {
        Write-Host -ForegroundColor Cyan "HP device gedetecteerd ($Model / $Product). HPIA/BIOS/TPM updates inschakelen"

        # TPM + BIOS updates via HP-functies van OSDCloud
        $Global:MyOSDCloud.HPTPMUpdate  = $true
        $Global:MyOSDCloud.HPBIOSUpdate = $true

        # Alleen HPIA Drivers (geen Software/Firmware via HPIA)
        $Global:MyOSDCloud.HPIADrivers = $true
        $Global:MyOSDCloud.HPIAALL = $false

        # Optioneel: nieuwste HP-driverpack via HPCMSL
        $Global:MyOSDCloud.HPCMSLDriverPackLatest = $true

        # Drivers niet meer via Windows Update
        $Global:MyOSDCloud.WindowsUpdateDrivers = $false
    }
    else {
        Write-Host -ForegroundColor DarkGray "Geen HP/HPIA-ondersteuning gedetecteerd. HP-specifieke updates worden niet geactiveerd."
    }
}
catch {
    Write-Host -ForegroundColor Red "Fout bij HP-detectie/HPIA: $($_.Exception.Message)"
}




#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion     = "Windows 11"
    OSBuild       = "25H2"
    OSEdition     = "Enterprise"
    OSLanguage    = "nl-nl"
    OSLicense     = "Volume"
    ZTI           = $true
    Firmware      = $true
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
reg add "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" /v ExcludeHttpsRootDomain /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f
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

reg unload HKU\DefUser

exit /b 0

'@
$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force

#================================================
#    [PostOS] SetupComplete
#================================================

$SetupComplete = @'
@echo off

REM start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Create-RunOnce-OSUpdate.ps1"
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
#wpeutil reboot
