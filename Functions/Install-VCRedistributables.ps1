# TLS 1.2 afdwingen (PS 5.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "[+] Function 'Install-VCRedistributables'"

function Install-VCRedistributables {
    <#
    .SYNOPSIS
    Installeert Microsoft Visual C++ Redistributables (2005 t/m 2022).

    .DESCRIPTION
    Installeert alle relevante Visual C++ Redistributables via Winget.
    Let op: het pakket "2015-2022" bevat 2015/2017/2019/2022 in één bundle.

    .EXAMPLE
    Install-VCRedistributables -Verbose
    #>

    [CmdletBinding()]
    param(
        [switch]$Include2005     = $true,
        [switch]$Include2008     = $true,
        [switch]$Include2010     = $true,
        [switch]$Include2012     = $true,
        [switch]$Include2013     = $true,
        [switch]$Include2015Plus = $true
    )

    # Controleer of winget beschikbaar is
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "Winget is niet gevonden. Installeer App Installer (Winget) en probeer opnieuw."
        return
    }

    $apps = @()

    if ($Include2005) {
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2005.x64"; Name = "VC++ 2005 x64" },
            @{ Id = "Microsoft.VCRedist.2005.x86"; Name = "VC++ 2005 x86" }
        )
    }
    if ($Include2008) {
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2008.x64"; Name = "VC++ 2008 x64" },
            @{ Id = "Microsoft.VCRedist.2008.x86"; Name = "VC++ 2008 x86" }
        )
    }
    if ($Include2010) {
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2010.x64"; Name = "VC++ 2010 x64" },
            @{ Id = "Microsoft.VCRedist.2010.x86"; Name = "VC++ 2010 x86" }
        )
    }
    if ($Include2012) {
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2012.x64"; Name = "VC++ 2012 x64" },
            @{ Id = "Microsoft.VCRedist.2012.x86"; Name = "VC++ 2012 x86" }
        )
    }
    if ($Include2013) {
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2013.x64"; Name = "VC++ 2013 x64" },
            @{ Id = "Microsoft.VCRedist.2013.x86"; Name = "VC++ 2013 x86" }
        )
    }
    if ($Include2015Plus) {
        # Gebruik ASCII/min-streepje i.p.v. en-dash om encoding-issues in PS 5.1 te voorkomen
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2015+.x64"; Name = "VC++ 2015-2022 x64" },
            @{ Id = "Microsoft.VCRedist.2015+.x86"; Name = "VC++ 2015-2022 x86" }
        )
    }

    foreach ($app in $apps) {
        Write-Host
        Write-Verbose "Installing $($app.Name)..." -Verbose
        try {
            winget install --id $($app.Id) --exact --accept-source-agreements --accept-package-agreements --force
        }
        catch {
            Write-Warning "Fout bij installatie van $($app.Name): $_"
        }
    }

    Write-Host
    Write-Output "Alle geselecteerde Microsoft Visual C++ Redistributables zijn geïnstalleerd."
}
