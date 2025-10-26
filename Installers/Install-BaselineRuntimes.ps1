# =========================
# Install-BaselineRuntimes.ps1
# =========================

# Logging
$OSSoftLogs = "C:\Logs\OSDCloud\Install\SYSTEM\$env:COMPUTERNAME-OSSoftware.log"
New-Item -ItemType Directory -Path (Split-Path $OSSoftLogs) -Force | Out-Null
Start-Transcript -Path $OSSoftLogs

# Verbose standaard aan
$VerbosePreference = 'Continue'

# Beveiliging (jouw standaard)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    try { return [bool](Get-Command -Name $Name -ErrorAction Stop) }
    catch { return $false }
}

function Test-NETFramework48OrHigher {
    # 4.8 = Release >= 528040; 4.8.1 is hoger (533xxx afhankelijk van OS)
    $release = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
    if ($release -ge 528040) { return $true } else { return $false }
}

################################################################
# Package Manager
################################################################
if (Test-Command -Name 'choco') {
    Write-Verbose -Message "Chocolatey is al geïnstalleerd; overslaan."
}
else {
    Write-Host "Installing Chocolatey (nodig voor .NET Framework)..." -ForegroundColor Cyan
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    catch {
        Write-Error "Fout bij installeren van Chocolatey: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# Controleer winget
if (-not (Test-Command -Name 'winget')) {
    Write-Error "winget is niet aanwezig. Installeer App Installer / winget en start dit script opnieuw."
    Stop-Transcript
    exit 1
}

################################################################
# .NET Framework (4.8/4.8.1)
################################################################
if (Test-NETFramework48OrHigher) {
    Write-Verbose -Message ".NET Framework 4.8 of hoger is al aanwezig; installatie overslaan."
}
else {
    Write-Host "Installing Microsoft .NET Framework..." -ForegroundColor Cyan
    Write-Verbose -Message "Installing .NET Framework (choco package: dotnetfx)..."
    choco install dotnetfx -y --no-progress
}

################################################################
# .NET 8 Runtimes (Desktop + ASP.NET Core)
################################################################
Write-Host "Installing Microsoft .NET (moderne runtimes)..." -ForegroundColor Cyan

$NETCoreRuntime = "Microsoft.DotNet.Runtime.8"
$ASPNETCoreRuntime = "Microsoft.DotNet.AspNetCore.8"

Write-Verbose -Message "Installing .NET 8 Runtime ($NETCoreRuntime)..."
winget install --id $NETCoreRuntime --exact --accept-package-agreements --accept-source-agreements

Write-Verbose -Message "Installing ASP.NET Core 8 Runtime ($ASPNETCoreRuntime)..."
winget install --id $ASPNETCoreRuntime --exact --accept-package-agreements --accept-source-agreements

################################################################
# Visual C++ Redistributable 2015-2022 (x64 + x86) 
################################################################
Write-Host "Installing Microsoft C++ Redistributables..." -ForegroundColor Cyan

$VCRedistX64 = "Microsoft.VCRedist.2015+.x64"
$VCRedistX86 = "Microsoft.VCRedist.2015+.x86"

Write-Verbose -Message "Installing VC++ 2015-2022 x64 ($VCRedistX64)..."
winget install --id $VCRedistX64 --exact --accept-package-agreements --accept-source-agreements

Write-Verbose -Message "Installing VC++ 2015-2022 x86 ($VCRedistX86)..."
winget install --id $VCRedistX86 --exact --accept-package-agreements --accept-source-agreements

Write-Host "Finished installing baseline runtimes." -ForegroundColor Yellow

Stop-Transcript
