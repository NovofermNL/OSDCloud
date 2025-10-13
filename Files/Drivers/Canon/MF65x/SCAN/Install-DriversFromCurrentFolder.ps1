<# 
.SYNOPSIS
    Installeert scan-gerelateerde drivers uit een map (INF/MSI/EXE).

.DESCRIPTION
    - INF: via pnputil, gefilterd op Class: Image/WIA/Scanner/StillImage
    - MSI: stil via msiexec /qn, met per-package log
    - EXE: best-effort stille switches (kan worden uitgezet)

.PARAMETER DriverRoot
    Rootmap met driverbestanden. Standaard: map van het script.

.PARAMETER AttemptExeSilent
    Probeer EXE-installers stil te installeren met bekende switches. Standaard: $true.

.PARAMETER InfClassFilter
    Welke INF Class-waarden als 'scan' tellen. Standaard: Image,WIA,Scanner,StillImage.

.NOTES
    Logt naar: C:\Windows\Temp\ScanDriverInstall\
    Datumformaat: DD-MM-YYYY
#>

param(
    [string]$DriverRoot = $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }),
    [switch]$AttemptExeSilent = $true,
    [string[]]$InfClassFilter = @('Image','WIA','Scanner','StillImage')
)

# Vereisten & omgeving
try {
    # TLS12 voorkeur (conform jouw standaard)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

# Culture naar NL voor datum/tijd output
try {
    $nl = New-Object System.Globalization.CultureInfo('nl-NL')
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $nl
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $nl
} catch {}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "Dit script moet als Administrator worden uitgevoerd."
    exit 1
}

# Log-setup
$scriptName   = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logRoot      = "C:\Windows\Temp\ScanDriverInstall\$scriptName"
$timestamp    = (Get-Date).ToString('dd-MM-yyyy_HHmmss')
$null = New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction SilentlyContinue
$transcript   = Join-Path $logRoot "$scriptName`_$timestamp.log"
Start-Transcript -Path $transcript -Append | Out-Null

Write-Host "=== $scriptName gestart op $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss') ==="
Write-Host "DriverRoot: $DriverRoot"
Write-Host ""

# Resultaatverzameling
$InfSuccess   = New-Object System.Collections.Generic.List[string]
$InfFailed    = New-Object System.Collections.Generic.List[string]
$MsiSuccess   = New-Object System.Collections.Generic.List[string]
$MsiFailed    = New-Object System.Collections.Generic.List[string]
$ExeSuccess   = New-Object System.Collections.Generic.List[string]
$ExeFailed    = New-Object System.Collections.Generic.List[string]

function Test-InfIsScannerClass {
    param(
        [Parameter(Mandatory=$true)][string]$InfPath,
        [string[]]$AllowedClasses = $InfClassFilter
    )
    try {
        # Lees alleen de eerste ~200 regels om snel Class te vinden
        $lines = Get-Content -Path $InfPath -TotalCount 200 -ErrorAction Stop
        foreach ($line in $lines) {
            if ($line -match '^\s*Class\s*=\s*(.+?)\s*$') {
                $cls = $Matches[1].Trim()
                if ($AllowedClasses -contains $cls) { return $true }
                # Sommige vendors gebruiken StillImage/Scanner varianten
                if ($AllowedClasses | ForEach-Object { $cls -like $_ }) { return $true }
                return $false
            }
        }
        # Geen Class gevonden -> conservatief: niet installeren
        return $false
    } catch {
        Write-Warning "Kan INF niet lezen: $InfPath. $_"
        return $false
    }
}

