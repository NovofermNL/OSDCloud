# --- Novoferm Functions Bootstrap (RAW + URL Normalizer + Verbose) ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Instellingen =====
$Owner   = 'NovofermNL'
$Repo    = 'OSDCloud'
$Branch  = 'main'
$BaseRaw = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/Functions"

$IndexFileUrl = "$BaseRaw/FunctionsIndex.txt"
$LocalRoot    = Join-Path $env:TEMP 'Novoferm-Functions'
$LocalIndex   = Join-Path $LocalRoot 'FunctionsIndex.txt'
$LogFile      = Join-Path $env:TEMP 'OSDCloud-Functions.log'
$Headers      = @{ 'User-Agent' = 'PowerShell' }

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    "$stamp  $Message" | Add-Content -Path $LogFile -Encoding UTF8
}

function Convert-ToRawUrl {
    param([string]$Input)
    $line = $Input.Trim()

    if (-not $line) { return $null }

    # Comment of lege regel?
    if ($line -match '^\s*#') { return $null }

    # Als het al een URL is:
    if ($line -match '^https?://') {
        $url = $line

        # GitHub UI -> RAW
        if ($url -match '^https?://github\.com/.*/blob/') {
            $url = $url -replace '^https?://github\.com/', 'https://raw.githubusercontent.com/'
            $url = $url -replace '/blob/', '/'
        }

        # Los 'tree' directory-URL's op (niet geldig voor file download) -> laat ze vallen
        if ($url -match '/tree/') { return $null }

        return $url
    }

    # Relative pad (bv. Set-TrustedPSGallery.ps1 of Sub\X.ps1)
    # Strip eventueel leidende ./ of / 
    $line = $line -replace '^[./\\]+',''
    return "$BaseRaw/$line"
}

Write-Log "Start bootstrap. Index: $IndexFileUrl"

# ===== Voorbereiden =====
try {
    Write-Log "Maken lokale map: $LocalRoot"
    $null = New-Item -Path $LocalRoot -ItemType Directory -Force
}
catch {
    Write-Log "FATALE FOUT: Kan lokale map niet maken. $($_.Exception.Message)"
    throw "Kan lokale map niet maken."
}

# ===== Index downloaden =====
try {
    Write-Log "Downloaden Index: $IndexFileUrl"
    Invoke-WebRequest -Uri $IndexFileUrl -UseBasicParsing -OutFile $LocalIndex -Headers $Headers -ErrorAction Stop
    $idxHead = Get-Content -Path $LocalIndex -TotalCount 5 -Raw
    if ($idxHead -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
        Write-Log "FATALE FOUT: Index lijkt HTML (verkeerde URL of rate-limit)."
        throw "Kon FunctionsIndex.txt niet als raw downloaden (HTML ontvangen)."
    }
    Write-Log "Index succesvol gedownload naar $LocalIndex"
}
catch {
    Write-Log "FATALE FOUT: kon index niet downloaden. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet downloaden."
}

# ===== Lijst parsen & normaliseren =====
$RawUrls = @()
try {
    $lines = Get-Content $LocalIndex -Raw -Encoding UTF8 -ErrorAction Stop -Force -EA Stop -ReadCount 0
    # Split robuust op CRLF/LF
    $lines = $lines -split "\r?\n"

    foreach ($l in $lines) {
        $u = Convert-ToRawUrl -Input $l
        if ($u) { $RawUrls += $u }
    }
}
catch {
    Write-Log "FATALE FOUT: Indexbestand kon niet worden gelezen. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet lezen."
}

if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log "FATALE FOUT: index bevat geen valide file-urls."
    throw "FunctionsIndex.txt bevat geen geldige items."
}

Write-Log ("Genormaliseerde items:`n" + ($RawUrls -join "`n"))

# ===== Functions downloaden + laden =====
$Loaded = @()
foreach ($src in $RawUrls) {
    # Bestandsnaam voor local pad bepalen
    try {
        $uri = [uri]$src
        $name = Split-Path $uri.AbsolutePath -Leaf
        if (-not $name -or ($name -notlike '*.ps1')) {
            Write-Log "Sla over (geen .ps1): $src"
            continue
        }

        # Rekonstrueer relative pad na '/Functions/' als dat in het pad zit, anders alleen bestandsnaam
        $rel = $name
        if ($uri.AbsolutePath -match '/Functions/(.+)$') { $rel = $Matches[1] }

        $dst = Join-Path $LocalRoot $rel
        $dstDir = Split-Path -Path $dst -Parent
        if ($dstDir -and -not (Test-Path $dstDir)) {
            $null = New-Item -Path $dstDir -ItemType Directory -Force
        }

        Write-Log "Downloaden: $src -> $dst"
        Invoke-WebRequest -Uri $src -UseBasicParsing -OutFile $dst -Headers $Headers -ErrorAction Stop

        # HTML-detectie
        $head = Get-Content -Path $dst -TotalCount 8 -Raw
        if ($head -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
            Write-Log "FOUT: HTML gedownload i.p.v. .ps1 voor $src"
            Write-Log "HEAD(voor debug): `n$($head.Substring(0, [Math]::Min(250, $head.Length)))"
            throw "Download gaf HTML terug voor $src"
        }

        # Dot-source
        . $dst
        $Loaded += $rel
        Write-Log "Loaded: $rel"
    }
    catch {
        Write-Log "FOUT bij $src: $($_.Exception.Message)"
        throw "Kon functie van '$src' niet downloaden of laden."
    }
}

Write-Log "Bootstrap voltooid. Functions geladen: $($Loaded -join ', ')"
