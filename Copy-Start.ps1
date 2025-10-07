Write-Host -ForegroundColor Green "Kopiëren van start2.bin"

$source = "C:\Windows\Setup\scripts\start2.bin"
$destination = "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\"

# Zorg dat de doelmap bestaat
if (-not (Test-Path -Path $destination)) {
    New-Item -Path $destination -ItemType Directory -Force
}

# Kopieer het bestand
Copy-Item -Path $source -Destination $destination -Force
