Write-Host "[+] Function Set-UserProfilePersonalPref"

function Set-UserProfilePersonalPref {
    # Pad naar HKCU
    $MountPS = 'HKCU:\' 

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
    New-ItemProperty -Path $PathSearch -Name 'SearchboxTaskbarMode' -PropertyType DWord -Value 0 -Force | Out-Null

    Write-Host "[+] Gebruikersspecifieke taakbalkinstellingen toegepast."
}
