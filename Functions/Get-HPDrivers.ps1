Write-Host "[+] Function Get-HPDrivers"

#requires -Version 5.1
<#
.SYNOPSIS
  Download & extract HP drivers via HPIA cloud endpoints (zelf-contained, non-interactive).

.NOTES
  - Werkt in WinPE; gebruikt BITS als beschikbaar, anders Invoke-WebRequest.
  - Geen externe helperfunction afhankelijkheden.
  - Logging naar host (timestamp dd-MM-yyyy HH:mm:ss).
#>

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $ts = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    Write-Host "[$ts] $Message"
}

function Invoke-Proc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ArgumentList = ''
    )
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden
    return $p
}

function Test-UrlSimple {
    param([Parameter(Mandatory)][string]$Url,[int]$TimeoutSec=15)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
    } catch { return $false }
}

function Start-Download {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [int]$Retries = 3,
        [int]$TimeoutSec = 600
    )
    $attempt = 0
    $useBITS = $false
    try {
        $svc = Get-Service -Name BITS -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') { $useBITS = $true }
    } catch {}

    while ($attempt -lt $Retries) {
        $attempt++
        try {
            if ($useBITS) {
                Write-Log "BITS download (attempt $attempt): $Source -> $Destination"
                Start-BitsTransfer -Source $Source -Destination $Destination -DisplayName "Get-HPDrivers" -ErrorAction Stop
            } else {
                Write-Log "IWR download (attempt $attempt): $Source -> $Destination"
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $Source -OutFile $Destination -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            }
            if (Test-Path $Destination -PathType Leaf) { return $true }
        } catch {
            Write-Log "Download mislukt: $($_.Exception.Message)"
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 15))
        }
    }
    return $false
}

