[CmdletBinding()]
param(
    # Naam van de Office-configuratie XML die we lokaal genereren
    [string]$ConfigXmlName = 'SingleUser.xml',

    # Werkmap waar ODT + Office-bestanden komen
    [string]$WorkFolder = "$PSScriptRoot\ODT"
)

# TLS 1.2 afdwingen
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = 'Stop'

function Get-ODTDownloadUrl {
    Write-Host "Ophalen van Microsoft Download pagina voor ODT..."

    $url = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    $regex = '"url":"(https://download\.microsoft\.com/download/[^"]+\.exe)"'

    if ($response.Content -match $regex) {
        $downloadUrl = $matches[1] -replace '\\/', '/'
        Write-Host "Gevonden ODT download URL:"
        Write_Host "  $downloadUrl"
        return $downloadUrl
    }
    else {
        throw "ODT download-URL niet gevonden op de Microsoft-pagina."
    }
}

# NIEUWE FUNCTIE: Past een registerwaarde toe op ALLE actief ingelogde gebruikers (via HKEY_USERS)
function Set-UserRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeKeyPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)]$Value
    )

    # Haalt de SIDs van alle actieve console-gebruikers op (exclusief Systeemaccounts)
    $ActiveUsers = Get-CimInstance -ClassName Win32_LogonSession | 
    Where-Object { $_.LogonType -eq 2 } | # LogonType 2 = Interactive (UI)
    ForEach-Object { Get-CimInstance -ClassName Win32_LoggedOnUser -Filter "Dependent -like '$($_.Path.RelativePath)'" } | 
    Select-Object -ExpandProperty Antecedent | 
    ForEach-Object { 
        $_.SID -replace '^.*SID="([^"]+)".*$', '$1'
    } | Select-Object -Unique

    if (-not $ActiveUsers) {
        Write-Host "  > Geen actief ingelogde gebruikers gevonden. Registerwijziging overgeslagen."
        return
    }

    Write-Host "  > Toepassen op $($ActiveUsers.Count) actieve gebruiker(s): $RelativeKeyPath - $Name..."

    foreach ($SID in $ActiveUsers) {
        # Constructie van het volledige pad onder HKEY_USERS
        $FullRegistryPath = "Registry::HKEY_USERS\$SID\$RelativeKeyPath"
        
        # Pad aanmaken indien nodig
        if (-not (Test-Path -Path $FullRegistryPath)) {
            New-Item -Path $FullRegistryPath -Force | Out-Null
        }
        
        # Instellen van de registerwaarde
        # Gebruik New-ItemProperty als de waarde nog niet bestaat
        if (-not (Get-ItemProperty -Path $FullRegistryPath -Name $Name -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $FullRegistryPath -Name $Name -Type $Type -Value $Value -Force | Out-Null
        }
        else {
            Set-ItemProperty -Path $FullRegistryPath -Name $Name -Type $Type -Value $Value -Force | Out-Null
        }
    }
}


