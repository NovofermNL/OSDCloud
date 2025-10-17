$ScriptName = 'Installeren Windows 11'
$ScriptVersion = '24.7.4.4'
Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"

#=======================================================================
#   OSDCLOUD Definitions
#=======================================================================
# OSDCLOUD Definitions (opgeschoond)
$OSName        = 'Windows 11 24H2 x64'
$OSEdition     = 'Pro'
$OSActivation  = 'Volume'
$OSLanguage    = 'nl-nl'

#=======================================================================
#   OSDCLOUD VARS
#=======================================================================
$Global:MyOSDCloud = [ordered]@{
    Restart             = [bool]$false
    RecoveryPartition   = [bool]$false
    OEMActivation       = [bool]$true
    WindowsUpdate       = [bool]$true
    MSCatalogFirmware   = [bool]$false
    WindowsUpdateDrivers= [bool]$true
    WindowsDefenderUpdate = [bool]$false
    SetTimeZone         = [bool]$true
    SkipClearDisk       = [bool]$false
    ClearDiskConfirm    = [bool]$false
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB= [bool]$true
    CheckSHA1           = [bool]$true
    ZTI                 = [bool]$true
}

#=======================================================================
#   LOCAL DRIVE LETTERS
#=======================================================================
function Get-WinPEDrive {
    $WinPEDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'WINPE' }).DeviceID
    write-host "Current WINPE drive is: $WinPEDrive"
    return $WinPEDrive
}

# De functie Get-OSDCloudDrive is behouden voor compatibiliteit, maar wordt niet gebruikt voor de image
function Get-OSDCloudDrive {
    $OSDCloudDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'OSDCloudUSB' }).DeviceID
    write-host "Current OSDCLOUD Drive is: $OSDCloudDrive"
    return $OSDCloudDrive
}

#=======================================================================
#   OSDCLOUD Image - Netwerk Share
#=======================================================================

# Vraag credentials op
$Credentials = Get-Credential

# Maak tijdelijk een PSDrive aan naar de share
New-PSDrive -Name "OSD" -PSProvider FileSystem -Root "\\10.101.1.20\osdeploy$" -Credential $Credentials

# Definieer het pad en bestandsnaam
$ImageNetworkPath = "OSD:\OS\W11-24H2-x64\"
$WIMName = "W11_Pro_x64_20251510.wim"
$ImageFileFullName = Join-Path -Path $ImageNetworkPath -ChildPath $WIMName

$UseLocalImage = $true
Write-Host -ForegroundColor Green -BackgroundColor Black "UseLocalImage is set to: $UseLocalImage (Netwerklocatie)"

# (optioneel) Na afloop opruimen:
# Remove-PSDrive -Name "OSD"


if ($uselocalimage -eq $true) {
    if (Test-Path $ImageFileFullName) {
        Write-Host -ForegroundColor Green -BackgroundColor Black "WIM-bestand gevonden op netwerklocatie: $ImageFileFullName. Dit bestand wordt gebruikt voor de installatie."
        
        # Stel de OSDCloud variabelen in met het netwerkpad
        $Global:MyOSDCloud.ImageFileItem = $ImageFileFullName # Belangrijk: het volledige pad wordt gebruikt
        $Global:MyOSDCloud.ImageFileName = $WIMName
        $Global:MyOSDCloud.ImageFileFullName = $ImageFileFullName
        $Global:MyOSDCloud.OSImageIndex = 1 # Meestal is de Windows Pro image index 1. Pas aan indien nodig.
        
    } else {
        Write-Host -ForegroundColor Red -BackgroundColor Black "Fout: WIM-bestand NIET gevonden op $ImageFileFullName."
        Write-Host -ForegroundColor Red -BackgroundColor Black "Controleer netwerktoegang en pad. Schakel over op de standaard OSDCloud downloadmethode."
        $uselocalimage = $false
        
        # OSDCloud Variabelen resetten voor een normale online installatie
        $Global:MyOSDCloud.ImageFileItem = $null
        $Global:MyOSDCloud.ImageFileName = $null
        $Global:MyOSDCloud.ImageFileFullName = $null
        
        Start-Sleep -Seconds 10
    }
}

#=======================================================================
#   Update OSDCloud modules
#=======================================================================
$ModulePath = (Get-ChildItem -Path "$($Env:ProgramFiles)\WindowsPowerShell\Modules\osd" | Where-Object { $_.Attributes -match "Directory" } | select -Last 1).fullname
Import-Module "$ModulePath\OSD.psd1" -Force

#=======================================================================
#   Start OSDCloud installation
#=======================================================================
Write-Host "Starting OSDCloud" -ForegroundColor Green
Write-Host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"

Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage

Write-Host "OSDCloud Process Complete, Running Custom Actions From Script Before Reboot" -ForegroundColor Green

#=======================================================================
#   Custom Actions (OOBE en SetupComplete)
#=======================================================================

Write-Host -ForegroundColor Green "Downloading and creating script for OOBE phase"

# Zorg dat de scripts-map bestaat vóór het wegschrijven
New-Item -ItemType Directory -Path 'C:\Windows\Setup\scripts' -Force | Out-Null

Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFIles/Remove-Appx.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Remove-AppX.ps1' -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "C:\Windows\Setup\scripts\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFIles/Copy-Start.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Copy-Start.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFIles/OSUpdate.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\OSUpdate.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFIles/New-ComputerName.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\New-ComputerName.ps1' -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFIles/Create-OSUpdateTask.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Create-OSUpdateTask.ps1' -Encoding ascii -Force

#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Prod/OSDCloud/Custom-Tweaks.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\Custom-Tweaks.ps1' -Encoding ascii -Force

#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Dev/OSD-CleanUp.ps1" | Out-File -FilePath 'C:\Windows\Setup\scripts\OSD-CleanUp.ps1' -Encoding ascii -Force

$OOBECMD = @'
@echo off
:: OOBE fase verwijder standaard apps en wijzig start-menu
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\scripts\Remove-AppX.ps1
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\scripts\Copy-Start.ps1
'@
$OOBECMD | Out-File -FilePath 'C:\Windows\Setup\scripts\oobe.cmd' -Encoding ascii -Force

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
reg add "HKEY_USERS\.DEFAULT\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" /v ExcludeHttpsRootDomain /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f

:: Cleanup logs en folders
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

:: Start copy-start script
echo Starten van Copy-Start.ps1 >> "%logfile%"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\Copy-Start.ps1" >> "%logfile%" 2>&1
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\New-ComputerName.ps1" >> "%logfile%" 2>&1
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\scripts\OSUpdate.ps1" >> "%logfile%" 2>&1
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
