# --- Novoferm Functions Bootstrap (RAW + Robust) ---
# Downloadt en laadt functies uit de GitHub-repo via raw.githubusercontent.com
# Vereist: Functions/FunctionsIndex.txt in de repo met relative paden naar .ps1-bestanden

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

$WebHeaders = @{ 'User-Agent' = 'PowerShell' }  # voorkomt GitHub HTML/redirect issues

# ===== Logging helper =====
function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    "$stamp  $Message" | Add-Content -Path $LogFile -Encoding UTF8
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
    Invoke-WebRequest -Uri $IndexFileUrl -UseBasicParsing -OutFile $LocalIndex -Headers $WebHeaders -ErrorAction Stop
    # Basic sanity check tegen HTML
    $idxHead = Get-Content -Path $LocalIndex -TotalCount 5 -Raw
    if ($idxHead -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
        Write-Log "FATALE FOUT: Index lijkt HTML te zijn (verkeerde URL of rate-limit)."
        throw "Kon FunctionsIndex.txt niet als raw downloaden (HTML ontvangen)."
    }
    Write-Log "Index succesvol gedownload naar $LocalIndex"
}
catch {
    Write-Log "FATALE FOUT: kon index niet downloaden. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet downloaden."
}

# ===== Lijst parsen =====
try {
    $FunctionFiles = Get-Content $LocalIndex | Where-Object {
        $_.Trim() -and ($_.Trim() -notmatch '^\s*#')
    } | ForEach-Object { $_.Trim() }
}
catch {
    Write-Log "FATALE FOUT: Indexbestand kon niet worden gelezen. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet lezen."
}

if (-not $FunctionFiles -or $FunctionFiles.Count -eq 0) {
    Write-Log "FATALE FOUT: index bevat geen function-bestanden."
    throw "FunctionsIndex.txt bevat geen items."
}

# ===== Functions downloaden + laden =====
$Loaded = @()
foreach ($f in $FunctionFiles) {
    # Ondersteun submappen in de index (bijv. Sub\Naam.ps1)
    $src = "$BaseRaw/$f"
    $dst = Join-Path $LocalRoot $f

    try {
        $dstDir = Split-Path -Path $dst -Parent
        if ($dstDir -and -not (Test-Path $dstDir)) {
            $null = New-Item -Path $dstDir -ItemType Directory -Force
        }

        Write-Log "Downloaden: $src -> $dst"
        Invoke-WebRequest -Uri $src -UseBasicParsing -OutFile $dst -Headers $WebHeaders -ErrorAction Stop

        # Sanity check: geen HTML/redirectpagina
        $head = Get-Content -Path $dst -TotalCount 5 -Raw
        if ($head -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
            Write-Log "FOUT: $f lijkt HTML te zijn (verkeerde raw-URL of rate-limit)."
            throw "Download gaf HTML terug voor $f."
        }

        # Dot-source in huidige sessie
        . $dst
        $Loaded += $f
        Write-Log "Loaded: $f"
    }
    catch {
        Write-Log "FOUT bij $f: $($_.Exception.Message)"
        throw "Kon functie '$f' niet downloaden of laden."
    }
}

Write-Log "Bootstrap voltooid. Functions geladen: $($Loaded -join ', ')"
