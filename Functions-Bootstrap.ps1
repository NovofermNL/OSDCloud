# --- Novoferm Functions Bootstrap ---
# Dit script downloadt en laadt functies van de GitHub-repository.

# Instellingen
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaseUrl = 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Functions'
$IndexFileUrl = "$BaseUrl/FunctionsIndex.txt"
$LocalRoot = Join-Path $env:TEMP 'Novoferm-Functions'
$LocalIndex = Join-Path $LocalRoot 'FunctionsIndex.txt'
# Pas de log-locatie aan naar een veilige map om rechtenproblemen te voorkomen.
$LogFile = Join-Path $env:TEMP 'OSDCloud-Functions.log' 

# -----------------------------------------------------------------------------
# Logging helper
# -----------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    # Gebruik Add-Content voor betere prestaties dan Out-File -Append
    "$stamp  $Message" | Add-Content -Path $LogFile -Encoding UTF8
}

# -----------------------------------------------------------------------------
# Voorbereiden en Index downloaden
# -----------------------------------------------------------------------------
Write-Log "Start bootstrap. Index: $IndexFileUrl"

# Maak lokale root-map
try {
    Write-Log "Maken lokale map: $LocalRoot"
    $null = New-Item -Path $LocalRoot -ItemType Directory -Force
}
catch {
    Write-Log "FATALE FOUT: Kan lokale map niet maken. $($_.Exception.Message)"
    throw "Kan lokale map niet maken."
}

# Index downloaden
try {
    Write-Log "Downloaden Index: $IndexFileUrl"
    Invoke-WebRequest -Uri $IndexFileUrl -UseBasicParsing -OutFile $LocalIndex -ErrorAction Stop
    Write-Log "Index succesvol gedownload naar $LocalIndex"
}
catch {
    # Fix voor de fout uit de screenshot: gebruik $($_.Exception.Message)
    Write-Log "FATALE FOUT: kon index niet downloaden. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet downloaden."
}

# -----------------------------------------------------------------------------
# Lijst parsen
# -----------------------------------------------------------------------------
try {
    $FunctionFiles = Get-Content $LocalIndex | Where-Object {
        # Negeer lege regels en regels die met '#' beginnen (comments)
        $_.Trim() -and ($_.Trim() -notmatch '^\s*#')
    }
}
catch {
    Write-Log "FATALE FOUT: Indexbestand kon niet worden gelezen. $($_.Exception.Message)"
    throw "Kon FunctionsIndex.txt niet lezen."
}


if (-not $FunctionFiles -or $FunctionFiles.Count -eq 0) {
    Write-Log "FATALE FOUT: index bevat geen function-bestanden."
    throw "FunctionsIndex.txt bevat geen items."
}

# -----------------------------------------------------------------------------
# Functions binnenhalen en laden
# -----------------------------------------------------------------------------
foreach ($f in $FunctionFiles) {
    $src = "$BaseUrl/$f"
    $dst = Join-Path $LocalRoot $f
    try {
        Write-Log "Downloaden: $src naar $dst"
        Invoke-WebRequest -Uri $src -UseBasicParsing -OutFile $dst -ErrorAction Stop

        # Dot-source in huidige sessie
        . $dst
        Write-Log "Loaded: $f"
    }
    catch {
        Write-Log "Bootstrap voltooid. Functions geladen: $($FunctionFiles -join ', ')"
        throw "Kon functie '$f' niet downloaden of laden."
    }
}

Write-Log "Bootstrap voltooid. Functions geladen: $($FunctionFiles -join ', ')"

# Optionele Validatie
# Write-Host "`n--- Geladen Functies ---"
# Get-Command -CommandType Function | Where-Object Name -like 'Novoferm*' | Select-Object Name, ModuleName | Format-Table -AutoSize
