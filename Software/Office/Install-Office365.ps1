[CmdletBinding()]
param()

# --- AUTOMATISERING CONFIGURATIE ---
$ConfigXmlUrl = "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/Config.xml"
$OdtExeUrl    = "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/setup.exe"
$WorkFolder   = "C:\Windows\Temp\OfficeInstaller"
# ----------------------------------

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param($Message, [ValidateSet("INFO", "ERROR", "SUCCESS")] $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{"INFO"="White"; "ERROR"="Red"; "SUCCESS"="Green"}
    Write-Host "[$timestamp][$Level] $Message" -ForegroundColor $colors[$Level]
}

try {
    Write-Log "Office 365 installatie gestart (Volledig Geautomatiseerd)."

    # folder voorbereiden
    if (Test-Path $WorkFolder) { 
        Write-Log "Oude werkmap verwijderen..."
        Remove-Item $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue 
    }
    New-Item -Path $WorkFolder -ItemType Directory -Force | Out-Null

    $xmlPath = Join-Path $WorkFolder "Configuration.xml"
    $setupExe = Join-Path $WorkFolder "setup.exe"

    # Downloaden van GitHub
    Write-Log "Bestanden ophalen van GitHub..."
    Invoke-WebRequest -Uri $ConfigXmlUrl -OutFile $xmlPath -UseBasicParsing
    Invoke-WebRequest -Uri $OdtExeUrl -OutFile $setupExe -UseBasicParsing

    # Installatie uitvoeren
    Write-Log "Installatie start (Configure-modus)..."
    $process = Start-Process -FilePath $setupExe -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru -WindowStyle Hidden
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Office is succesvol geïnstalleerd!" "SUCCESS"
    } else {
        throw "Installatie mislukt. Exitcode: $($process.ExitCode). Controleer de Office logs in C:\Windows\Temp."
    }

    exit 0
}
catch {
    Write-Log "FOUT: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    # Opruimen
    if (Test-Path $WorkFolder) { 
        Write-Log "Opruimen tijdelijke bestanden..."
        Remove-Item $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue 
    }
}
