Write-Host "[+] Function Set-DefaultProfilePersonalPref"

function Set-DefaultProfilePersonalPref {
    $HiveFile = 'C:\Users\Default\NTUSER.DAT'
    $MountReg = 'HKLM\Default'       # voor reg.exe
    $MountPS  = 'HKLM:\Default'      # voor PowerShell provider

    if (!(Test-Path $HiveFile)) {
        throw "Default profile hive niet gevonden: $HiveFile"
    }

    # Als hij per ongeluk al gemount is: eerst unloaden
    if (Test-Path "$MountPS\Software") {
        reg unload $MountReg | Out-Null
        Start-Sleep -Milliseconds 300
    }

    # Mount de Default User hive
    reg load $MountReg $HiveFile | Out-Null

    try {
        # Zorg dat de paden bestaan
        $PathAdvanced = Join-Path $MountPS 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $PathSearch   = Join-Path $MountPS 'Software\Microsoft\Windows\CurrentVersion\Search'
        if (!(Test-Path $PathAdvanced)) { New-Item -Path $PathAdvanced -Force | Out-Null }
        if (!(Test-Path $PathSearch))   { New-Item -Path $PathSearch   -Force | Out-Null }

        # 1) Task View-knop verbergen
        New-ItemProperty -Path $PathAdvanced -Name 'ShowTaskViewButton' -PropertyType DWord -Value 0 -Force | Out-Null

        # 2) Widgets verbergen (Windows 11)
        New-ItemProperty -Path $PathAdvanced -Name 'TaskbarDa' -PropertyType DWord -Value 0 -Force | Out-Null

        # 3) Zoeken verbergen op de taakbalk
        #    0 = verborgen, 1 = pictogram, 2 = knop, 3 = zoekvak (afhankelijk van build)
        New-ItemProperty -Path $PathSearch -Name 'SearchboxTaskbarMode' -PropertyType DWord -Value 0 -Force | Out-Null

        Write-Host "[+] Default User taakbalkinstellingen toegepast."
    }
    finally {
        # Altijd unloaden, ook bij fouten
        reg unload $MountReg | Out-Null
    }
}
