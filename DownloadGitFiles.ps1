
# Doelmappen
$ScriptDir = 'C:\Temp\SetupTest\Scripts'
if (-not (Test-Path -LiteralPath $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
}

function Save-FromUrl {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Destination
    )
    $tmp = "$Destination.download"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        # Atomic move na succesvolle download
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
        Move-Item -LiteralPath $tmp -Destination $Destination
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        throw
    }
}

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" `
    (Join-Path $ScriptDir 'Remove-Appx.ps1')

Save-FromUrl "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" `
    (Join-Path $ScriptDir 'start2.bin')

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1" `
    (Join-Path $ScriptDir 'Copy-Start.ps1')

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" `
    (Join-Path $ScriptDir 'OSUpdate.ps1')

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" `
    (Join-Path $ScriptDir 'New-ComputerName.ps1')

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Deploy-RunOnceTask-OSUpdate.ps1" `
    (Join-Path $ScriptDir 'Deploy-RunOnceTask-OSUpdate.ps1')

Save-FromUrl "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Update-Firmware.ps1" `
    (Join-Path $ScriptDir 'Update-Firmware.ps1')
