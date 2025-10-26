$CapabilitiesToRemove = @(
    "OpenSSH.Client~~~~0.0.1.0",
    "XPS.Viewer~~~~0.0.1.0",
    "Microsoft.Windows.WordPad~~~~0.0.1.0"
)

foreach ($cap in $CapabilitiesToRemove) {
    Write-Host "Removing capability: $cap"
    Remove-WindowsCapability -Online -Name $cap
