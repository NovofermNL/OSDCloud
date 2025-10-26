# =========================
# Baseline Runtimes Install
# =========================

# Loggen
$OSSoftLogs = "C:\Logs\OSDCloud\Install\SYSTEM\$env:COMPUTERNAME-OSSoftware.log"
New-Item -ItemType Directory -Path (Split-Path $OSSoftLogs) -Force | Out-Null
Start-Transcript -Path $OSSoftLogs

# TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#####################################################################
#########                 SOFTWARE VARIABLES
#####################################################################

$SYSGroup1 = "Microsoft .NET Framework"
$SYSGroup2 = "Microsoft .NET (moderne runtimes)"
$SYSGroup3 = "Microsoft C++ Redistributables"

$NETCoreRuntime   = "Microsoft.DotNet.Runtime.8"
$ASPNETCoreRuntime= "Microsoft.DotNet.AspNetCore.8"

$VCRedistX64 = "Microsoft.VCRedist.2015+.x64"
$VCRedistX86 = "Microsoft.VCRedist.2015+.x86"

################################################################
# Package Manager
################################################################

Write-Host "Installing Chocolatey (nodig voor .NET Framework)..." -ForegroundColor Cyan
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

################################################################
# .NET Framework (4.8/4.8.1)
################################################################
Write-Host "Installing $SYSGroup1..." -ForegroundColor Cyan
Write-Verbose "Installing .NET Framework (dotnetfx)..." -Verbose
choco install dotnetfx -y --no-progress

################################################################
# .NET 8 Runtimes (Desktop + ASP.NET Core)
################################################################
Write-Host "Installing $SYSGroup2..." -ForegroundColor Cyan

Write-Verbose "Installing .NET 8 Runtime ($NETCoreRuntime)..." -Verbose
winget install --id $NETCoreRuntime --exact --accept-package-agreements --accept-source-agreements --force

Write-Verbose "Installing ASP.NET Core 8 Runtime ($ASPNETCoreRuntime)..." -Verbose
winget install --id $ASPNETCoreRuntime --exact --accept-package-agreements --accept-source-agreements --force

################################################################
# Visual C++ Redistributable 2015–2022 (x64 + x86)
################################################################
Write-Host "Installing $SYSGroup3..." -ForegroundColor Cyan

Write-Verbose "Installing VC++ 2015–2022 x64 ($VCRedistX64)..." -Verbose
winget install --id $VCRedistX64 --exact --accept-package-agreements --accept-source-agreements --force

Write-Verbose "Installing VC++ 2015–2022 x86 ($VCRedistX86)..." -Verbose
winget install --id $VCRedistX86 --exact --accept-package-agreements --accept-source-agreements --force

Write-Host "Finished installing baseline runtimes." -ForegroundColor Yellow

Stop-Transcript
