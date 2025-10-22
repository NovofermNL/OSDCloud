Write-Host "[+] Function Install-HPDrivers"

function Get-HPDrivers {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Make,
        [Parameter()]
        [string]$Model,
        [Parameter()]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,
        [Parameter()]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,
        [Parameter()]
        [string]$WindowsVersion
    )

    # --- Padopbouw & basisbestanden ---
    if (-not $script:DriversFolder -and -not $DriversFolder) {
        $DriversFolder = Join-Path $env:ProgramData 'Drivers'
    }
    $DriversPath = Join-Path $DriversFolder $Make

    $PlatformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
    $PlatformListCab = Join-Path $DriversPath 'platformList.cab'
    $PlatformListXml = Join-Path $DriversPath 'PlatformList.xml'

    if (-not (Test-Path -Path $DriversPath)) {
        WriteLog "Aanmaken downloadmap: $DriversPath"
        New-Item -Path $DriversPath -ItemType Directory -Force | Out-Null
        WriteLog "Downloadmap aangemaakt"
    }

    # --- Download & uitpakken PlatformList ---
    WriteLog "Downloaden $PlatformListUrl -> $PlatformListCab"
    Start-BitsTransferWithRetry -Source $PlatformListUrl -Destination $PlatformListCab
    WriteLog "Download gereed"

    WriteLog "Uitpakken $PlatformListCab -> $PlatformListXml"
    Invoke-Process -FilePath expand.exe -ArgumentList "`"$PlatformListCab`" `"$PlatformListXml`"" | Out-Null
    WriteLog "Uitpakken gereed"

    # --- Parse PlatformList om SystemID e.d. te bepalen ---
    [xml]$PlatformListContent = Get-Content -Path $PlatformListXml
    $ProductNodes = $PlatformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match $Model }

    $ProductNames = @()
    foreach ($node in $ProductNodes) {
        foreach ($productName in $node.ProductName) {
            if ($productName.'#text' -match $Model) {
                $ProductNames += [PSCustomObject]@{
                    ProductName = $productName.'#text'
                    SystemID    = $node.SystemID
                    OSReleaseID = $node.OS.OSReleaseIdFileName -replace 'H', 'h'
                    IsWindows11 = $node.OS.IsWindows11 -contains 'true'
                }
            }
        }
    }

    if ($ProductNames.Count -gt 1) {
        Write-Output "Meerdere modellen gevonden voor '$Model':"
        WriteLog     "Meerdere modellen gevonden voor '$Model':"
        $ProductNames | ForEach-Object -Begin { $i = 1 } -Process {
            if ($VerbosePreference -ne 'Continue') { Write-Output "$i. $($_.ProductName)" }
            WriteLog "$i. $($_.ProductName)"
            $i++
        }

        $selection = Read-Host "Selecteer het nummer van het juiste model"
        WriteLog "Gebruiker koos modelnummer: $selection"

        if ($selection -match '^\d+$' -and [int]$selection -le $ProductNames.Count) {
            $SelectedProduct = $ProductNames[[int]$selection - 1]
        }
        else {
            WriteLog "Ongeldige selectie. Stop."
            if ($VerbosePreference -ne 'Continue') { Write-Host "Ongeldige selectie. Stop." }
            return
        }
    }
    elseif ($ProductNames.Count -eq 1) {
        $SelectedProduct = $ProductNames[0]
    }
    else {
        WriteLog "Geen modellen gevonden voor '$Model'. Stop."
        if ($VerbosePreference -ne 'Continue') { Write-Host "Geen modellen gevonden voor '$Model'. Stop." }
        return
    }

    $ProductName = $SelectedProduct.ProductName
    $SystemID = $SelectedProduct.SystemID
    $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
    $IsWindows11 = $SelectedProduct.IsWindows11

    WriteLog "Geselecteerd model: $ProductName"
    WriteLog "SystemID: $SystemID"
    WriteLog "Geldige OSReleaseIDs: $ValidOSReleaseIDs"
    WriteLog "Ondersteunt Windows 11: $IsWindows11"

    if (-not $SystemID) {
        WriteLog "Geen SystemID gevonden voor model: $Model. Stop."
        if ($VerbosePreference -ne 'Continue') { Write-Host "Geen SystemID gevonden voor model: $Model. Stop." }
        return
    }

    # --- Validatie Windows-release ---
    if ($WindowsRelease -eq 11 -and -not $IsWindows11) {
        $msg = "WindowsRelease=11 maar er zijn geen drivers voor Windows 11. Zet -WindowsRelease op 10 of lever eigen drivers aan (FFUDevelopment\Drivers)."
        WriteLog $msg
        Write-Output $msg
        return
    }

    # --- Validatie WindowsVersion tegen OSReleaseID ---
    $OSReleaseIDs = $ValidOSReleaseIDs -split ' '
    $MatchingReleaseID = $OSReleaseIDs | Where-Object { $_ -eq "$WindowsVersion" }

    if (-not $MatchingReleaseID) {
        Write-Output "De opgegeven WindowsVersion '$WindowsVersion' is niet geldig voor dit model. Kies een geldige OSReleaseID:"
        $OSReleaseIDs | ForEach-Object -Begin { $i = 1 } -Process { Write-Output "$i. $_"; $i++ }

        $selection = Read-Host "Selecteer het nummer van de juiste OSReleaseID"
        WriteLog "Gebruiker koos OSReleaseID nummer: $selection"

        if ($selection -match '^\d+$' -and [int]$selection -le $OSReleaseIDs.Count) {
            $WindowsVersion = $OSReleaseIDs[[int]$selection - 1]
            WriteLog "Gekozen OSReleaseID: $WindowsVersion"
        }
        else {
            WriteLog "Ongeldige selectie. Stop."
            return
        }
    }

    # --- Opbouw download-URL voor model-driverlijst ---
    $Arch = $WindowsArch -replace '^x', ''
    $WindowsVersionHP = $WindowsVersion -replace 'H', 'h'
    $ModelRelease = "${SystemID}_${Arch}_${WindowsRelease}.0.$WindowsVersionHP"

    $DriverCabUrl = "https://hpia.hpcloud.hp.com/ref/$SystemID/$ModelRelease.cab"
    $DriverCabFile = Join-Path $DriversPath "$ModelRelease.cab"
    $DriverXmlFile = Join-Path $DriversPath "$ModelRelease.xml"

    if (-not (Test-Url -Url $DriverCabUrl)) {
        WriteLog "HP Driver CAB URL onbereikbaar: $DriverCabUrl. Stop."
        if ($VerbosePreference -ne 'Continue') { Write-Host "HP Driver CAB URL onbereikbaar: $DriverCabUrl. Stop." }
        return
    }

    # --- Download & uitpakken model-driverlijst ---
    WriteLog "Downloaden HP Driver CAB: $DriverCabUrl -> $DriverCabFile"
    Start-BitsTransferWithRetry -Source $DriverCabUrl -Destination $DriverCabFile

    WriteLog "Uitpakken CAB -> $DriverXmlFile"
    Invoke-Process -FilePath expand.exe -ArgumentList "`"$DriverCabFile`" `"$DriverXmlFile`"" | Out-Null

    # --- Parse driver-XML en download/extract per driver ---
    [xml]$DriverXmlContent = Get-Content -Path $DriverXmlFile

    WriteLog "Drivers downloaden voor $ProductName"
    foreach ($update in $DriverXmlContent.ImagePal.Solutions.UpdateInfo) {
        if ($update.Category -notmatch '^Driver') { continue }

        $Name = ($update.Name -replace '[\\\/\:\*\?\"\<\>\|]', '_')
        $Category = ($update.Category -replace '[\\\/\:\*\?\"\<\>\|]', '_')
        $Version = ($update.Version -replace '[\\\/\:\*\?\"\<\>\|]', '_')

        $rawUrl = [string]$update.URL
        if ($rawUrl -match '^(https?|ftp)://') {
            if ($rawUrl -like 'ftp://*') {
                $DriverUrl = $rawUrl -replace '^ftp://', 'https://'
            }
            else {
                $DriverUrl = $rawUrl
            }
        }
        else {
            $DriverUrl = 'https://' + $rawUrl.TrimStart('/')
        }

        WriteLog "Driver: $Name"
        WriteLog "Categorie: $Category"
        WriteLog "Versie: $Version"
        WriteLog "URL: $DriverUrl"

        $DriverFileName = [IO.Path]::GetFileName($DriverUrl)
        $downloadFolder = Join-Path (Join-Path $DriversPath $ProductName) $Category
        $DriverFilePath = Join-Path $downloadFolder $DriverFileName

        if (Test-Path -Path $DriverFilePath) {
            WriteLog "Driver al aanwezig, overslaan: $DriverFilePath"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Aanmaken downloadmap: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Downloadmap aangemaakt"
        }

        WriteLog "Download naar: $DriverFilePath"
        Start-BitsTransferWithRetry -Source $DriverUrl -Destination $DriverFilePath
        WriteLog "Download gereed"

        $exeBaseName = [IO.Path]::GetFileNameWithoutExtension($DriverFileName)
        $extractFolder = Join-Path (Join-Path (Join-Path $downloadFolder $Name) $Version) $exeBaseName

        WriteLog "Aanmaken extractiemap: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog "Extractiemap aangemaakt"

        $arguments = "/s /e /f `"$extractFolder`""
        WriteLog "Uitpakken driver"
        Invoke-Process -FilePath $DriverFilePath -ArgumentList $arguments | Out-Null
        WriteLog "Uitpakken gereed: $extractFolder"

        Remove-Item -Path $DriverFilePath -Force
        WriteLog "Installer verwijderd: $DriverFilePath"
    }

    Remove-Item -Path $DriverCabFile, $DriverXmlFile, $PlatformListCab, $PlatformListXml -Force -ErrorAction SilentlyContinue
    WriteLog "Tijdelijke CAB/XML bestanden verwijderd"
}
