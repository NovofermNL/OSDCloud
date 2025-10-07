function Set-TrustedPSGallery {
    <#
    Scriptnaam: Set-TrustedPSGallery
    Beschrijving: Controleert of de PSGallery repository op Trusted staat. 
                  Zo niet, dan wordt de NuGet provider geïnstalleerd en de repository op Trusted gezet.
    #>

    [CmdletBinding()]
    param()

    # Zorg dat TLS 1.2 wordt gebruikt
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
        Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
        Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
        Write-Output "PSGallery repository is nu ingesteld als Trusted."
    }
    else {
        Write-Output "PSGallery repository is al Trusted."
    }
}
