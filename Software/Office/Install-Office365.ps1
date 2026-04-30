# C:\Windows\Temp\Install-Office365.ps1
#requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ConfigXmlUrl = 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/Config.xml'
$OdtExeUrl    = 'https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Software/Office/setup.exe'
$WorkFolder   = 'C:\Windows\Temp\OfficeInstaller'
$LogFile      = Join-Path $WorkFolder 'Install-Office365.log'
$XmlPath      = Join-Path $WorkFolder 'Configuration.xml'
$SetupExe     = Join-Path $WorkFolder 'setup.exe'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp][$Level] $Message"

    Write-Host $line
    if (Test-Path $WorkFolder) {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

function Test-IsSystem {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -eq 'NT AUTHORITY\SYSTEM'
}

function Stop-OfficeProcesses {
    $officeProcesses = @(
        'winword','excel','powerpnt','outlook','onenote','onenotem',
        'msaccess','mspub','visio','winproj','teams','lync','ucmapi',
        'groove','officeclicktorun','officec2rclient','integratedoffice','setup'
    )

    Write-Log 'Controleer en sluit actieve Office/Click-to-Run processen...'

    foreach ($name in $officeProcesses) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Write-Log "Proces afsluiten: $($_.ProcessName) PID $($_.Id)" 'WARNING'
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Log "Kon proces niet afsluiten: $($_.ProcessName) PID $($_.Id). Fout: $($_.Exception.Message)" 'WARNING'
            }
        }
    }

    Start-Sleep -Seconds 5
}

try {
    if (Test-Path $WorkFolder) {
        Remove-Item $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $WorkFolder -ItemType Directory -Force | Out-Null

    Write-Log 'Office 365 installatie gestart.'
    Write-Log "Uitvoerende gebruiker: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "Is SYSTEM: $(Test-IsSystem)"
    Write-Log "Werkmap: $WorkFolder"

    Invoke-WebRequest -Uri $ConfigXmlUrl -OutFile $XmlPath -UseBasicParsing
    Invoke-WebRequest -Uri $OdtExeUrl    -OutFile $SetupExe -UseBasicParsing

    if (!(Test-Path $XmlPath))  { throw 'Configuration.xml is niet gedownload.' }
    if (!(Test-Path $SetupExe)) { throw 'setup.exe is niet gedownload.' }

    $xmlSizeKb   = [math]::Round((Get-Item $XmlPath).Length / 1KB, 2)
    $setupSizeKb = [math]::Round((Get-Item $SetupExe).Length / 1KB, 2)

    Write-Log "Configuration.xml grootte: $xmlSizeKb KB"
    Write-Log "setup.exe grootte: $setupSizeKb KB"

    if ((Get-Item $SetupExe).Length -lt 500KB) {
        throw 'setup.exe lijkt niet correct gedownload. Bestand is te klein.'
    }

    Stop-OfficeProcesses

    Write-Log "Installatie start met: `"$SetupExe`" /configure `"$XmlPath`""

    $proc = Start-Process `
        -FilePath $SetupExe `
        -ArgumentList "/configure `"$XmlPath`"" `
        -WorkingDirectory $WorkFolder `
        -Wait `
        -PassThru

    Write-Log "Office setup.exe exitcode: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0) {
        Write-Log 'Office installatie mislukt.' 'ERROR'
        Write-Log 'Controleer ODT/ClickToRun logs in C:\Windows\Temp en C:\ProgramData\Microsoft\ClickToRun\Log' 'WARNING'
        exit $proc.ExitCode
    }

    Write-Log 'Office is succesvol geïnstalleerd.' 'SUCCESS'
    exit 0
}
catch {
    Write-Log "FOUT: $($_.Exception.Message)" 'ERROR'
    Write-Log 'Controleer ODT/ClickToRun logs in C:\Windows\Temp en C:\ProgramData\Microsoft\ClickToRun\Log' 'WARNING'
    exit 1
}
