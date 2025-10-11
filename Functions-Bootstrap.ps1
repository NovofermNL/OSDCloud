# --- Novoferm Functions Bootstrap v8 (Index + Tree API + ZIP fallback) ---
[CmdletBinding()]
param(
    [string]$Owner  = 'NovofermNL',
    [string]$Repo   = 'OSDCloud',
    [string]$Branch = 'main'  # of specifieke SHA voor pinning
)

# TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Consts =====
$LogFile   = Join-Path $env:SystemRoot 'Temp\OSDCloud-Functions.log'
$LocalRoot = Join-Path $env:TEMP 'Novoferm-Functions'
$Headers   = @{ 'User-Agent' = 'PowerShell'; 'Accept' = 'application/vnd.github+json' }

# Raw/Tree/Zip endpoints
$RawBase     = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch"
$IndexUrl    = "$RawBase/Functions/FunctionsIndex.txt"
$TreeApiUrl  = "https://api.github.com/repos/$Owner/$Repo/git/trees/$Branch?recursive=1"
$ZipUrl      = "https://codeload.github.com/$Owner/$Repo/zip/refs/heads/$Branch"

# ===== Helpers =====
function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $stamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
    "{0}  {1}" -f $stamp, $Message | Add-Content -Path $LogFile -Encoding UTF8
}

function Is-HtmlContent {
    param([string]$Text)
    if (-not $Text) { return $false }
    return ($Text -match '<!DOCTYPE html>|<html|HTTP-EQUIV|<title>')
}

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
        $status = $null; $desc = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            $desc   = $_.Exception.Response.StatusDescription
        }
        Write-Log ("WEB-ERROR {0} {1}: {2} [{3}]" -f $status, $desc, $_.Exception.Message, $Uri)
        return @{ Ok = $false; Status = $status; Error = $_.Exception.Message }
    }
}

function Ensure-Dir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -ItemType Directory -Force
    }
}

# ===== Start =====
Write-Log ("Start bootstrap voor {0}/{1}@{2}" -f $Owner, $Repo, $Branch)

try {
    Ensure-Dir -Path $LocalRoot
    Write-Log ("Lokale map: {0}" -f $LocalRoot)
} catch {
    Write-Log ("FATALE FOUT: Kan lokale map niet maken. {0}" -f $_.Exception.Message)
    throw "Kan lokale map niet maken."
}

# === Stap 1: Probeer FunctionsIndex.txt (raw) ===
$RawUrls = @()
$LocalIndex = Join-Path $LocalRoot 'FunctionsIndex.txt'
Write-Log ("Probeer index downloaden: {0}" -f $IndexUrl)
$idx = Invoke-WebRequestSafe -Uri $IndexUrl -OutFile $LocalIndex
if ($idx.Ok) {
    $idxHead = Get-Content -Path $LocalIndex -TotalCount 5 -Raw
    if (Is-HtmlContent -Text $idxHead) {
        Write-Log "Index is HTML (redirect/blocked). Ga naar Tree API fallback."
    } else {
        try {
            $lines = (Get-Content $LocalIndex -Raw -Encoding UTF8) -split "\r?\n"
            foreach ($l in $lines) {
                $line = $l.Trim()
                if (-not $line -or $line -match '^\s*#') { continue }
                if ($line -match '^https?://') {
                    # Normaliseer eventueel github.com/blob → raw
                    $url = $line -replace '^https?://github\.com/', 'https://raw.githubusercontent.com/'
                    $url = $url -replace '/blob/', '/'
                    # Alleen .ps1
                    if ($url -like '*.ps1') { $RawUrls += $url }
                } else {
                    # Relative pad
                    $rel = $line -replace '^[./\\]+',''
                    if ($rel -like '*.ps1') { $RawUrls += ("{0}/Functions/{1}" -f $RawBase, $rel) }
                }
            }
            Write-Log ("Index parsed: {0} items." -f $RawUrls.Count)
        } catch {
            Write-Log ("Index leesfout, ga naar Tree API fallback. {0}" -f $_.Exception.Message)
            $RawUrls = @()
        }
    }
} else {
    Write-Log "Index download niet gelukt, ga naar Tree API fallback."
}

# === Stap 2: Tree API (recursive) → alle Functions/*.ps1 ===
if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log ("Ophalen tree via API: {0}" -f $TreeApiUrl)
    try {
        $tree = Invoke-RestMethod -Uri $TreeApiUrl -Headers $Headers -ErrorAction Stop
    } catch {
        Write-Log ("Tree API mislukt: {0}" -f $_.Exception.Message)
        $tree = $null
    }

    if ($tree -and $tree.tree) {
        $ps1 = $tree.tree | Where-Object {
            $_.type -eq 'blob' -and $_.path -like 'Functions/*.ps1' -or $_.path -like 'Functions/*/*.ps1'
        }
        foreach ($n in $ps1) {
            # Bouw raw URL: raw.base + / + path
            $RawUrls += ("{0}/{1}" -f $RawBase, $n.path)
        }
        Write-Log ("Tree API items: {0}" -f $RawUrls.Count)
    } else {
        Write-Log "Geen tree-gegevens ontvangen of leeg. Ga naar ZIP fallback."
    }
}

