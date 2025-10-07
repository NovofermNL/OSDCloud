$RemoveAppx = @(
    "Clipchamp.Clipchamp"
    "Microsoft.BingNews"
    "Microsoft.BingSearch"
    "Microsoft.BingWeather"
    "Microsoft.GamingApp"
    "Microsoft.GetHelp"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.OutlookForWindows"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.Todos"
    "Microsoft.Windows.DevHome"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.WindowsTerminal"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.YourPhone"
    "Microsoft.ZuneMusic"
)

foreach ($App in $RemoveAppx) {
    Write-Host "`n--- Controleren op geïnstalleerde app: $App ---"

    # Verwijder AppxPackage
    $Installed = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$App*" }
    if ($Installed) {
        foreach ($pkg in $Installed) {
            Write-Host "Verwijderen Appx-package: $($pkg.PackageFullName)"
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Host "Verwijderd: $($pkg.PackageFullName)"
            } catch {
                Write-Warning "Fout bij verwijderen Appx-package: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "Niet gevonden als AppxPackage."
    }

    # Verwijder Provisioned Package (voor nieuwe gebruikers)
    $Provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $App }
    if ($Provisioned) {
        foreach ($prov in $Provisioned) {
            Write-Host "Verwijderen provisioned package: $($prov.PackageName)"
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Host "Verwijderd uit image: $($prov.PackageName)"
            } catch {
                Write-Warning "Fout bij verwijderen provisioned package: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "Niet gevonden als ProvisionedPackage."
    }
}