try {
    # Werkmap voorbereiden
    if (-not (Test-Path -Path $WorkFolder)) {
        New-Item -Path $WorkFolder -ItemType Directory -Force | Out-Null
    }

    # Download ODT
    $odtUrl = Get-ODTDownloadUrl
    $odtSetupExe = Join-Path $WorkFolder 'ODTSetup.exe'

    Write-Host "Downloaden van ODT naar: $odtSetupExe"
    Invoke-WebRequest -Uri $odtUrl -OutFile $odtSetupExe

    if (-not (Test-Path -Path $odtSetupExe)) {
        throw "ODTSetup.exe is niet gevonden na download."
    }

    # ODT uitpakken
    Write-Host "Uitpakken van ODT in: $WorkFolder"
    $extractArgs = "/quiet /extract:`"$WorkFolder`""
    $proc = Start-Process -FilePath $odtSetupExe -ArgumentList $extractArgs -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "ODT installatiebestand kon niet worden uitgepakt. ExitCode: $($proc.ExitCode)"
    }

    # Controleren of setup.exe bestaat
    $setupExe = Join-Path $WorkFolder 'setup.exe'
    if (-not (Test-Path -Path $setupExe)) {
        throw "setup.exe van ODT is niet gevonden in $WorkFolder."
    }

    # XML Configuratie lokaal genereren en opslaan
    $configXmlPath = Join-Path $WorkFolder $ConfigXmlName

    Write-Host "Genereren en opslaan van configuratie XML: $ConfigXmlName"

    $xmlContent = @"
<Configuration ID="f689756d-2e60-4ffa-a20e-d52a843b3834">
    <Info Description="Single User Configuratie" />
    <Add OfficeClientEdition="32" Channel="MonthlyEnterprise">
        <Product ID="O365ProPlusRetail">
            <Language ID="nl-nl" />
            <ExcludeApp ID="Groove" />
            <ExcludeApp ID="Lync" />
            <ExcludeApp ID="OutlookForWindows" />
            <ExcludeApp ID="Publisher" />
            <ExcludeApp ID="Teams" />
        </Product>
        <Product ID="AccessRuntimeRetail">
            <Language ID="nl-nl" />
            <Language ID="en-us" />
        </Product>
    </Add>
    <Property Name="SharedComputerLicensing" Value="0" />
    <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
    <Property Name="DeviceBasedLicensing" Value="0" />
    <Property Name="SCLCacheOverride" Value="0" />
    <Property Name="PinIconsToTaskbar" Value="TRUE" />
    <Updates Enabled="TRUE" />
    <RemoveMSI />
    <AppSettings>
        <Setup Name="Company" Value="Novoferm Nederland BV" />
    </AppSettings>
    <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@

    # XML naar het bestand schrijven
    $xmlContent | Out-File $configXmlPath -Encoding UTF8 -Force

    # 6. Office-bestanden downloaden
    Write-Host "Downloaden van Office-bestanden met XML: $ConfigXmlName"
    $downloadArgs = "/download `"$configXmlPath`""
    $proc = Start-Process -FilePath $setupExe -ArgumentList $downloadArgs -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Download van Office-bestanden is mislukt. ExitCode: $($proc.ExitCode)"
    }

    # 7. Office installeren
    Write-Host "Installeren van Office met XML: $ConfigXmlName"
    $configureArgs = "/configure `"$configXmlPath`""
    $proc = Start-Process -FilePath $setupExe -ArgumentList $configureArgs -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Installatie van Office is mislukt. ExitCode: $($proc.ExitCode)"
    }

    Write-Host "Office installatie is succesvol afgerond."

    # Instellen van Office First Run, privacy-opties en standaard bestandsformaten
    Write-Host "Instellen van Office First Run suppressie, bestandsformaten en andere opties in het register (voor actieve gebruikers)..."

    # Basispad voor Office onder de gebruikersprofielen
    $OfficeUserPath = "Software\Microsoft\Office\16.0"

    # --- Registry Keys Conversie (Nu via Set-UserRegistryValue) ---

    #  Word Options: DisableBootToOfficeStart
    # HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Word\Options - DisableBootToOfficeStart=dword:00000001
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Word\Options" -Name "DisableBootToOfficeStart" -Type DWord -Value 1
    
    #  Privacy Settings: OptionalConnectedExperiencesNoticeVersion
    # HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Common\Privacy\SettingsStore\Anonymous - OptionalConnectedExperiencesNoticeVersion=dword:00000002
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\Privacy\SettingsStore\Anonymous" -Name "OptionalConnectedExperiencesNoticeVersion" -Type DWord -Value 2
    
    #  Registration: AcceptAllEulas (EULA automatisch accepteren)
    # HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Registration - AcceptAllEulas=dword:00000001
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Registration" -Name "AcceptAllEulas" -Type DWord -Value 1
    
    #  Common General Settings (First Run Suppressie/File Format Prompts)
    # HKEY_CURRENT_USER\SOFTWARE\Microsoft\Office\16.0\Common\General
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "FirstRunTime" -Type DWord -Value 0x019975fb
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "FileFormatBallotBoxAppIDBootedOnce" -Type DWord -Value 0
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "FileFormatBallotBoxTelemetryEventSent" -Type DWord -Value 1
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "ShownFileFmtPrompt" -Type DWord -Value 1
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "FileFormatBallotBoxShowAttempts" -Type DWord -Value 1
    
    #  Common General Settings (Skip Open and Save As Place)
    # HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Common\General - SkipOpenAndSaveAsPlace=dword:00000001
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\Common\General" -Name "SkipOpenAndSaveAsPlace" -Type DWord -Value 1

    #  Excel Default Format (51 = .xlsx)
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\excel\options" -Name "defaultformat" -Type DWord -Value 51

    #  PowerPoint Default Format (27 = .pptx)
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\powerpoint\options" -Name "defaultformat" -Type DWord -Value 27

    #  Word Default Format (Leeg = .docx)
    Set-UserRegistryValue -RelativeKeyPath "$OfficeUserPath\word\options" -Name "defaultformat" -Type String -Value ""
    
    # Outlook Policy (ZeroConfigExchangeOnce) - Dit gaat via de Policies-tak.
    # HKCU\SOFTWARE\Policies\Microsoft\office\16.0\Outlook\AutoDiscover /v ZeroConfigExchangeOnce /t REG_DWORD /d 1
    $OutlookPolicyUserPath = "SOFTWARE\Policies\Microsoft\office\16.0\Outlook\AutoDiscover"
    Set-UserRegistryValue -RelativeKeyPath $OutlookPolicyUserPath -Name "ZeroConfigExchangeOnce" -Type DWord -Value 1

    Write-Host "Alle registerinstellingen zijn toegepast op actief ingelogde gebruikers."
    
    # Succesvolle Exit Code voor Intune
    Exit 0

}
catch {
    Write-Host "Fout tijdens installatie/configuratie: $($_.Exception.Message)"
    Exit 1
}