function Get-HPDrivers {
    [CmdletBinding()]
    param (
        [Parameter()][string]$Make,
        [Parameter()][string]$Model,
        [Parameter()][ValidateSet("x64", "x86", "ARM64")][string]$WindowsArch,
        [Parameter()][ValidateSet(10, 11)][int]$WindowsRelease,
        [Parameter()][string]$WindowsVersion,
        [Parameter()][string]$DriversFolder
    )

    # --- Defaults (detectie waar mogelijk)
    if (-not $Make -or -not $Model) {
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            if (-not $Make)  { $Make  = $cs.Manufacturer }
            if (-not $Model) { $Model = $cs.Model }
        } catch {}
    }
    if (-not $WindowsArch)   { $WindowsArch   = if ([Environment]::Is64BitOperatingSystem) {'x64'} else {'x86'} }
    if (-not $WindowsRelease){ $WindowsRelease = 11 } # Default: 11 (pas aan indien gewenst)
    if (-not $WindowsVersion){ $WindowsVersion = '24H2' } # Verwacht door HPIA: bijv. 23H2 / 24H2
    if (-not $DriversFolder) { $DriversFolder = Join-Path $env:ProgramData 'Drivers' }

    Write-Log "Parameters: Make='$Make' Model='$Model' Arch='$WindowsArch' Release='$WindowsRelease' Version='$WindowsVersion'"
    Write-Log "DriversFolder: $DriversFolder"

    # --- Padopbouw & basisbestanden ---
    $DriversPath      = Join-Path $DriversFolder ($Make -replace '[\\\/\:\*\?\"<>\|]', '_')
    $PlatformListUrl  = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
    $PlatformListCab  = Join-Path $DriversPath 'platformList.cab'
    $PlatformListXml  = Join-Path $DriversPath 'PlatformList.xml'

    if (-not (Test-Path -Path $DriversPath)) {
        Write-Log "Aanmaken downloadmap: $DriversPath"
        New-Item -Path $DriversPath -ItemType Directory -Force | Out-Null
    }

    # --- Download & uitpakken PlatformList ---
    Write-Log "Downloaden: $PlatformListUrl"
    if (-not (Start-Download -Source $PlatformListUrl -Destination $PlatformListCab)) {
        Write-Log "Kon platformList.cab niet downloaden. Stop."
        return
    }

    Write-Log "Uitpakken: $PlatformListCab -> $PlatformListXml"
    $proc = Invoke-Proc -FilePath "$env:SystemRoot\System32\expand.exe" -ArgumentList "`"$PlatformListCab`" `"$PlatformListXml`""
    if ($proc.ExitCode -ne 0 -or -not (Test-Path $PlatformListXml)) {
        Write-Log "Uitpakken van platformList.cab mislukt (exitcode $($proc.ExitCode)). Stop."
        return
    }

    # --- Parse PlatformList om SystemID e.d. te bepalen ---
    [xml]$PlatformListContent = Get-Content -Path $PlatformListXml
    $productNodes = $PlatformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match [regex]::Escape($Model) }

    if (-not $productNodes) {
        Write-Log "Geen modellen gevonden voor '$Model'. Stop."
        return
    }

    # Maak kandidatenlijst (ProductName/SystemID/OSReleaseIDs/IsWindows11)
    $candidates = foreach ($node in $productNodes) {
        foreach ($pn in $node.ProductName) {
            if ($pn.'#text' -match [regex]::Escape($Model)) {
                [PSCustomObject]@{
                    ProductName = $pn.'#text'
                    SystemID    = $node.SystemID
                    OSReleaseID = $node.OS.OSReleaseIdFileName -replace 'H', 'h'
                    IsWindows11 = ($node.OS.IsWindows11 -contains 'true')
                }
            }
        }
    }

    if (-not $candidates) {
        Write-Log "Geen valide kandidaten opgebouwd. Stop."
        return
    }

    # Non-interactive selectie: eerst exacte match op model, anders eerste
    $selected = $candidates | Where-Object { $_.ProductName -eq $Model } | Select-Object -First 1
    if (-not $selected) { $selected = $candidates | Select-Object -First 1 }

    $ProductName       = $selected.ProductName
    $SystemID          = $selected.SystemID
    $ValidOSReleaseIDs = $selected.OSReleaseID
    $IsWindows11       = $selected.IsWindows11

    Write-Log "Geselecteerd model: $ProductName"
    Write-Log "SystemID: $SystemID"
    Write-Log "Geldige OSReleaseIDs: $ValidOSReleaseIDs"
    Write-Log "Ondersteunt Windows 11: $IsWindows11"

    if (-not $SystemID) {
        Write-Log "Geen SystemID gevonden voor '$Model'. Stop."
        return
    }

    # --- Validatie Windows-release ---
    if ($WindowsRelease -eq 11 -and -not $IsWindows11) {
        Write-Log "WindowsRelease=11 maar geen Win11 support. Advies: gebruik WindowsRelease=10 of lever eigen drivers aan."
        return
    }

    # --- Validatie WindowsVersion tegen OSReleaseID ---
    $OSReleaseIDs = ($ValidOSReleaseIDs -split '\s+') | Where-Object { $_ } # lijstje
    $WindowsVersionHP = $WindowsVersion -replace 'H','h'
    if ($OSReleaseIDs -notcontains $WindowsVersionHP) {
        Write-Log "WindowsVersion '$WindowsVersion' niet gevonden in ondersteunde ID's: $($OSReleaseIDs -join ', ')"
        # non-interactive: kies eerste geldige i.p.v. Read-Host
        $WindowsVersionHP = $OSReleaseIDs | Select-Object -First 1
        Write-Log "Automatisch gekozen OSReleaseID: $WindowsVersionHP"
    }

    # --- Opbouw download-URL voor model-driverlijst ---
    $Arch = $WindowsArch -replace '^x',''   # x64 -> 64, x86 -> 86, ARM64 -> ARM64 (HP lijkt 64/86/ARM64 te accepteren)
    $ModelRelease = "${SystemID}_${Arch}_${WindowsRelease}.0.$WindowsVersionHP"

    $DriverCabUrl  = "https://hpia.hpcloud.hp.com/ref/$SystemID/$ModelRelease.cab"
    $DriverCabFile = Join-Path $DriversPath "$ModelRelease.cab"
    $DriverXmlFile = Join-Path $DriversPath "$ModelRelease.xml"

    if (-not (Test-UrlSimple -Url $DriverCabUrl)) {
        Write-Log "HP Driver CAB URL onbereikbaar: $DriverCabUrl. Stop."
        return
    }

    # --- Download & uitpakken model-driverlijst ---
    Write-Log "Downloaden HP Driver CAB: $DriverCabUrl"
    if (-not (Start-Download -Source $DriverCabUrl -Destination $DriverCabFile)) {
        Write-Log "Kon driver CAB niet downloaden. Stop."
        return
    }

    Write-Log "Uitpakken CAB -> $DriverXmlFile"
    $proc = Invoke-Proc -FilePath "$env:SystemRoot\System32\expand.exe" -ArgumentList "`"$DriverCabFile`" `"$DriverXmlFile`""
    if ($proc.ExitCode -ne 0 -or -not (Test-Path $DriverXmlFile)) {
        Write-Log "Uitpakken van driver CAB mislukt (exitcode $($proc.ExitCode)). Stop."
        return
    }

    # --- Parse driver-XML en download/extract per driver ---
    [xml]$DriverXmlContent = Get-Content -Path $DriverXmlFile

    Write-Log "Drivers downloaden voor $ProductName"
    foreach ($update in $DriverXmlContent.ImagePal.Solutions.UpdateInfo) {
        if ($update.Category -notmatch '^Driver') { continue }

        $Name     = ($update.Name     -replace '[\\\/\:\*\?\"<>\|]', '_')
        $Category = ($update.Category -replace '[\\\/\:\*\?\"<>\|]', '_')
        $Version  = ($update.Version  -replace '[\\\/\:\*\?\"<>\|]', '_')

        # Normaliseer URL
        $rawUrl = [string]$update.URL
        if ($rawUrl -match '^(https?|ftp)://') {
            if ($rawUrl -like 'ftp://*') { $DriverUrl = $rawUrl -replace '^ftp://','https://' } else { $DriverUrl = $rawUrl }
        } else {
            $DriverUrl = 'https://' + $rawUrl.TrimStart('/')
        }

        Write-Log "Driver: $Name | Categorie: $Category | Versie: $Version"
        Write-Log "URL: $DriverUrl"

        $DriverFileName = [IO.Path]::GetFileName($DriverUrl)
        $downloadFolder = Join-Path (Join-Path $DriversPath ($ProductName -replace '[\\\/\:\*\?\"<>\|]', '_')) $Category
        $DriverFilePath = Join-Path $downloadFolder $DriverFileName

        if (Test-Path -Path $DriverFilePath) {
            Write-Log "Driver al aanwezig, overslaan: $DriverFilePath"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            Write-Log "Aanmaken downloadmap: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
        }

        Write-Log "Download naar: $DriverFilePath"
        if (-not (Start-Download -Source $DriverUrl -Destination $DriverFilePath)) {
            Write-Log "Download mislukt; volgende driver."
            continue
        }

        # Extract naar nette boom: <DriversPath>\<Product>\<Category>\<Name>\<Version>\<ExeName>\
        $exeBaseName   = [IO.Path]::GetFileNameWithoutExtension($DriverFileName)
        $extractFolder = Join-Path (Join-Path (Join-Path $downloadFolder $Name) $Version) $exeBaseName

        Write-Log "Aanmaken extractiemap: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null

        $arguments = "/s /e /f `"$extractFolder`""
        Write-Log "Uitpakken driver (silent): $DriverFileName"
        try {
            $p2 = Invoke-Proc -FilePath $DriverFilePath -ArgumentList $arguments
            if ($p2.ExitCode -ne 0) {
                Write-Log "Uitpakken meldde exitcode $($p2.ExitCode) (kan soms non-zero zijn bij zelfextractors, controleer map)."
            }
        } catch {
            Write-Log "Uitpakken exception: $($_.Exception.Message)"
        }

        # Opruimen installer
        try { Remove-Item -Path $DriverFilePath -Force -ErrorAction SilentlyContinue } catch {}
        Write-Log "Installer verwijderd: $DriverFilePath"
    }

    # Cleanup tijdelijke CAB/XML
    foreach ($f in @($DriverCabFile,$DriverXmlFile,$PlatformListCab,$PlatformListXml)) {
        try { Remove-Item -Path $f -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log "Tijdelijke CAB/XML bestanden verwijderd"

    Write-Log "Klaar."
}

<# --------------------------------------------
Voorbeeld aanroep:
Get-HPDrivers -Make 'HP' -Model 'HP EliteBook 840 G8' -WindowsArch x64 -WindowsRelease 11 -WindowsVersion 24H2 -DriversFolder 'C:\Drivers'
--------------------------------------------- #>
