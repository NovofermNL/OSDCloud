[CmdletBinding()]
Param(
    [Parameter(Mandatory = $False)]
    [ValidateSet('Soft', 'Hard', 'None', 'Delayed')]
    [string] $Reboot = 'Soft',

    [Parameter(Mandatory = $False)]
    [int] $RebootTimeout = 120,

    [Parameter(Mandatory = $False)]
    [switch] $ExcludeDrivers,

    [Parameter(Mandatory = $False)]
    [switch] $ExcludeUpdates
)


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'

function Get-Ts { Get-Date -Format 'dd-MM-yyyy HH:mm:ss' }

# --- 32-bit → 64-bit relaunch (indien van toepassing) ---
# Zorgt ervoor dat de Windows Update COM objecten in de 64-bit context worden uitgevoerd.
if ($env:PROCESSOR_ARCHITEW6432 -and (Test-Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe")) {
    $argsCommon = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', "$PSCommandPath", '-Reboot', "$Reboot", '-RebootTimeout', "$RebootTimeout")
    if ($ExcludeDrivers) { $argsCommon += '-ExcludeDrivers' }
    if ($ExcludeUpdates) { $argsCommon += '-ExcludeUpdates' }
    Write-Output "$(Get-Ts) 32-bit omgeving gedetecteerd. Relaunch naar 64-bit..."
    & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" @argsCommon
    exit $LASTEXITCODE
}

# --- Validatie & Logging Setup ---
# Ongeldige combinatie switches afvangen
if ($ExcludeDrivers -and $ExcludeUpdates) {
    Write-Error "Gebruik niet zowel -ExcludeDrivers als -ExcludeUpdates. Kies één van beiden."
    exit 87  # ERROR_INVALID_PARAMETER
}

# Tag + logging pad (ProgramData is persistent en toegankelijk voor Autopilot)
$BaseDir = Join-Path $env:ProgramData 'Microsoft\UpdateOS'
New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null

# Deze tag-file dient als de markering dat het script (succesvol) is uitgevoerd
$TagFile = Join-Path $BaseDir 'UpdateOS.ps1.tag'
Set-Content -Path $TagFile -Value 'Installed' -Encoding UTF8

$LogFile = Join-Path $BaseDir 'UpdateOS.log'
# Start-Transcript vangt alle output (Write-Output, Write-Error, Write-Warning)
Start-Transcript -Path $LogFile -Append
try {
    $needReboot = $false

    Write-Output "$(Get-Ts) Opt-in voor Microsoft Update (voor drivers en overige Microsoft producten)."
    $ServiceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
    $ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d' # Microsoft Update Service ID
    try { $null = $ServiceManager.AddService2($ServiceId, 7, '') } catch { Write-Output "$(Get-Ts) Service al geactiveerd of fout bij activatie: $($_.Exception.Message)" }

    # Eén sessie hergebruiken
    $WUSession = New-Object -ComObject 'Microsoft.Update.Session'
    $Searcher = $WUSession.CreateUpdateSearcher()
    $Downloader = $WUSession.CreateUpdateDownloader()
    $Installer = $WUSession.CreateUpdateInstaller()

    # Query-set bepalen
    # We zoeken naar updates die NIET geïnstalleerd zijn.
    $queries = switch ($true) {
        { $ExcludeDrivers } { @("IsInstalled=0 and Type='Software'"); break }
        { $ExcludeUpdates } { @("IsInstalled=0 and Type='Driver'"); break }
        default { @("IsInstalled=0 and Type='Software'", "IsInstalled=0 and Type='Driver'") }
    }

    # Updates verzamelen
    $WUUpdates = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($q in $queries) {
        Write-Output "$(Get-Ts) Zoeken naar updates met query: $q"
        try {
            $res = $Searcher.Search($q)
            foreach ($u in $res.Updates) {
                if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }

                # Categorie ID voor 'Feature Pack' (Feature Updates)
                $isFeature = $u.Categories | Where-Object { $_.CategoryID -eq '3689BDC8-B205-4AF4-8D4A-A63924C5E9D5' }
                if ($isFeature) { Write-Output "$(Get-Ts) Overslaan feature update: $($u.Title)"; continue }
                # Overslaan van optionele Preview/C-week updates
                if ($u.Title -match 'Preview|C-week') { Write-Output "$(Get-Ts) Overslaan preview update: $($u.Title)"; continue }

                [void]$WUUpdates.Add($u)
            }
        }
        catch {
            # Veelvoorkomend tijdens 'Specialize' of bij problemen met de WU service
            Write-Warning "$(Get-Ts) Kon niet zoeken naar updates: $($_.Exception.Message)"
        }
    }

    if ($WUUpdates.Count -eq 0) {
        Write-Output "$(Get-Ts) Geen updates gevonden. Script beëindigd."
        Stop-Transcript
        exit 0
    }

    Write-Output "$(Get-Ts) Updates gevonden: $($WUUpdates.Count) - Start download/installatie cyclus."

    # Per update downloaden en installeren (garandeert gedetailleerde logs)
    foreach ($update in $WUUpdates) {
        $kbId = ($update.KBArticleIDs -join ', ')
        $titleLog = "$($update.Title) (KB:$kbId)"

        $single = New-Object -ComObject 'Microsoft.Update.UpdateColl'
        $null = $single.Add($update)

        $Downloader.Updates = $single
        $Installer.Updates = $single
        $Installer.ForceQuiet = $true

        Write-Output "$(Get-Ts) Downloaden: $titleLog"
        $dl = $Downloader.Download()
        Write-Output ("{0}   Download resultaat: {1} (0x{2:X8})" -f (Get-Ts), $dl.ResultCode, $dl.HResult)

        Write-Output "$(Get-Ts) Installeren: $titleLog"
        $inst = $Installer.Install()
        Write-Output ("{0}   Install resultaat: {1} (0x{2:X8})" -f (Get-Ts), $inst.ResultCode, $inst.HResult)

        if ($inst.RebootRequired) { $needReboot = $true }
    }

    # --- Afhandeling Reboot Beleid ---
    if ($needReboot) {
        Write-Output "$(Get-Ts) Reboot vereist volgens Windows Update. Beleid: $Reboot"
        switch ($Reboot) {
            'Hard' {
                Write-Output "$(Get-Ts) Script beëindigd met exit code 1641 (Hard Reboot)."
                exit 1641 # MS_DEPLOY_REBOOT_REQUIRED_HARD
            }
            'Soft' {
                Write-Output "$(Get-Ts) Script beëindigd met exit code 3010 (Soft Reboot)."
                exit 3010 # MS_DEPLOY_REBOOT_REQUIRED_SOFT
            }
            'Delayed' {
                Write-Output "$(Get-Ts) Initiëren van geplande reboot over $RebootTimeout seconden."
                & shutdown.exe /r /t $RebootTimeout /c "Rebooting to complete the installation of Windows updates (via UpdateOS.ps1)."
                exit 0
            }
            default {
                Write-Output "$(Get-Ts) Reboot nodig, maar overgeslagen (Reboot=None)."
                exit 0
            }
        }
    }
    else {
        Write-Output "$(Get-Ts) Geen reboot vereist. Script beëindigd."
        exit 0
    }
}
catch {
    Write-Error "$(Get-Ts) FATALE Onverwachte fout: $($_.Exception.Message)"
    # Probeer transcriptie af te sluiten, zelfs na een fatale fout
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
finally {
    # Zorg ervoor dat de transcriptie altijd stopt als het try-catch blok wordt verlaten (indien niet al gestopt)
    if ($LASTEXITCODE -ne 1) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