function Invoke-PnPUtilAddDriver {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Gebruik Start-Process voor exitcode
    $args = "/add-driver `"$Path`" /install"
    $p = Start-Process -FilePath pnputil.exe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
    return $p.ExitCode
}

function Install-InfDrivers {
    param([string]$Root)
    $infFiles = Get-ChildItem -Path $Root -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue
    if (-not $infFiles) {
        Write-Host "Geen INF-bestanden gevonden."
        return
    }
    Write-Host "Gevonden INF-bestanden: $($infFiles.Count). Filter op scanner/WIA classes: $($InfClassFilter -join ', ')"
    foreach ($inf in $infFiles) {
        $isScan = Test-InfIsScannerClass -InfPath $inf.FullName
        if (-not $isScan) {
            Write-Host "Overslaan (geen scanner/WIA class): $($inf.FullName)"
            continue
        }
        Write-Host "Installeren INF: $($inf.FullName)"
        try {
            $code = Invoke-PnPUtilAddDriver -Path $inf.FullName
            if ($code -eq 0) {
                $InfSuccess.Add($inf.FullName) | Out-Null
                Write-Host "OK: $($inf.Name)"
            } else {
                $InfFailed.Add($inf.FullName) | Out-Null
                Write-Warning "Mislukt (exitcode $code): $($inf.Name)"
            }
        } catch {
            $InfFailed.Add($inf.FullName) | Out-Null
            Write-Warning "Fout bij installeren INF $($inf.FullName): $_"
        }
    }
}

function Install-MsiPackages {
    param([string]$Root)
    $msis = Get-ChildItem -Path $Root -Recurse -Filter *.msi -File -ErrorAction SilentlyContinue
    if (-not $msis) {
        Write-Host "Geen MSI-bestanden gevonden."
        return
    }
    Write-Host "Gevonden MSI-bestanden: $($msis.Count)"
    foreach ($msi in $msis) {
        try {
            $msilog = Join-Path $logRoot ("{0}_{1}.msi.log" -f ($msi.BaseName), (Get-Date -Format 'dd-MM-yyyy_HHmmss'))
            $args = "/i `"$($msi.FullName)`" /qn /norestart /L*v `"$msilog`""
            Write-Host "Installeren MSI: $($msi.FullName)"
            $p = Start-Process -FilePath msiexec.exe -ArgumentList $args -PassThru -Wait
            # msiexec: 0=OK, 3010=succes met reboot nodig
            if ($p.ExitCode -in 0,3010) {
                $MsiSuccess.Add($msi.FullName) | Out-Null
                Write-Host "OK (code $($p.ExitCode)): $($msi.Name)"
            } else {
                $MsiFailed.Add($msi.FullName) | Out-Null
                Write-Warning "Mislukt (exitcode $($p.ExitCode)): $($msi.Name). Zie log: $msilog"
            }
        } catch {
            $MsiFailed.Add($msi.FullName) | Out-Null
            Write-Warning "Fout bij installeren MSI $($msi.FullName): $_"
        }
    }
}

function Install-ExePackages {
    param(
        [string]$Root,
        [switch]$TrySilent
    )
    if (-not $TrySilent) {
        Write-Host "EXE-installaties overslaan (AttemptExeSilent = $TrySilent)."
        return
    }

    # Neem alleen 'installer-achtige' EXE's: skip drivers die hulpprogramma's zijn zonder installatie
    $exes = Get-ChildItem -Path $Root -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'pnputil|dpinst|vcredist|dotnet|setupdiag|uninstall' }

    if (-not $exes) {
        Write-Host "Geen EXE-installers gevonden."
        return
    }

    Write-Host "Gevonden EXE-bestanden: $($exes.Count) — probeer stille installatie met bekende switches."

    # Veelvoorkomende stille switches (volgorde: meest voorkomend eerst)
    $switchSets = @(
        '/S', '/silent', '/s', '/verysilent /suppressmsgboxes /norestart',
        '/qn', '/quiet', '/passive /norestart'
    )

    foreach ($exe in $exes) {
        $installed = $false
        foreach ($sw in $switchSets) {
            try {
                Write-Host "Installeren EXE: $($exe.FullName) met switches: $sw"
                $p = Start-Process -FilePath $exe.FullName -ArgumentList $sw -PassThru -Wait -WindowStyle Hidden
                # Succescriteria: 0 of 3010 (reboot) zijn gangbaar
                if ($p.ExitCode -in 0,3010) {
                    $ExeSuccess.Add("$($exe.FullName) [$sw]") | Out-Null
                    Write-Host "OK (code $($p.ExitCode)): $($exe.Name)"
                    $installed = $true
                    break
                } else {
                    Write-Warning "Switch '$sw' werkt niet (exitcode $($p.ExitCode))."
                }
            } catch {
                Write-Warning "Fout met switch '$sw' voor $($exe.FullName): $_"
            }
        }
        if (-not $installed) {
            $ExeFailed.Add($exe.FullName) | Out-Null
            Write-Warning "Geen bekende stille switch werkte voor: $($exe.FullName). Voeg vendor-specifieke switch toe."
        }
    }
}

# Uitvoering
Write-Host "Stap 1/3: INF-drivers (scanner/WIA)"
Install-InfDrivers -Root $DriverRoot
Write-Host ""

Write-Host "Stap 2/3: MSI-packages"
Install-MsiPackages -Root $DriverRoot
Write-Host ""

Write-Host "Stap 3/3: EXE-installers (best-effort)"
Install-ExePackages -Root $DriverRoot -TrySilent:$AttemptExeSilent
Write-Host ""

# Samenvatting
Write-Host "=== Samenvatting ==="
Write-Host ("INF   OK : {0}" -f $InfSuccess.Count)
Write-Host ("INF   Mislukt: {0}" -f $InfFailed.Count)
Write-Host ("MSI   OK : {0}" -f $MsiSuccess.Count)
Write-Host ("MSI   Mislukt: {0}" -f $MsiFailed.Count)
Write-Host ("EXE   OK : {0}" -f $ExeSuccess.Count)
Write-Host ("EXE   Mislukt: {0}" -f $ExeFailed.Count)
Write-Host ""

if ($InfFailed.Count -or $MsiFailed.Count -or $ExeFailed.Count) {
    Write-Host "Mislukte items:"
    $InfFailed + $MsiFailed + $ExeFailed | ForEach-Object { Write-Host " - $_" }
}

Write-Host ""
Write-Host "Logbestand: $transcript"
Stop-Transcript | Out-Null