# === Stap 3: ZIP fallback (alleen als nog steeds niets) ===
$ZipExtractRoot = $null
if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log ("ZIP fallback downloaden: {0}" -f $ZipUrl)
    $zipPath = Join-Path $LocalRoot ('repo-{0}.zip' -f (Get-Random))
    $zipRes = Invoke-WebRequestSafe -Uri $ZipUrl -OutFile $zipPath
    if ($zipRes.Ok -and (Test-Path $zipPath)) {
        try {
            $ZipExtractRoot = Join-Path $LocalRoot ('repo-{0}' -f (Get-Random))
            Ensure-Dir -Path $ZipExtractRoot
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $ZipExtractRoot)
            Remove-Item $zipPath -Force

            # Zoek alle ps1 onder */Functions/*.ps1 in de uitgepakte boom
            $funcRoot = Get-ChildItem -Path $ZipExtractRoot -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName 'Functions')
            } | Select-Object -First 1

            if ($funcRoot) {
                $ps1Files = Get-ChildItem -Path (Join-Path $funcRoot.FullName 'Functions') -Recurse -Filter *.ps1 -File
                foreach ($file in $ps1Files) {
                    # Kopieer naar $LocalRoot zelfde relatieve structuur
                    $rel = $file.FullName.Substring($funcRoot.FullName.Length + 1) # Functions\...\x.ps1
                    $dst = Join-Path $LocalRoot $rel
                    Ensure-Dir -Path (Split-Path $dst -Parent)
                    Copy-Item $file.FullName $dst -Force
                    # Laad direct
                    . $dst
                    Write-Log ("Loaded (ZIP): {0}" -f $rel)
                }
                Write-Log "Bootstrap voltooid via ZIP fallback."
                return
            } else {
                Write-Log "Kon Functions-map niet vinden in ZIP."
            }
        } catch {
            Write-Log ("ZIP fallback fout: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Log "ZIP download mislukt."
    }
}

# === Download & load alle RawUrls ===
if (-not $RawUrls -or $RawUrls.Count -eq 0) {
    Write-Log "FATALE FOUT: Geen functies gevonden via Index, Tree API of ZIP."
    throw "Geen functies om te laden (index, API en ZIP faalden)."
}

Write-Log ("Te laden items:`n{0}" -f ($RawUrls -join "`n"))

$Loaded = @()
foreach ($src in $RawUrls) {
    try {
        $uri  = [uri]$src
        $rel  = $uri.AbsolutePath -replace '^/',''
        # Neem alleen het stuk na .../{branch}/
        $m = [regex]::Match($rel, '^[^/]+/[^/]+/[^/]+/(.+)$')
        if ($m.Success) { $rel = $m.Groups[1].Value } # bv. Functions/Sub/X.ps1

        if ($rel -notlike 'Functions/*.ps1' -and $rel -notlike 'Functions/*/*.ps1') {
            # als iemand rare URL in index heeft gezet, overslaan
            Write-Log ("Sla over (geen Functions/*.ps1): {0}" -f $src)
            continue
        }

        $dst = Join-Path $LocalRoot $rel
        Ensure-Dir -Path (Split-Path $dst -Parent)

        Write-Log ("Download: {0} -> {1}" -f $src, $dst)
        $fileRes = Invoke-WebRequestSafe -Uri $src -OutFile $dst
        if (-not $fileRes.Ok) { throw ("HTTP fout {0}: {1}" -f $fileRes.Status, $fileRes.Error) }

        $head = Get-Content -Path $dst -TotalCount 8 -Raw
        if (Is-HtmlContent -Text $head) {
            Write-Log ("FOUT: HTML ontvangen i.p.v. .ps1 voor {0}" -f $src)
            Write-Log ("HEAD(voor debug):`n{0}" -f $head.Substring(0, [Math]::Min(250, $head.Length)))
            throw "Download gaf HTML terug"
        }

        . $dst
        $Loaded += $rel
        Write-Log ("Loaded: {0}" -f $rel)
    } catch {
        Write-Log ("FOUT bij {0}: {1}" -f $src, $_.Exception.Message)
        throw "Kon functie van '$src' niet downloaden of laden."
    }
}

Write-Log ("Bootstrap voltooid. Functions geladen: {0}" -f ($Loaded -join ', '))
