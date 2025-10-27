# TLS 1.2 afdwingen
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host -ForegroundColor Yellow "Starten van installatie Windows 11 24H2 NL"

#################################################################
#   [PreOS] Update Module
#################################################################
Write-Host -ForegroundColor Green "Updaten OSD PowerShell Module"

# NuGet-provider en PSGallery vertrouwen
try { Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null }
catch { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }

try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch {}

Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importeren OSD PowerShell Module"
Import-Module OSD -Force

#################################################################
#   [PreOS] OSDCloud functies + internet
#################################################################
try {
    Invoke-Expression -Command (Invoke-RestMethod -Uri functions.osdcloud.com)
} catch {
    Write-Host "Kon functions.osdcloud.com niet laden" -ForegroundColor Red
}

$InternetConnection = $false
if (Get-Command -Name Test-OSDCloudNetwork -ErrorAction SilentlyContinue) {
    $InternetConnection = [bool](Test-OSDCloudNetwork)
} else {
    try {
        $null = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/" -Method Head -TimeoutSec 10
        $InternetConnection = $true
    } catch { $InternetConnection = $false }
}

#################################################################
#   [PreOS] HP detectie (TPM/BIOS/HPIA)
#################################################################
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
$Model        = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$HPTPM        = $false
$HPBIOS       = $false
$HPIADrivers  = $false
$HPEnterprise = $false

if ($Manufacturer -match 'HP' -or $Manufacturer -match 'Hewlett-Packard') {
    $Manufacturer = 'HP'
    if ($InternetConnection -and (Get-Command -Name Test-HPIASupport -ErrorAction SilentlyContinue)) {
        $HPEnterprise = [bool](Test-HPIASupport)
    }
}

if ($HPEnterprise) {
    try {
        Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1')

        if (Get-Command -Name osdcloud-InstallModuleHPCMSL -ErrorAction SilentlyContinue) {
            osdcloud-InstallModuleHPCMSL
        }

        $TPM   = $null
        $BIOS  = $null
        if (Get-Command osdcloud-HPTPMDetermine -ErrorAction SilentlyContinue) { $TPM  = osdcloud-HPTPMDetermine }
        if (Get-Command osdcloud-HPBIOSDetermine -ErrorAction SilentlyContinue){ $BIOS = osdcloud-HPBIOSDetermine }

        $HPIADrivers = $true

        if ($TPM) {
            Write-Host "HP Update TPM Firmware: $TPM - Requires Interaction" -ForegroundColor Yellow
            $HPTPM = $true
        } else {
            $HPTPM = $false
        }

        if ($BIOS -eq $false) {
            if (Get-Command Get-HPBIOSVersion -ErrorAction SilentlyContinue) {
                $CurrentVer = Get-HPBIOSVersion
                Write-Host "HP System Firmware already Current: $CurrentVer" -ForegroundColor Green
            }
            $HPBIOS = $false
        } else {
            if ((Get-Command Get-HPBIOSUpdates -ErrorAction SilentlyContinue) -and (Get-Command Get-HPBIOSVersion -ErrorAction SilentlyContinue)) {
                $LatestVer  = (Get-HPBIOSUpdates -Latest).ver
                $CurrentVer = Get-HPBIOSVersion
                Write-Host "HP Update System Firmware from $CurrentVer to $LatestVer" -ForegroundColor Yellow
            } else {
                Write-Host "HP BIOS update geadviseerd (versie-info niet beschikbaar)" -ForegroundColor Yellow
            }
            $HPBIOS = $true
        }
    } catch {
        Write-Host "HP Enterprise detectie of modules laden is mislukt: $($_.Exception.Message)" -ForegroundColor Red
        $HPTPM = $false
        $HPBIOS = $false
        $HPIADrivers = $false
    }
}

#################################################################
#   Global.MyOSDCloud (één definitie, samengevoegd)
#################################################################
$Global:MyOSDCloud = [ordered]@{
    Restart               = [bool]$False
    RecoveryPartition     = [bool]$true
    OEMActivation         = [bool]$false
    WindowsUpdate         = [bool]$false
    WindowsUpdateDrivers  = [bool]$false
    WindowsDefenderUpdate = [bool]$false
    SetTimeZone           = [bool]$true
    ClearDiskConfirm      = [bool]$False
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$true

    DevMode               = [bool]$true
    NetFx3                = [bool]$true
    Bitlocker             = [bool]$true
    OSDCloudUnattend      = [bool]$true

    HPIADrivers           = [bool]$HPIADrivers
    HPTPMUpdate           = [bool]$HPTPM
    HPBIOSUpdate          = [bool]$HPBIOS
}

#################################################################
#   [PreOS] Zorg dat doelmappen bestaan
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
#   [OS] Params and Start-OSDCloud
#################################################################
$Params = @{
    OSVersion     = "Windows 11"
    OSBuild       = "24H2"
    OSEdition     = "Pro"
    OSLanguage    = "nl-nl"
    OSLicense     = "Retail"
    ZTI           = $true
    Firmware      = $false
    SkipAutopilot = $false
}
Start-OSDCloud @Params
