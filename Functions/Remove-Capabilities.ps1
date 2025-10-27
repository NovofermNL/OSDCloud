Write-Host "[+] Function Remove-Capabilities"

function Remove-Capabilities {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$All,
        [switch]$Force
    )

    begin {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ErrorActionPreference = 'Stop'

        $LogRoot = 'C:\Windows\Temp\Capability-Removal'
        if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
        $LogFile = Join-Path $LogRoot ("Remove-Capabilities_{0}.log" -f (Get-Date -Format 'dd-MM-yyyy_HH-mm-ss'))

        function Write-Log {
            param([string]$Message)
            $ts = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
            Add-Content -Path $LogFile -Value "$ts`t$Message"
            Write-Verbose $Message
        }

        function Test-OpenSSHInUse {
            try {
                $procs = Get-Process -Name 'ssh','scp','sftp','ssh-agent' -ErrorAction SilentlyContinue
                return [bool]$procs
            } catch { return $false }
        }

        if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
            throw "Out-GridView is niet beschikbaar. Installeer het RSAT/GUI onderdeel of gebruik PowerShell 7 + Microsoft.PowerShell.GraphicalTools."
        }
    }

    process {
        Write-Log "Start Remove-Capabilities. Log: $LogFile"

        $allCaps = Get-WindowsCapability -Online
        $caps = if ($All) { $allCaps } else { $allCaps | Where-Object State -eq 'Installed' }

        if (-not $caps) {
            Write-Host "Geen capabilities gevonden voor de huidige filter."
            return
        }

        $selection = $caps |
            Select-Object Name, State |
            Out-GridView -PassThru -Title ("Selecteer capabilities om te verwijderen ({0})" -f ($(if($All) {'alle staten'} else {'alleen Installed'})))

        if (-not $selection) {
            Write-Host "Niets geselecteerd. Stop."
            return
        }

        $results = foreach ($item in $selection) {
            $name  = $item.Name
            $state = $item.State

            if ($state -ne 'Installed') {
                Write-Log "Overgeslagen (niet geïnstalleerd): $name (State=$state)"
                [PSCustomObject]@{ Name=$name; Action='Skip'; Result=$state; RestartNeeded=$false; Message='Niet geïnstalleerd' }
                continue
            }

            if ($name -like 'OpenSSH.Client*' -and -not $Force) {
                if (Test-OpenSSHInUse) {
                    Write-Log "Overgeslagen: $name lijkt in gebruik (ssh/scp/sftp/ssh-agent actief). Gebruik -Force om te forceren."
                    [PSCustomObject]@{ Name=$name; Action='Skip'; Result='InUse'; RestartNeeded=$false; Message='OpenSSH proces actief' }
                    continue
                }
            }

            if ($PSCmdlet.ShouldProcess($name, "Remove-WindowsCapability")) {
                try {
                    Write-Log "Verwijderen: $name"
                    $res = Remove-WindowsCapability -Online -Name $name -ErrorAction Stop
                    $restart = [bool]$res.RestartNeeded
                    Write-Log "Resultaat: State=$($res.State); RestartNeeded=$restart"
                    [PSCustomObject]@{ Name=$name; Action='Remove'; Result=$res.State; RestartNeeded=$restart; Message='OK' }
                } catch {
                    Write-Log "FOUT bij verwijderen van $name : $($_.Exception.Message)"
                    [PSCustomObject]@{ Name=$name; Action='Remove'; Result='Error'; RestartNeeded=$false; Message=$_.Exception.Message }
                }
            } else {
                [PSCustomObject]@{ Name=$name; Action='WhatIf'; Result='Simulated'; RestartNeeded=$false; Message='WhatIf' }
            }
        }

        $results | Format-Table -AutoSize | Out-String | Write-Host
        return $results
    }
}
