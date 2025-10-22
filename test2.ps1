# ============================================
#  OSDCloud + HP (HPIA/CMSL) – WinPE script
#  Dominic Bruins – complete, gepatchte versie
# ============================================

# --- Basis: TLS12 + ExecutionPolicy + transcript logging
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$tsPath = "C:\Windows\Temp\OSDCloud-$(Get-Date -f yyyyMMdd-HHmmss).log"
try { Start-Transcript -Path $tsPath -ErrorAction SilentlyContinue } catch {}

# --- Console helpers
$Global:ConsoleDateFmt = 'dd-MM-yyyy HH:mm:ss'   # voor scherm
function Write-DarkGrayDate {
    [CmdletBinding()]
    param([string]$Message)
    $ts = (Get-Date).ToString($Global:ConsoleDateFmt)
    if ($Message) { Write-Host -ForegroundColor DarkGray "$ts $Message" }
    else { Write-Host -ForegroundColor DarkGray "$ts " -NoNewline }
}
function Write-DarkGrayHost { [CmdletBinding()] param([Parameter(Mandatory)][string]$Message) ; Write-Host -ForegroundColor DarkGray $Message }
function Write-DarkGrayLine { [CmdletBinding()] param() ; Write-Host -ForegroundColor DarkGray '=========================================================================' }
function Write-SectionHeader { [CmdletBinding()] param([Parameter(Mandatory)][string]$Message) ; Write-DarkGrayLine; Write-DarkGrayDate; Write-Host -ForegroundColor Cyan $Message }
function Write-SectionSuccess { [CmdletBinding()] param([string]$Message='Success!') ; Write-DarkGrayDate; Write-Host -ForegroundColor Green $Message }

# --- [PreOS] OSD module updaten en importeren
Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
try { Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null } catch { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }
try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch {}
Install-Module OSD -Force -ErrorAction SilentlyContinue
Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force

# --- Device info
$Product      = Get-MyComputerProduct
$Model        = Get-MyComputerModel
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer

# --- Doelmappen
$ScriptDir = 'C:\Windows\Setup\Scripts'
if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null }
$Panther = 'C:\Windows\Panther'
if (-not (Test-Path $Panther)) { New-Item -ItemType Directory -Path $Panther -Force | Out-Null }

# --- MyOSDCloud (als object, zodat dot-assignments werken)
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

# --- HP functies laden
Write-Host -ForegroundColor Cyan "HP Functions"

Write-Host -ForegroundColor Green "[+] Function Get-HPIALatestVersion"
Write-Host -ForegroundColor Green "[+] Function Install-HPIA"
Write-Host -ForegroundColor Green "[+] Function Run-HPIA"
Write-Host -ForegroundColor Green "[+] Function Get-HPIAXMLResult"
Write-Host -ForegroundColor Green "[+] Function Get-HPIAJSONResult"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/HPIA/HPIA-Functions.ps1)

Write-Host -ForegroundColor Green "[+] Function Get-HPOSSupport"
Write-Host -ForegroundColor Green "[+] Function Get-HPSoftpaqListLatest"
Write-Host -ForegroundColor Green "[+] Function Get-HPSoftpaqItems"
Write-Host -ForegroundColor Green "[+] Function Get-HPDriverPackLatest"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/OSDeploy/OSD/master/Public/OSDCloudTS/Test-HPIASupport.ps1)

Write-Host -ForegroundColor Green "[+] Function Install-ModuleHPCMSL"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/EMPS/Install-ModuleHPCMSL.ps1)

