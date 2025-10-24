Write-Host "[+] function Rename-ComputerFromSerial"

function Rename-ComputerFromSerial {
    <#
    .SYNOPSIS
    Hernoemt de computer op basis van BIOS SerialNumber met een prefix.

    .DESCRIPTION
    Vormt een nieuwe naam als: <Prefix><Suffix>, waarbij <Suffix> de laatste tekens van het
    opgeschoonde BIOS-serial is (alleen A-Z/0-9, uppercase). Houdt rekening met NetBIOS-limiet (15 chars).

    .PARAMETER NoReboot
    Voorkomt automatische reboot na succesvolle Rename-Computer.

    .PARAMETER Prefix
    Aanpasbare prefix (default: 'NNMBLT-').

    .PARAMETER SuffixLength
    Aantal te gebruiken tekens uit einde van het serienummer (default: 8).

    .OUTPUTS
    PSCustomObject met CurrentName, NewName, RebootPlanned, LogFile.

    .EXAMPLE
    Rename-ComputerFromSerial
    .EXAMPLE
    Rename-ComputerFromSerial -Prefix 'NNLT-' -SuffixLength 10 -Confirm:$false
    .EXAMPLE
    Rename-ComputerFromSerial -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [switch]$NoReboot,
        [string]$Prefix = 'NNMBLT-',
        [int]$SuffixLength = 8
    )

    begin {
        # Altijd TLS 1.2 zoals gevraagd
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # --- Logging ---
        $LogRoot = 'C:\Windows\Temp\ComputerRename'
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
        $LogFile = Join-Path $LogRoot ("ComputerRename_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $dt = { Get-Date -Format 'dd-MM-yyyy HH:mm:ss' }
        function Write-Log([string]$msg){ "{0}  {1}" -f (& $dt), $msg | Tee-Object -FilePath $LogFile -Append }

        Write-Log "Start functie Rename-ComputerFromSerial."

        # --- Admin check ---
        $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if(-not $IsAdmin){
            Write-Log "FOUT: Deze functie moet als Administrator draaien."
            throw "Administratorrechten vereist."
        }

        function Get-SerialNumber {
            try {
                $sn = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
                if([string]::IsNullOrWhiteSpace($sn)){ throw "Leeg serienummer via CIM." }
                return $sn
            } catch {
                Write-Log "Waarschuwing: CIM gaf geen bruikbaar serienummer. Fallback naar WMI. Details: $($_.Exception.Message)"
                try {
                    $sn = (Get-WmiObject -Class Win32_BIOS -ErrorAction Stop).SerialNumber
                    if([string]::IsNullOrWhiteSpace($sn)){ throw "Leeg serienummer via WMI." }
                    return $sn
                } catch {
                    throw "Kon BIOS SerialNumber niet ophalen via CIM of WMI."
                }
            }
        }
    }

    process {
        try {
            $rawSN = Get-SerialNumber
            Write-Log ("Raw SerialNumber: '{0}'" -f $rawSN)

            # Alleen A-Z/0-9, uppercase
            $cleanSN = ($rawSN -replace '[^A-Za-z0-9]', '').ToUpper()
            if([string]::IsNullOrWhiteSpace($cleanSN)){
                throw "Serienummer bevatte geen bruikbare tekens."
            }

            # Laatste N tekens (padding met 0 indien korter)
            if($cleanSN.Length -ge $SuffixLength){
                $suffix = $cleanSN.Substring($cleanSN.Length - $SuffixLength, $SuffixLength)
            } else {
                $suffix = $cleanSN.PadLeft($SuffixLength,'0')
            }

            $NewName = "{0}{1}" -f $Prefix, $suffix

            # Huidige naam
            $CurrentName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
            Write-Log ("Huidige naam: {0}" -f $CurrentName)
            Write-Log ("Voorgestelde nieuwe naam: {0}" -f $NewName)

            if($CurrentName -eq $NewName){
                Write-Log "Geen actie nodig: naam is al correct."
                return [pscustomobject]@{
                    CurrentName   = $CurrentName
                    NewName       = $NewName
                    RebootPlanned = $false
                    LogFile       = $LogFile
                }
            }

            # Validatie hostnaam (max 15 chars voor NetBIOS, alleen A-Z/0-9/-)
            if($NewName.Length -gt 15){
                Write-Log ("Waarschuwing: '{0}' is langer dan 15 tekens. Inkorten voor NetBIOS-compatibiliteit." -f $NewName)
                $allowedSuffix = 15 - $Prefix.Length
                if($allowedSuffix -lt 1){ throw "Prefix is te lang t.o.v. 15-teken limiet." }
                $suffix  = $suffix.Substring($suffix.Length - $allowedSuffix, $allowedSuffix)
                $NewName = "{0}{1}" -f $Prefix, $suffix
                Write-Log ("Ingekorte nieuwe naam: {0}" -f $NewName)
            }
            if($NewName -notmatch '^[A-Z0-9-]+$'){
                throw "Nieuwe naam bevat ongeldige karakters. Overgebleven: $NewName"
            }

            if ($PSCmdlet.ShouldProcess("Computernaam wijzigen naar '$NewName'")) {
                Write-Log "Rename-Computer uitvoeren..."
                Rename-Computer -NewName $NewName -Force -ErrorAction Stop
                Write-Log "Rename-Computer succesvol."

                $rebootPlanned = $false
                if(-not $NoReboot){
                    Write-Log "Systeem wordt nu herstart om naamwijziging toe te passen."
                    $rebootPlanned = $true
                    Restart-Computer -Force
                } else {
                    Write-Log "NoReboot actief: geen herstart uitgevoerd. Herstart later vereist om naam door te voeren."
                }

                return [pscustomobject]@{
                    CurrentName   = $CurrentName
                    NewName       = $NewName
                    RebootPlanned = $rebootPlanned
                    LogFile       = $LogFile
                }
            }
        }
        catch {
            Write-Log ("FOUT: {0}" -f $_.Exception.Message)
            throw
        }
        finally {
            Write-Log "Functie gereed."
        }
    }
}
