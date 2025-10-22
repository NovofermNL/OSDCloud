# Helemaal bovenaan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force


#### functions definitions
function Write-DarkGrayDate {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [System.String]
        $Message
    )
    if ($Message) {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) $Message"
    }
    else {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
    }
}

function Write-DarkGrayHost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $Message
    )
    Write-Host -ForegroundColor DarkGray $Message
}

function Write-DarkGrayLine {
    [CmdletBinding()]
    param ()
    Write-Host -ForegroundColor DarkGray '========================================================================='
}

function Write-SectionHeader {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $Message
    )
    Write-DarkGrayLine
    Write-DarkGrayDate
    Write-Host -ForegroundColor Cyan $Message
}

function Write-SectionSuccess {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [System.String]
        $Message = 'Success!'
    )
    Write-DarkGrayDate
    Write-Host -ForegroundColor Green $Message
}

#################################################################
#   [PreOS] Update Module (robuust in WinPE)
#################################################################
Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"

# NuGet-provider en PSGallery vertrouwen (handig in WinPE/clean)
try { Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null }
catch { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }

try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch {}

Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force

#################################################################
#   Bepaal type device
#################################################################

$Product = (Get-MyComputerProduct)
$Model = (Get-MyComputerModel)
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer

#################################################################
#   [Prep] Zorg dat doelmappen bestaan
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
#   Global:MyOSDCloud
#################################################################
$Global:MyOSDCloud = [pscustomobject]([ordered]@{
    Restart               = $false
    RecoveryPartition     = $true
    OEMActivation         = $true
    WindowsUpdate         = $false
    WindowsUpdateDrivers  = $false
    WindowsDefenderUpdate = $false
    SetTimeZone           = $true
    ClearDiskConfirm      = $false
    ShutdownSetupComplete = $false
    SyncMSUpCatDriverUSB  = $true
    CheckSHA1             = $true
})
#################################################################
#   HP Functies
#################################################################
write-host -ForegroundColor Cyan "HP Functions"

#HPIA Functions
Write-Host -ForegroundColor Green "[+] Function Get-HPIALatestVersion"
Write-Host -ForegroundColor Green "[+] Function Install-HPIA"
Write-Host -ForegroundColor Green "[+] Function Run-HPIA"
Write-Host -ForegroundColor Green "[+] Function Get-HPIAXMLResult"
Write-Host -ForegroundColor Green "[+] Function Get-HPIAJSONResult"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/HPIA/HPIA-Functions.ps1)

#HP CMSL WinPE replacement
Write-Host -ForegroundColor Green "[+] Function Get-HPOSSupport"
Write-Host -ForegroundColor Green "[+] Function Get-HPSoftpaqListLatest"
Write-Host -ForegroundColor Green "[+] Function Get-HPSoftpaqItems"
Write-Host -ForegroundColor Green "[+] Function Get-HPDriverPackLatest"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/OSDeploy/OSD/master/Public/OSDCloudTS/Test-HPIASupport.ps1)

#Install-ModuleHPCMSL
Write-Host -ForegroundColor Green "[+] Function Install-ModuleHPCMSL"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/EMPS/Install-ModuleHPCMSL.ps1)

Write-Host -ForegroundColor Green "[+] Function Invoke-HPAnalyzer"
Write-Host -ForegroundColor Green "[+] Function Invoke-HPDriverUpdate"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/EMPS/Invoke-HPDriverUpdate.ps1)

#Enable HPIA | Update HP BIOS | Update HP TPM 
if (Test-HPIASupport) {
    Write-SectionHeader -Message "Detected HP Device, Enabling HPIA, HP BIOS and HP TPM Updates"
    $Global:MyOSDCloud.DevMode = [bool]$true
    $Global:MyOSDCloud.HPTPMUpdate = [bool]$true
	
    $Global:MyOSDCloud.HPIAALL = [bool]$false
    $Global:MyOSDCloud.HPIADrivers = [bool]$true
    $Global:MyOSDCloud.HPIASoftware = [bool]$false
    $Global:MyOSDCloud.HPIAFirmware = [bool]$true	
    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true
    $Global:MyOSDCloud.HPBIOSWinUpdate = [bool]$false   
    
    write-host "Setting DriverPackName to 'None'"
    $Global:MyOSDCloud.DriverPackName = "None"
}

$DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID
if ($DriverPack) {
    $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
}

#write variables to console
Write-SectionHeader "OSDCloud Variables"
Write-Output $Global:MyOSDCloud

