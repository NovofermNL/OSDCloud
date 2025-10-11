# --- Novoferm Functions Bootstrap (RAW + API Fallback + Logging) ---
[CmdletBinding()]
param(
    [string]$Owner  = 'NovofermNL',
    [string]$Repo   = 'OSDCloud',
    [string]$Branch = 'main'
)

# TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Instellingen =====
$BaseRaw       = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/Functions"
$IndexFileUrl  = "$BaseRaw/FunctionsIndex.txt"
$ApiUrl        = "https://api.github.com/repos/$Owner/$Repo/contents/Functions?ref=$Branch"

$LocalRoot     = Join-Path $env:TEMP 'Novoferm-Functions'
$LocalIndex    = Join-Path $LocalRoot 'FunctionsIndex.txt'
$LogFile       = Join-Path $env:SystemRoot 'Temp\OSDCloud-Functions.log'

$Headers       = @{ 'User-Agent' = 'PowerShell' ; 'Accept' = 'application/vnd.github+json' }

# ===== Logging helper =====
function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    "{0}  {1}" -f $stamp, $Message | Add-Content -Path $LogFile -Encoding UTF8
}

# ===== URL normalizer (indexregels => raw URL) =====
function Convert-ToRawUrl {
    param([Parameter(Mandatory)][string]$Input)
    $line = $Input.Trim()
    if (-not $line) { return $null }
    if ($line -match '^\s*#') { return $null }

    if ($line -match '^https?://') {
        $url = $line
        if ($url -match '^https?://github\.com/.*/blob/') {
            $url = $url -replace '^https?://github\.com/', 'https://raw.githubusercontent.com/'
            $url = $url -replace '/blob/', '/'
        }
        if ($url -match '/tree/') { return $null }
        return $url
    }

    $line = $line -replace '^[./\\]+',''
    return "$BaseRaw/$line"
}

# ===== Helper: veilige webrequest met betere foutuitleg =====
function Invoke-WebRequestSafe {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$OutFile
    )
    try {
        if ($PSBoundParameters.ContainsKey('OutFile')) {
            Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing -OutFile $OutFile -ErrorAction Stop
            return @{ Ok = $true; Status = 200 }
        } else {
            $r = Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing -ErrorAction Stop
            return @{ Ok = $true; Status = $r.StatusCode; Response = $r }
        }
    } catch {
        $status = $null
        $desc   = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            $desc   = $_.Exception.Response.StatusDescription
        }
        Write-Log ("WEB-ERROR {0} {1}: {2}" -f $status, $desc, $_.Exception.Message)
        return @{ Ok = $false; Status = $status; Error = $_.Exception.Message }
    }
}

# ===== Start =====
Write-Log ("Start bootstrap. Index: {0}" -f $IndexFileUrl)

# Lokale root maken
try {
    Write-Log ("Maken lokale map: {0}" -f $LocalRoot)
    $null = New-Item -Path $LocalRoot -ItemType Directory -Force
} catch {
    Write-Log ("FATALE FOUT: Kan lokale map niet maken. {0}" -f $_.Exception.Message)
    throw "Kan lokale map niet maken."
}

# ===== Index downloaden (met fallback naar GitHub API) =====
$RawUrls = @()

# 1) Probeer indexbestand
Write-Log ("Downloaden Index: {0}" -f $IndexFileUrl)
$idxResult = Invoke-WebRequestSafe -Uri $IndexFileUrl -OutFile $LocalIndex
if ($idxResult.Ok) {
    # check op HTML
    $idxHead = Get-Content -Path $LocalIndex -TotalCount 5 -Raw
    if ($idxHead -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>') {
        Write-Log "Index lijkt HTML (verkeerde URL/redirect/rate-limit). Gebruik API-fallback."
        $idxResult = @{ Ok = $false; Status = 0; Error = 'HTML index' }
    } else {
        try {
            $lines = (Get-Content $LocalIndex -Raw -Encoding UTF8) -split "\r?\n"
            foreach ($l in $lines) {
                $u = Convert-ToRawUrl -Input $l
                if ($u) { $RawUrls += $u }
            }
            Write-Log ("Index parsed. {0} items." -f $RawUrls.Count)
        } catch {
            Write-Log ("FOUT: Indexbestand kon niet worden gelezen. {0}" -f $_.Exception.Message)
            $idxResult = @{ Ok = $false; Status = 0; Error = 'Parse index fail' }
        }
    }
}

# 2) Fallback via GitHub API: lijst Functions/ inhoud en pak .ps1 download_url
if (-not $idxResult.Ok) {
    Write-Log ("API-fallback ophalen: {0}" -f $ApiUrl)
    $apiCall = $null
    try {
        $apiCall = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -ErrorAction Stop
    } catch {
        Write-Log ("FATALE FOUT: GitHub API mislukt: {0}" -f $_.Exception.Message)
        throw "Kon FunctionsIndex niet ophalen via index of API."
    }

    if (-not $apiCall) {
        Write-Log "FATALE FOUT: Lege API-respons."
        throw "Lege API-respons van GitHub."
    }

    # Filter alleen files die op .ps1 eindigen
    $ps1 = $apiCall | Where-Object { $_.type -eq 'file' -and $_.name -like '*.ps1' }
    if (-not $ps1) {
        Write-Log "FATALE FOUT: Geen .ps1 in /Functions via API."
        throw "Geen .ps1 bestanden gevonden via API."
    }

    # Gebruik download_url (raw)
    $RawUrls = $ps1.download_url
    Write-Log ("API-fallback gebruikt. {0} items." -f $RawUrls.Count)
}

if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log "FATALE FOUT: Geen geldige items na index+API."
    throw "Geen functies om te laden."
}

Write-Log ("Genormaliseerde items:`n{0}" -f ($RawUrls -join "`n"))

# ===== Functions downloaden + laden =====
$Loaded = @()
foreach ($src in $RawUrls) {
    try {
        $uri  = [uri]$src
        $name = Split-Path $uri.AbsolutePath -Leaf
        if (-not $name -or ($name -notlike '*.ps1')) {
            Write-Log ("Sla over (geen .ps1): {0}" -f $src)
            continue
        }

        # relative pad reconstrueren na '/Functions/' indien aanwezig
        $rel = $name
        if ($uri.AbsolutePath -match '/Functions/(.+)$') { $rel = $Matches[1] }

        $dst    = Join-Path $LocalRoot $rel
        $dstDir = Split-Path -Path $dst -Parent
        if ($dstDir -and -not (Test-Path $dstDir)) {
            $null = New-Item -Path $dstDir -ItemType Directory -Force
        }

        Write-Log ("Downloaden: {0} -> {1}" -f $src, $dst)
        $fileResult = Invoke-WebRequestSafe -Uri $src -OutFile $dst
        if (-not $fileResult.Ok) {
            throw "HTTP fout bij download ($($fileResult.Status)): $($fileResult.Error)"
        }

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
    } catch {
        Write-Log ("FOUT bij {0}: {1}" -f $src, $_.Exception.Message)
        throw "Kon functie van '$src' niet downloaden of laden."
    }
}

Write-Log ("Bootstrap voltooid. Functions geladen: {0}" -f ($Loaded -join ', '))