Write-Host -ForegroundColor Green "[+] Function Invoke-HPAnalyzer"
Write-Host -ForegroundColor Green "[+] Function Invoke-HPDriverUpdate"
Invoke-Expression (Invoke-RestMethod https://raw.githubusercontent.com/gwblok/garytown/master/hardware/HP/EMPS/Invoke-HPDriverUpdate.ps1)

# --- Enable HPIA / BIOS / TPM wanneer HP
if (Test-HPIASupport) {
    Write-SectionHeader -Message "Detected HP Device, enabling HPIA, HP BIOS and HP TPM updates"
    $Global:MyOSDCloud.DevMode         = $true
    $Global:MyOSDCloud.HPTPMUpdate     = $true
    $Global:MyOSDCloud.HPIAALL         = $false
    $Global:MyOSDCloud.HPIADrivers     = $true
    $Global:MyOSDCloud.HPIASoftware    = $false
    $Global:MyOSDCloud.HPIAFirmware    = $true
    $Global:MyOSDCloud.HPBIOSUpdate    = $true
    $Global:MyOSDCloud.HPBIOSWinUpdate = $false
    Write-Host "Setting DriverPackName to 'None'"
    $Global:MyOSDCloud.DriverPackName  = "None"
}

# --- Belangrijke OS-variabelen (moet vóór Get-OSDCloudDriverPack)
$OSVersion    = 'Windows 11'
$OSReleaseID  = '24H2'
$OSEdition    = 'Pro'
$OSLanguage   = 'nl-nl'
$OSActivation = 'Retail'

# --- OSDCloud DriverPack-naam optioneel bepalen
$DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID
if ($DriverPack) { $Global:MyOSDCloud.DriverPackName = $DriverPack.Name }

# --- Debug output
Write-SectionHeader "OSDCloud Variables"
$Global:MyOSDCloud | Out-Host

# --- Start OSDCloud
Write-SectionHeader -Message "Starting OSDCloud"
$Params = @{
    OSVersion     = $OSVersion
    OSBuild       = $OSReleaseID
    OSEdition     = $OSEdition
    OSLanguage    = $OSLanguage
    OSLicense     = $OSActivation
    ZTI           = $true
    Firmware      = $false
    SkipAutopilot = $false
}
Start-OSDCloud @Params

Write-SectionHeader -Message "OSDCloud complete, running custom actions prior to reboot"

# --- HP Driver Pack: download → uitpak → inject → cleanup
Install-ModuleHPCMSL  # echt uitvoeren, niet alleen definiëren

$driverpackDetails = Get-HPDriverPackLatest
if (-not $driverpackDetails) { Write-Error "Geen HP driverpack gevonden."; Start-Sleep 10; exit 1 }

$driverpackID  = $driverpackDetails.Id
$ToolLocation  = "C:\Drivers"
New-Item -ItemType Directory -Path $ToolLocation -Force | Out-Null
$ToolPath      = Join-Path $ToolLocation "$driverpackID.exe"

# Download
if (-not (Test-Path $ToolPath)) {
    if ($driverpackDetails.Url) {
        Write-DarkGrayHost "Downloading driverpack: $($driverpackDetails.Url)"
        Invoke-WebRequest -Uri $driverpackDetails.Url -OutFile $ToolPath -UseBasicParsing
    } elseif (Get-Command -Name Save-HPDriverPack -ErrorAction SilentlyContinue) {
        Write-DarkGrayHost "Saving driverpack via Save-HPDriverPack to $ToolLocation"
        Save-HPDriverPack -Destination $ToolLocation | Out-Null
        $ToolPath = (Get-ChildItem $ToolLocation -Filter *.exe | Sort-Object LastWriteTime -desc | Select-Object -First 1).FullName
    } else {
        Write-Error "Geen downloadmethode (Url/Save-HPDriverPack) beschikbaar."
        Start-Sleep 10; exit 1
    }
}
if (-not (Test-Path $ToolPath)) { Write-Error "Driverpack EXE niet aanwezig op $ToolPath"; Start-Sleep 10; exit 1 }

# Uitpakken naar C:\Drivers
$ToolArg = '/s /f C:\Drivers\'
$proc = Start-Process -FilePath $ToolPath -ArgumentList $ToolArg -Wait -PassThru
if ($proc.ExitCode -ne 0) { Write-Error "Uitpakken driverpack faalde: $($proc.ExitCode)"; Start-Sleep 10; exit 1 }

# Injecteren in offline image (WinPE: target = C:)
if (-not (Test-Path 'C:\Windows')) { Write-DarkGrayHost "Waarschuwing: C:\Windows niet gevonden; controleer of C: het offline image is." }
& dism.exe /Image:C: /Add-Driver /Driver:C:\Drivers /Recurse /LogPath:C:\Windows\Temp\Dism-AddDriver.log

# Opruimen
Remove-Item $ToolPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path C:\Drivers\ -Recurse -Force -ErrorAction SilentlyContinue


# --- Klaar → Reboot
Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
Start-Sleep -Seconds 20
try { Stop-Transcript | Out-Null } catch {}
wpeutil reboot
