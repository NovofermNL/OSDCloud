# Script nog in test!  
# Script voegt taken/scripts toe aan bestaande SetupComplete welke door OSDCloud wordt gegenereerd

##########################################################################################################################


##########################################################################################################################

Function Set-SetupCompleteCMTrace {
    $ScriptsPath = "$env:SystemRoot\Setup\Scripts"
    $PSFilePath  = Join-Path $ScriptsPath 'SetupComplete.ps1'

    if (!(Test-Path $ScriptsPath)) {
        New-Item -Path $ScriptsPath -ItemType Directory -Force | Out-Null
    }

    if (!(Test-Path $PSFilePath)) {
        'Write-Output "Start SetupComplete.ps1"' | Set-Content -Path $PSFilePath
    }

    Add-Content -Path $PSFilePath -Value 'Write-Output "Running CMTrace-Setup.ps1"'
    Add-Content -Path $PSFilePath -Value '& "$env:SystemRoot\Setup\Scripts\CMTrace-Setup.ps1"'
    Add-Content -Path $PSFilePath -Value 'Write-Output "Completed CMTrace-Setup.ps1"'
    Add-Content -Path $PSFilePath -Value 'Write-Output "-------------------------------------------------------------"'
}

##########################################################################################################################

Function Set-SetupCompleteCleanUp {
    $ScriptsPath = "$env:SystemRoot\Setup\Scripts"
    $PSFilePath  = Join-Path $ScriptsPath 'SetupComplete.ps1'

    if (!(Test-Path $ScriptsPath)) {
        New-Item -Path $ScriptsPath -ItemType Directory -Force | Out-Null
    }

    if (!(Test-Path $PSFilePath)) {
        'Write-Output "Start SetupComplete.ps1"' | Set-Content -Path $PSFilePath
    }

    Add-Content -Path $PSFilePath -Value 'Write-Output "Running Create-RunOnce-CleanUp.ps1"'
    Add-Content -Path $PSFilePath -Value '& "$env:SystemRoot\Setup\Scripts\Create-RunOnce-CleanUp.ps1"'
    Add-Content -Path $PSFilePath -Value 'Write-Output "Completed Create-RunOnce-CleanUp.ps1"'
    Add-Content -Path $PSFilePath -Value 'Write-Output "-------------------------------------------------------------"'
}
