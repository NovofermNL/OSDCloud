Write-Host "[+] Function Install-VCRedistributables"

function Install-VCRedistributables {
    <#
    .SYNOPSIS
    Installeert alle Visual C++ Redistributables (2005 t/m 2015+).

    .DESCRIPTION
    Deze functie installeert alle gangbare Microsoft Visual C++ Redistributables 
    via Winget (en Chocolatey voor 2017). 
    De functie accepteert optioneel parameters voor logging of specifieke jaren.

    .PARAMETER Include2005
    Installeert de 2005 Redistributables.

    .PARAMETER Include2008
    Installeert de 2008 Redistributables.

    .PARAMETER Include2010
    Installeert de 2010 Redistributables.

    .PARAMETER Include2012
    Installeert de 2012 Redistributables.

    .PARAMETER Include2013
    Installeert de 2013 Redistributables.

    .PARAMETER Include2015Plus
    Installeert de 2015-2022 Redistributables.

    .PARAMETER Include2017
    Installeert de 2017 Redistributables via Chocolatey.

    .EXAMPLE
    Install-VCRedistributables
    # Installeert alle redistributables (2005–2017).
    #>

    [CmdletBinding()]
    param(
        [switch]$Include2005 = $true,
        [switch]$Include2008 = $true,
        [switch]$Include2010 = $true,
        [switch]$Include2012 = $true,
        [switch]$Include2013 = $true,
        [switch]$Include2015Plus = $true,
        [switch]$Include2017 = $true
    )

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
        $apps += @(
            @{ Id = "Microsoft.VCRedist.2015+.x64"; Name = "VC++ 2015–2022 x64" },
            @{ Id = "Microsoft.VCRedist.2015+.x86"; Name = "VC++ 2015–2022 x86" }
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

    if ($Include2017) {
        Write-Host
        Write-Verbose "Installing VC++ 2017 (via Chocolatey)..." -Verbose
        try {
            choco install vcredist2017 -y
        }
        catch {
            Write-Warning "Fout bij installatie van VC++ 2017: $_"
        }
    }

    Write-Host
    Write-Output "Alle geselecteerde Visual C++ Redistributables zijn geïnstalleerd."
}