#### important OS variables
$OSVersion = 'Windows 11'
$OSReleaseID = '24H2'
$OSName = 'Windows 11 23H2 x64'
$OSEdition = 'Enterprise'
$OSActivation = 'Retail'
$OSLanguage = 'nl-nl'

#################################################################
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion     = $OSVersion
    OSBuild       = $OSReleaseID
    OSEdition     = "$OSEdition
    OSLanguage    = nl-nl
    OSLicense     = $OSLanguage
    ZTI           = $true
    Firmware      = $false
    SkipAutopilot = $false
}

Start-OSDCloud @Params

#################################################################
#   Uitpakken, importeren en verwijderen van driverpack
#################################################################

$driverpackDetails = Get-HPDriverPackLatest
$driverpackID = $driverpackDetails.Id
[string]$ToolLocation = "C:\Drivers"

$ToolPath = "$ToolLocation\$driverpackID.exe"
if (!(Test-Path -Path $ToolPath)) {
    Write-Output "Unable to find $ToolPath"
    pause
    Exit -1
}

#$ToolArg = "/s /f C:\Drivers\"
#$Process = Start-Process -FilePath $ToolPath -ArgumentList $ToolArg -Wait -PassThru

Dism /Image:C: /Add-Driver /Driver:C:\Drivers /Recurse

#################################################################
#   Download Files 
#################################################################
# PS-scripts als UTF8 met BOM wegschrijven
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" | Out-File -FilePath "$ScriptDir\Remove-AppX.ps1" -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "$ScriptDir\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1" | Out-File -FilePath "$ScriptDir\Copy-Start.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\OSUpdate.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" | Out-File -FilePath "$ScriptDir\New-ComputerName.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Deploy-RunOnceTask-OSUpdate.ps1" | Out-File -FilePath "$ScriptDir\Deploy-RunOnceTask-OSUpdate.ps1"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Update-Firmware.ps1" | Out-File -FilePath "$ScriptDir\Update-Firmware.ps1" -Encoding ascii -Force

#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Prod/OSDCloud/Custom-Tweaks.ps1" | Out-File -FilePath "$ScriptDir\Custom-Tweaks.ps1" -Encoding ascii -Force
#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Dev/OSD-CleanUp.ps1" | Out-File -FilePath "$ScriptDir\OSD-CleanUp.ps1" -Encoding ascii -Force

#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Prod/OSDCloud/Custom-Tweaks.ps1" | Out-File -FilePath "$ScriptDir\Custom-Tweaks.ps1" -Encoding utf8BOM -Force
#Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/Public/main/Dev/OSD-CleanUp.ps1" | Out-File -FilePath "$ScriptDir\OSD-CleanUp.ps1" -Encoding utf8BOM -Force

#=================================================
Write-SectionHeader "[PostOS] Unattend (oobeSystem locale)"
#=================================================
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
      <InputLocale>en-US</InputLocale>
      <SystemLocale>nl-NL</SystemLocale>
      <UILanguage>nl-NL</UILanguage>
      <UserLocale>nl-NL</UserLocale>
    </component>
  </settings>
</unattend>
'@

# Voorkom draaien in volwaardige Windows (dit hoort in WinPE)
Block-WinOS

$UnattendPath = Join-Path $Panther 'Unattend.xml'
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-DarkGrayHost "Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath"
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null

#================================================
Write-SectionHeader "[PostOS] OOBE CMD Command Line"
#================================================
$OOBECMD = @'
@echo off
:: OOBE fase: verwijder standaard apps
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\Remove-AppX.ps1
'@
$OOBECMD | Out-File -FilePath "$ScriptDir\oobe.cmd" -Encoding ascii -Force

#================================================
#    SetupComplete
#================================================
Write-SectionHeader "Maak SetupComplete file"

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
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Deploy-RunOnceTask-OSUpdate.ps1" >> "%logfile%" 2>&1

echo Starten van OSUpdate.ps1 >> "%logfile%"
:: start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\OSUpdate.ps1" >> "%logfile%" 2>&1

echo === SetupComplete Afgerond %date% %time% === >> "%logfile%"

exit /b 0
'@

# Schrijf het SetupComplete script weg
$SetupComplete | Out-File -FilePath "$ScriptDir\SetupComplete.cmd" -Encoding ascii -Force

#================================================
#    Einde  Deployment
#================================================
Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
Start-Sleep -Seconds 20
wpeutil reboot
