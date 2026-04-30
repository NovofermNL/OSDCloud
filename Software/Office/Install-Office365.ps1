[CmdletBinding()]
param()

# --- AUTOMATISERING CONFIGURATIE ---
$ConfigXmlUrl = "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/Config.xml"
$OdtExeUrl    = "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/setup.exe"
$WorkFolder   = "C:\Windows\Temp\OfficeInstaller"
$LogFile      = Join-Path $WorkFolder "Install-Office365.log"
# ----------------------------------

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARNING")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"

    Write-Host $line

    if (Test-Path $WorkFolder) {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

try {
    Write-Host "Office 365 installatie gestart."

    if (Test-Path $WorkFolder) {
        Remove-Item $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $WorkFolder -ItemType Directory -Force | Out-Null

    Write-Log "Office 365 installatie gestart als gebruiker: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "Werkmap: $WorkFolder"

    $xmlPath  = Join-Path $WorkFolder "Configuration.xml"
    $setupExe = Join-Path $WorkFolder "setup.exe"

    Write-Log "Download Config.xml..."
    Invoke-WebRequest -Uri $ConfigXmlUrl -OutFile $xmlPath -UseBasicParsing

    Write-Log "Download setup.exe..."
    Invoke-WebRequest -Uri $OdtExeUrl -OutFile $setupExe -UseBasicParsing

    if (!(Test-Path $xmlPath)) {
        throw "Configuration.xml is niet gedownload."
    }

    if (!(Test-Path $setupExe)) {
        throw "setup.exe is niet gedownload."
    }

    $setupSizeKb = [math]::Round((Get-Item $setupExe).Length / 1KB, 2)
    $xmlSizeKb   = [math]::Round((Get-Item $xmlPath).Length / 1KB, 2)

    Write-Log "Configuration.xml grootte: $xmlSizeKb KB"
    Write-Log "setup.exe grootte: $setupSizeKb KB"

    if ((Get-Item $setupExe).Length -lt 500KB) {
        throw "setup.exe lijkt niet correct gedownload. Bestand is te klein."
    }

    Write-Log "Config.xml inhoud:"
    Get-Content $xmlPath | ForEach-Object {
        Write-Log "XML: $_"
    }

    Write-Log "Controle bestaande Office Click-to-Run processen..."
    Get-Process OfficeClickToRun, setup -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Proces actief: $($_.Name) PID $($_.Id)" "WARNING"
    }

    Write-Log "Installatie start met: setup.exe /configure `"$xmlPath`""

    $process = Start-Process `
        -FilePath $setupExe `
        -ArgumentList "/configure `"$xmlPath`"" `
        -WorkingDirectory $WorkFolder `
        -Wait `
        -PassThru `
        -WindowStyle Hidden

    Write-Log "Office setup.exe exitcode: $($process.ExitCode)"

    if ($process.ExitCode -eq 0) {
        Write-Log "Office is succesvol geïnstalleerd." "SUCCESS"

        Write-Log "Opruimen tijdelijke bestanden..."
        Remove-Item $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue

        exit 0
    }
    else {
        Write-Log "Office installatie mislukt met exitcode: $($process.ExitCode)" "ERROR"
        Write-Log "Tijdelijke bestanden blijven staan voor troubleshooting: $WorkFolder" "WARNING"
        Write-Log "Controleer ook Office logs in C:\Windows\Temp en C:\ProgramData\Microsoft\ClickToRun\Log" "WARNING"

        exit $process.ExitCode
    }
}
catch {
    Write-Log "FOUT: $($_.Exception.Message)" "ERROR"
    Write-Log "Tijdelijke bestanden blijven staan voor troubleshooting: $WorkFolder" "WARNING"
    exit 1
}
