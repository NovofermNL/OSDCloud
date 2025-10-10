function Enable-HyperV {
    <#
    .SYNOPSIS
        Controleert of Hyper-V en de GUI-tools zijn ingeschakeld en schakelt ze in indien nodig.

    .DESCRIPTION
        Deze functie controleert of de Windows-onderdelen 'Microsoft-Hyper-V-Hypervisor' 
        en 'Microsoft-Hyper-V-Management-Clients' actief zijn. 
        Indien uitgeschakeld, worden ze ingeschakeld zonder herstart.

    .EXAMPLE
        Enable-HyperV
    #>

    # Controleer Hyper-V hypervisor
    $hyperVState = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Hypervisor).State
    if ($hyperVState -eq "Disabled") {
        Write-Host "Hyper-V wordt ingeschakeld..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
    }
    else {
        Write-Host "Hyper-V is al geïnstalleerd."
    }

    # Controleer Hyper-V Management GUI
    $guiState = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients).State
    if ($guiState -eq "Disabled") {
        Write-Host "Hyper-V Management GUI wordt ingeschakeld..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients -All -NoRestart
    }
    else {
        Write-Host "Hyper-V Management GUI is al geïnstalleerd."
    }
}
