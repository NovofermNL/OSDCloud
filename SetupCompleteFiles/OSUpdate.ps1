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

# Standaard security & error handling
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'

function Get-Ts { Get-Date -Format 'dd-MM-yyyy HH:mm:ss' }

# 32-bit → 64-bit relaunch (indien van toepassing)
if ($env:PROCESSOR_ARCHITEW6432 -and (Test-Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe")) {
    $argsCommon = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', "$PSCommandPath", '-Reboot', "$Reboot", '-RebootTimeout', "$RebootTimeout")
    if ($ExcludeDrivers) { $argsCommon += '-ExcludeDrivers' }
    if ($ExcludeUpdates) { $argsCommon += '-ExcludeUpdates' }
    & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" @argsCommon
    exit $LASTEXITCODE
}

# Ongeldige combinatie switches afvangen
if ($ExcludeDrivers -and $ExcludeUpdates) {
    Write-Error "Gebruik niet zowel -ExcludeDrivers als -ExcludeUpdates. Kies één van beiden."
    exit 87  # ERROR_INVALID_PARAMETER
}

# Tag + logging pad (ProgramData)
$BaseDir = Join-Path $env:ProgramData 'Microsoft\UpdateOS'
New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null

$TagFile = Join-Path $BaseDir 'UpdateOS.ps1.tag'
Set-Content -Path $TagFile -Value 'Installed' -Encoding UTF8

$LogFile = Join-Path $BaseDir 'UpdateOS.log'
Start-Transcript -Path $LogFile -Append
try {
    $needReboot = $false

    Write-Output "$(Get-Ts) Opt-in voor Microsoft Update"
    $ServiceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
    $ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
    try { $null = $ServiceManager.AddService2($ServiceId, 7, '') } catch { Write-Output "$(Get-Ts) Service al geactiveerd: $($_.Exception.Message)" }

    # Eén sessie hergebruiken
    $WUSession = New-Object -ComObject 'Microsoft.Update.Session'
    $Searcher = $WUSession.CreateUpdateSearcher()
    $Downloader = $WUSession.CreateUpdateDownloader()
    $Installer = $WUSession.CreateUpdateInstaller()

    # Query-set bepalen
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

                # Feature updates en Previews overslaan
                $isFeature = $u.Categories | Where-Object { $_.CategoryID -eq '3689BDC8-B205-4AF4-8D4A-A63924C5E9D5' }
                if ($isFeature) { Write-Output "$(Get-Ts) Overslaan feature update: $($u.Title)"; continue }
                if ($u.Title -match 'Preview') { Write-Output "$(Get-Ts) Overslaan preview update: $($u.Title)"; continue }

                [void]$WUUpdates.Add($u)
            }
        }
        catch {
            Write-Warning "$(Get-Ts) Kon niet zoeken naar updates (mogelijk tijdens specialize): $($_.Exception.Message)"
        }
    }

    if ($WUUpdates.Count -eq 0) {
        Write-Output "$(Get-Ts) Geen updates gevonden."
        Stop-Transcript
        exit 0
    }

    Write-Output "$(Get-Ts) Updates gevonden: $($WUUpdates.Count)"

    # Per update downloaden en installeren (betere voortgangslogs)
    foreach ($update in $WUUpdates) {
        $single = New-Object -ComObject 'Microsoft.Update.UpdateColl'
        $null = $single.Add($update)

        $Downloader.Updates = $single
        $Installer.Updates = $single
        $Installer.ForceQuiet = $true

        Write-Output "$(Get-Ts) Downloaden: $($update.Title)"
        $dl = $Downloader.Download()
        Write-Output ("{0}   Download resultaat: {1} (0x{2:X8})" -f (Get-Ts), $dl.ResultCode, $dl.HResult)

        Write-Output "$(Get-Ts) Installeren: $($update.Title)"
        $inst = $Installer.Install()
        Write-Output ("{0}   Install resultaat: {1} (0x{2:X8})" -f (Get-Ts), $inst.ResultCode, $inst.HResult)

        if ($inst.RebootRequired) { $needReboot = $true }
    }

    # Exitcodes / reboot-beleid
    if ($needReboot) {
        Write-Output "$(Get-Ts) Reboot vereist volgens Windows Update."
        switch ($Reboot) {
            'Hard' {
                Write-Output "$(Get-Ts) Exit 1641 (hard reboot vereist)."
                Stop-Transcript
                exit 1641
            }
            'Soft' {
                Write-Output "$(Get-Ts) Exit 3010 (soft reboot vereist)."
                Stop-Transcript
                exit 3010
            }
            'Delayed' {
                Write-Output "$(Get-Ts) Reboot over $RebootTimeout seconden."
                Stop-Transcript
                & shutdown.exe /r /t $RebootTimeout /c "Rebooting to complete the installation of Windows updates."
                exit 0
            }
            default {
                Write-Output "$(Get-Ts) Reboot nodig, maar geen reboot aangevraagd (Reboot=None)."
                Stop-Transcript
                exit 0
            }
        }
    }
    else {
        Write-Output "$(Get-Ts) Geen reboot vereist."
        Stop-Transcript
        exit 0
    }
}
catch {
    Write-Error "$(Get-Ts) Onverwachte fout: $($_.Exception.Message)"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
