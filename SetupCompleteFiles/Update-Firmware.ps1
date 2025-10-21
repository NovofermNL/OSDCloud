[CmdletBinding()]
param(
    [ValidateSet('Soft','Hard','None','Delayed')]
    [string]$Reboot = 'None',
    [int]$RebootTimeout = 10
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:needReboot = $false

# Relaunch x64 indien nodig
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64" -and (Test-Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe")) {
    & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -File "$PSCommandPath" -Reboot $Reboot -RebootTimeout $RebootTimeout
    exit $LASTEXITCODE
}

# Logging
$logPath = "C:\Windows\Temp\Windows-FirmwareAndDrivers.log"
Start-Transcript -Path $logPath | Out-Null
function Now { Get-Date -Format 'dd-MM-yyyy HH:mm:ss' }

try {
    Write-Output "$(Now) Start: Windows driver- en firmwareupdates (Microsoft Update)."

    # Microsoft Update opt-in 
    try {
        $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
        $muId = '7971f918-a847-4430-9279-4a52d1efe18d'
        [void]$svcMgr.AddService2($muId, 7, '')
        Write-Output "$(Now) Microsoft Update-service toegevoegd of reeds aanwezig."
    } catch {
        Write-Output "$(Now) Microsoft Update opt-in waarschijnlijk al actief: $($_.Exception.Message)"
    }

    # Eén sessie + helpers
    $session    = New-Object -ComObject Microsoft.Update.Session
    $searcher   = $session.CreateUpdateSearcher()
    $downloader = $session.CreateUpdateDownloader()
    $installer  = $session.CreateUpdateInstaller()

    function New-UpdateColl { New-Object -ComObject Microsoft.Update.UpdateColl }

    function Add-Updates {
        param(
            [object]$Updates,
            [object]$ToAdd
        )
        foreach ($u in $ToAdd) {
            if (-not $u.EulaAccepted) { $u.EulaAccepted = $true }
            if ($u.Title -notmatch '(?i)\bPreview\b') { [void]$Updates.Add($u) }
        }
    }

    # 1) Drivers
    Write-Output "$(Now) Zoeken naar driverupdates..."
    $driverResult = $searcher.Search("IsInstalled=0 and Type='Driver'")
    $allToInstall = New-UpdateColl
    Add-Updates -Updates $allToInstall -ToAdd $driverResult.Updates
    $drvCount = $driverResult.Updates.Count

    # 2) Firmware
    Write-Output "$(Now) Zoeken naar firmwareupdates..."
    $swResult = $searcher.Search("IsInstalled=0 and Type='Software'")
    $firmwareCandidates = @()
    foreach ($u in $swResult.Updates) {
        # Filter op categorie-naam 'Firmware' of herkenbare titel
        $isFirmwareCategory = $false
        foreach ($c in $u.Categories) {
            if ($c.Name -match '(?i)^Firmware$') { $isFirmwareCategory = $true; break }
        }
        $titleLooksFirmware = $u.Title -match '(?i)\b(Firmware|BIOS|UEFI|System Firmware)\b'
        if ($isFirmwareCategory -or $titleLooksFirmware) {
            $firmwareCandidates += $u
        }
    }
    Add-Updates -Updates $allToInstall -ToAdd $firmwareCandidates
    $fwCount = $firmwareCandidates.Count

    $total = $allToInstall.Count
    if ($total -lt 1) {
        Write-Output "$(Now) Geen driver- of firmwareupdates gevonden."
    } else {
        Write-Output "$(Now) Gevonden: $total update(s) (Drivers: $drvCount, Firmware: $fwCount). Downloaden..."
        $downloader.Updates = $allToInstall
        [void]$downloader.Download()

        Write-Output "$(Now) Installeren..."
        $installer.ForceQuiet = $true
        $installer.Updates = $allToInstall
        $installResult = $installer.Install()

        if ($installResult -and $installResult.RebootRequired) { $script:needReboot = $true }
        Write-Verbose ($installResult | Out-String)
        Write-Output "$(Now) Installatie gereed. Reboot vereist: $($script:needReboot)"
    }

    # Reboot-afhandeling
    if ($script:needReboot) {
        Write-Output "$(Now) Windows Update geeft aan dat herstart nodig is."
    } else {
        Write-Output "$(Now) Geen herstart vereist volgens Windows Update."
    }

    switch ($Reboot) {
        'Hard'    { Write-Output "$(Now) Beleid=Hard: exit 1641."; exit 1641 }
        'Soft'    { Write-Output "$(Now) Beleid=Soft: exit 3010."; exit 3010 }
        'Delayed' { Write-Output "$(Now) Beleid=Delayed: reboot over $RebootTimeout sec."; Start-Process shutdown.exe -ArgumentList "/r /t $RebootTimeout /c `"Reboot om updates te voltooien.`""; exit 0 }
        Default   { Write-Output "$(Now) Beleid=None: geen reboot door script."; exit 0 }
    }
}
catch {
    Write-Output "$(Now) FOUT: $($_.Exception.Message)"
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
