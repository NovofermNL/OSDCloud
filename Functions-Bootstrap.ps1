# --- Novoferm Functions Bootstrap (RAW + Normalizer + Logging) ---
# Leest Functions/FunctionsIndex.txt uit de repo en laadt alle .ps1 functies
# Logging: C:\Windows\Temp\OSDCloud-Functions.log

[CmdletBinding()]
param(
    [string]$Owner  = 'NovofermNL',
    [string]$Repo   = 'OSDCloud',
    [string]$Branch = 'main'
)

# TLS 1.2 afdwingen
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Instellingen =====
$BaseRaw       = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/Functions"
$IndexFileUrl  = "$BaseRaw/FunctionsIndex.txt"

$LocalRoot     = Join-Path $env:TEMP 'Novoferm-Functions'
$LocalIndex    = Join-Path $LocalRoot 'FunctionsIndex.txt'

# Log in C:\Windows\Temp conform voorkeur
$LogFile       = Join-Path $env:SystemRoot 'Temp\OSDCloud-Functions.log'

# Headers voor GitHub
$Headers       = @{ 'User-Agent' = 'PowerShell' }

# ===== Logging helper =====
function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    "{0}  {1}" -f $stamp, $Message | Add-Content -Path $LogFile -Encoding UTF8
}

# ===== URL normalizer =====
function Convert-ToRawUrl {
    param([Parameter(Mandatory)][string]$Input)
    $line = $Input.Trim()
    if (-not $line) { return $null }                # leeg
    if ($line -match '^\s*#') { return $null }      # comment

    if ($line -match '^https?://') {
        $url = $line
        # GitHub UI -> RAW
        if ($url -match '^https?://github\.com/.*/blob/') {
            $url = $url -replace '^https?://github\.com/', 'https://raw.githubusercontent.com/'
            $url = $url -replace '/blob/', '/'
        }
        # directory-URL's overslaan
        if ($url -match '/tree/') { return $null }
        return $url
    }

    # relative pad (bv. Sub\Naam.ps1)
    $line = $line -replace '^[./\\]+',''
    return "$BaseRaw/$line"
}

# ===== Start =====
Write-Log ("Start bootstrap. Index: {0}" -f $IndexFileUrl)

# Lokale root maken
try {
    Write-Log ("Maken lokale map: {0}" -f $LocalRoot)
    $null = New-Item -Path $LocalRoot -ItemType Directory -Force
}
catch {
    Write-Log ("FATALE FOUT: Kan lokale map niet maken. {0}" -f $_.Exception.Message)
    throw "Kan lokale map niet maken."
}

# Index downloaden
try {
    Write-Log ("Downloaden Index: {0}" -f $IndexFileUrl)
    Invoke-WebRequest -Uri $IndexFileUrl -UseBasicParsing -OutFile $LocalIndex -Headers $Headers -ErrorAction Stop

    # Sanity check op HTML
    $idxHead = Get-Content -Path $LocalIndex -TotalCount 5 -Raw
    if ($idxHead -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
        Write-Log "FATALE FOUT: Index lijkt HTML (verkeerde URL of rate-limit)."
        throw "Kon FunctionsIndex.txt niet als raw downloaden (HTML ontvangen)."
    }
    Write-Log ("Index succesvol gedownload naar {0}" -f $LocalIndex)
}
catch {
    Write-Log ("FATALE FOUT: kon index niet downloaden. {0}" -f $_.Exception.Message)
    throw "Kon FunctionsIndex.txt niet downloaden."
}

# Lijst parsen & normaliseren
$RawUrls = @()
try {
    $lines = (Get-Content $LocalIndex -Raw -Encoding UTF8) -split "\r?\n"
    foreach ($l in $lines) {
        $u = Convert-ToRawUrl -Input $l
        if ($u) { $RawUrls += $u }
    }
}
catch {
    Write-Log ("FATALE FOUT: Indexbestand kon niet worden gelezen. {0}" -f $_.Exception.Message)
    throw "Kon FunctionsIndex.txt niet lezen."
}

if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log "FATALE FOUT: index bevat geen valide file-urls."
    throw "FunctionsIndex.txt bevat geen geldige items."
}

Write-Log ("Genormaliseerde items:`n{0}" -f ($RawUrls -join "`n"))

# Functions downloaden + laden
$Loaded = @()
foreach ($src in $RawUrls) {
    try {
        $uri  = [uri]$src
        $name = Split-Path $uri.AbsolutePath -Leaf
        if (-not $name -or ($name -notlike '*.ps1')) {
            Write-Log ("Sla over (geen .ps1): {0}" -f $src)
            continue
        }

        # relative pad reconstrueren na '/Functions/'
        $rel = $name
        if ($uri.AbsolutePath -match '/Functions/(.+)$') { $rel = $Matches[1] }

        $dst    = Join-Path $LocalRoot $rel
        $dstDir = Split-Path -Path $dst -Parent
        if ($dstDir -and -not (Test-Path $dstDir)) {
            $null = New-Item -Path $dstDir -ItemType Directory -Force
        }

        Write-Log ("Downloaden: {0} -> {1}" -f $src, $dst)
        Invoke-WebRequest -Uri $src -UseBasicParsing -OutFile $dst -Headers $Headers -ErrorAction Stop

        # HTML-detectie
        $head = Get-Content -Path $dst -TotalCount 8 -Raw
        if ($head -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
            Write-Log ("FOUT: HTML gedownload i.p.v. .ps1 voor {0}" -f $src)
            Write-Log ("HEAD(voor debug): `n{0}" -f $head.Substring(0, [Math]::Min(250, $head.Length)))
            throw "Download gaf HTML terug voor $src"
        }

        # Dot-source
        . $dst
        $Loaded += $rel
        Write-Log ("Loaded: {0}" -f $rel)
    }
    catch {
        Write-Log ("FOUT bij {0}: {1}" -f $src, $_.Exception.Message)
        throw "Kon functie van '$src' niet downloaden of laden."
    }
}

Write-Log ("Bootstrap voltooid. Functions geladen: {0}" -f ($Loaded -join ', '))
