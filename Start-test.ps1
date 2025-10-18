$ScriptName = 'Installeren Windows 11'
$ScriptVersion = '24.7.4.4'
Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"

#=======================================================================
#   OSDCLOUD Definitions
#=======================================================================
$OSName = 'Windows 11 24H2 x64'
$OSEdition = 'Pro'
$OSActivation = 'Volume'
$OSLanguage = 'nl-nl'

#=======================================================================
#   OSDCLOUD VARS (defaults)
#=======================================================================
$Global:MyOSDCloud = [ordered]@{
    Restart               = [bool]$false
    RecoveryPartition     = [bool]$false
    OEMActivation         = [bool]$true
    WindowsUpdate         = [bool]$false
    MSCatalogFirmware     = [bool]$false
    WindowsUpdateDrivers  = [bool]$false
    WindowsDefenderUpdate = [bool]$false
    SetTimeZone           = [bool]$true
    SkipClearDisk         = [bool]$false
    ClearDiskConfirm      = [bool]$false
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$true
    ZTI                   = [bool]$false
}

#=======================================================================
#   HP / HPIA / BIOS/TPM integratie (Hyper-V safe, ZTI-proof)
#=======================================================================
$HPTPM = $false; $HPBIOS = $false; $HPIADrivers = $false; $HPEnterprise = $false

# VM-detectie
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$sp = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
$Manufacturer = $cs.Manufacturer
$Model = $cs.Model
$vendor = $sp.Vendor
$product = $sp.Name
$IsVM = ($Manufacturer -match 'Microsoft Corporation' -and $Model -match 'Virtual Machine') -or
        ($vendor -match 'Microsoft Corporation' -and $product -match 'Virtual Machine')

# Internet check
$InternetConnection = $false
try {
    $resp = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($resp.StatusCode -eq 200 -and $resp.Content -match 'Microsoft') { $InternetConnection = $true }
}
catch { $InternetConnection = $false }

# OSDCloud functions (best-effort)
$FunctionsLoaded = $false
if ($InternetConnection -and -not $IsVM) {
    try {
        Invoke-Expression -Command (Invoke-RestMethod -Uri 'https://functions.osdcloud.com')
        $FunctionsLoaded = $true
    }
    catch { Write-Warning "OSDCloud functions niet geladen: $($_.Exception.Message)" }
}

# HP enterprise check
$HasTestHPIA = ($null -ne (Get-Command Test-HPIASupport -ErrorAction SilentlyContinue))
if (-not $IsVM -and $InternetConnection -and $FunctionsLoaded -and $HasTestHPIA -and ($Manufacturer -match 'HP|Hewlett-Packard')) {
    try { $HPEnterprise = Test-HPIASupport } catch { Write-Warning "Test-HPIASupport faalde: $($_.Exception.Message)"; $HPEnterprise = $false }
}

# HP enterprise flow
if ($HPEnterprise) {
    try {
        Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1')
        if (-not (Get-Command osdcloud-InstallModuleHPCMSL -ErrorAction SilentlyContinue)) { throw "osdcloud-InstallModuleHPCMSL niet beschikbaar." }
        osdcloud-InstallModuleHPCMSL
        if (-not (Get-Command osdcloud-HPTPMDetermine -ErrorAction SilentlyContinue)) { throw "osdcloud-HPTPMDetermine niet beschikbaar." }
        if (-not (Get-Command osdcloud-HPBIOSDetermine -ErrorAction SilentlyContinue)) { throw "osdcloud-HPBIOSDetermine niet beschikbaar." }

        $TPM = osdcloud-HPTPMDetermine
        $BIOS = osdcloud-HPBIOSDetermine
        $HPIADrivers = $true

        if ($TPM) { Write-Host "HP TPM firmware update vereist: $TPM" -ForegroundColor Yellow; $HPTPM = $true }
        if ($BIOS -eq $false) {
            if (Get-Command Get-HPBIOSVersion -ErrorAction SilentlyContinue) {
                $CurrentVer = Get-HPBIOSVersion
                Write-Host "HP System Firmware up-to-date: $CurrentVer" -ForegroundColor Green
            }
            else { Write-Host "HP System Firmware up-to-date" -ForegroundColor Green }
        }
        else {
            if (Get-Command Get-HPBIOSUpdates -ErrorAction SilentlyContinue) {
                $LatestVer = (Get-HPBIOSUpdates -Latest).ver
                $CurrentVer = (Get-HPBIOSVersion)
                Write-Host "HP System Firmware update: $CurrentVer -> $LatestVer" -ForegroundColor Yellow
            }
            else { Write-Host "HP System Firmware update nodig" -ForegroundColor Yellow }
            $HPBIOS = $true
        }
    }
    catch {
        Write-Warning "HP Enterprise flow overgeslagen door fout: $($_.Exception.Message)"
        $HPIADrivers = $false; $HPTPM = $false; $HPBIOS = $false
    }
}
else {
    if ($IsVM) { Write-Host "VM gedetecteerd (Hyper-V). HP/HPIA overgeslagen." -ForegroundColor DarkYellow }
    elseif (-not $InternetConnection) { Write-Host "Geen internet in WinPE; HP/HPIA overgeslagen." -ForegroundColor DarkYellow }
    elseif (-not $FunctionsLoaded) { Write-Host "OSDCloud functions niet geladen; HP/HPIA overgeslagen." -ForegroundColor DarkYellow }
    elseif (-not $HasTestHPIA) { Write-Host "Test-HPIASupport niet beschikbaar; HP/HPIA overgeslagen." -ForegroundColor DarkYellow }
    elseif ($Manufacturer -notmatch 'HP|Hewlett-Packard') { Write-Host "Geen HP hardware; HP/HPIA overgeslagen." -ForegroundColor DarkYellow }
}

# HP-flags terugzetten
$Global:MyOSDCloud.HPIADrivers = [bool]$HPIADrivers
$Global:MyOSDCloud.HPTPMUpdate = [bool]$HPTPM
$Global:MyOSDCloud.HPBIOSUpdate = [bool]$HPBIOS
Write-Host "HP/HPIA summary -> VM:$IsVM Internet:$InternetConnection HPIA:$HPIADrivers TPM:$HPTPM BIOS:$HPBIOS" -ForegroundColor Cyan

#=======================================================================
#   LOCAL DRIVE LETTERS (CIM)
#=======================================================================
function Get-WinPEDrive {
    $d = (Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object VolumeName -eq 'WINPE').DeviceID
    Write-Host "Current WINPE drive is: $d"
    return $d
}
function Get-OSDCloudDrive {
    $d = (Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object VolumeName -eq 'OSDCloudUSB').DeviceID
    Write-Host "Current OSDCLOUD Drive is: $d"
    return $d
}

#=======================================================================
#   OSDCLOUD Image met keuzemenu (ZTI-proof)
#=======================================================================
$uselocalimage = $true
$OSDCloudDrive = Get-OSDCloudDrive
$ImageFileItem = $null   # init voor nette linting/analyzers

Write-Host -ForegroundColor Green "UseLocalImage is set to: $uselocalimage"
if (-not $OSDCloudDrive) { Write-Warning "OSDCloudUSB niet gevonden; online image."; $uselocalimage = $false }

if ($uselocalimage) {
    $wimRoot = Join-Path $OSDCloudDrive 'OSDCloud\OS'
    $wimFiles = Get-ChildItem -Path $wimRoot -Filter "*.wim" -Recurse -File -ErrorAction SilentlyContinue

    if (-not $wimFiles -or $wimFiles.Count -eq 0) {
        Write-Warning "Geen WIM-bestanden in $wimRoot"
        $uselocalimage = $false
    }
    else {
        if ($Global:MyOSDCloud.ZTI) {
            $ImageFileItem = $wimFiles | Select-Object -First 1
        }
        else {
            $i = 1
            $wimFiles | ForEach-Object {
                Write-Host ("{0}. {1}" -f $i, $_.FullName) -ForegroundColor Yellow
                $i++
            }
            $selectionRaw = Read-Host "`nTyp het nummer (1-$($wimFiles.Count))"
            $selection = [int]$selectionRaw
            if ($selection -ge 1 -and $selection -le $wimFiles.Count) {
                $ImageFileItem = $wimFiles[$selection - 1]
            }
            else {
                Write-Warning "Ongeldige selectie; online image."
                $uselocalimage = $false
            }
        }

        if ($ImageFileItem) {
            $Global:MyOSDCloud.ImageFileItem = $ImageFileItem
            $Global:MyOSDCloud.ImageFileName = $ImageFileItem.Name
            $Global:MyOSDCloud.ImageFileFullName = $ImageFileItem.FullName

            $imgInfo = Get-WindowsImage -ImagePath $ImageFileItem.FullName -ErrorAction SilentlyContinue
            if ($imgInfo) {
                $match = $imgInfo | Where-Object { $_.ImageName -match $OSEdition } | Select-Object -First 1
                $Global:MyOSDCloud.OSImageIndex = if ($match) { $match.ImageIndex } else { 1 }
            }
            else {
                $Global:MyOSDCloud.OSImageIndex = 1
            }

            Write-Host "`nWIM-bestand gekozen: $($ImageFileItem.Name) [Index $($Global:MyOSDCloud.OSImageIndex)]" -ForegroundColor Green
        }
    }
}
#=======================================================================
#   Update OSDCloud modules (pak hoogste versie)
#=======================================================================
$moduleRoot = Join-Path $Env:ProgramFiles 'WindowsPowerShell\Modules\OSD'
$ModulePath = Get-ChildItem -Path $moduleRoot -Directory -ErrorAction SilentlyContinue |
Sort-Object { [version]($_.Name) } -Descending |
Select-Object -First 1 -ExpandProperty FullName
if (-not $ModulePath) { throw "OSD module niet gevonden in $moduleRoot" }
Import-Module (Join-Path $ModulePath 'OSD.psd1') -Force

#=======================================================================
#   Start OSDCloud (géén auto-reboot) — staging komt erna
#=======================================================================
$Global:MyOSDCloud.Restart = $false   # belangrijk: wij rebooten zelf als laatste
Write-Host "Starting OSDCloud" -ForegroundColor Green
if ($uselocalimage -and $Global:MyOSDCloud.ImageFileFullName) {
    Write-Host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage -ImageFileFullName $($Global:MyOSDCloud.ImageFileFullName) -OSImageIndex $($Global:MyOSDCloud.OSImageIndex)"
    Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage `
        -ImageFileFullName $Global:MyOSDCloud.ImageFileFullName -OSImageIndex $Global:MyOSDCloud.OSImageIndex
}
else {
    Write-Host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"
    Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage
}

Write-Host -ForegroundColor Green "OS toegepast. Staging SetupComplete/oobe op doel-OS..."

#=======================================================================
#   NA imaging: stage OOBE + SetupComplete op DOEL-OS
#=======================================================================
function Get-TargetWindowsDrive {
    foreach ($dl in 'C'..'Z') {
        if (Test-Path "$dl`:\Windows\System32" -ErrorAction SilentlyContinue) { return $dl }
    }
    return $null
}
$Target = Get-TargetWindowsDrive
if (-not $Target) { throw "Doel-OS partitie niet gevonden." }

$ScriptPath = "$Target`:\Windows\Setup\Scripts"
New-Item -ItemType Directory -Path $ScriptPath -Force | Out-Null

# Bestanden downloaden naar DOEL-OS (let op case: SetupCompleteFiles)
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Remove-Appx.ps1" | Out-File -FilePath "$ScriptPath\Remove-AppX.ps1" -Encoding ascii -Force
Invoke-WebRequest -Uri "https://github.com/NovofermNL/OSDCloud/raw/main/Files/start2.bin" -OutFile "$ScriptPath\start2.bin"
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Copy-Start.ps1"c | Out-File -FilePath "$ScriptPath\Copy-Start.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/OSUpdate.ps1" | Out-File -FilePath "$ScriptPath\OSUpdate.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/New-ComputerName.ps1" | Out-File -FilePath "$ScriptPath\New-ComputerName.ps1" -Encoding ascii -Force
Invoke-RestMethod "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/SetupCompleteFiles/Create-OSUpdateTask.ps1" | Out-File -FilePath "$ScriptPath\Create-OSUpdateTask.ps1" -Encoding ascii -Force

# oobe.cmd (overwriting is prima)
@'
@echo off
:: OOBE fase verwijder standaard apps en wijzig start-menu
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File %WINDIR%\Setup\Scripts\Remove-AppX.ps1
::start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File %WINDIR%\Setup\Scripts\Copy-Start.ps1
'@ | Out-File -FilePath "$ScriptPath\oobe.cmd" -Encoding ascii -Force

# SetupComplete: append als die al bestaat, anders nieuw maken
$SetupCompletePath = "$ScriptPath\SetupComplete.cmd"
$SetupBlock = @'
:: === Begin custom block ===
for /f %%a in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyy-MM-dd-HHmmss')"') do set logname=%%a-Cleanup-Script.log
set logfolder=%ProgramData%\Microsoft\IntuneManagementExtension\Logs\OSD
set logfile=%logfolder%\%logname%
if not exist "%logfolder%" mkdir "%logfolder%"
C:

reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v DisableSelectiveSuspend /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v SearchOnTaskbarMode /t REG_DWORD /d 0 /f
reg add "HKEY_USERS\.DEFAULT\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f
reg add "HKLM\Software\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" /v ExcludeHttpsRootDomain /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f
reg add "HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f

echo === Start Cleanup %date% %time% === >> "%logfile%"
if exist "%WINDIR%\Temp" copy /Y "%WINDIR%\Temp\*.log" "%logfolder%" >> "%logfile%" 2>&1
if exist "C:\OSDCloud\Logs" copy /Y "C:\OSDCloud\Logs\*.log" "%logfolder%" >> "%logfile%" 2>&1
if exist "%ProgramData%\OSDeploy" copy /Y "%ProgramData%\OSDeploy\*.log" "%logfolder%" >> "%logfile%" 2>&1

for %%D in ("C:\OSDCloud" "C:\Drivers" "C:\Intel" "%ProgramData%\OSDeploy") do (
    if exist %%D (
        echo Removing folder %%D >> "%logfile%"
        rmdir /S /Q %%D >> "%logfile%" 2>&1
    )
)

echo Starten van Copy-Start.ps1 >> "%logfile%"
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Copy-Start.ps1" >> "%logfile%" 2>&1
start /wait powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\Create-OSUpdateTask.ps1" >> "%logfile%" 2>&1
:: === Einde custom block ===
'@

if (Test-Path $SetupCompletePath) {
    Add-Content -Path $SetupCompletePath -Value "`r`n$SetupBlock`r`n"
}
else {
    "@echo off`r`n$SetupBlock`r`nexit /b 0" | Out-File -FilePath $SetupCompletePath -Encoding ascii -Force
}

Write-Host "Staging klaar op $Target`: $ScriptPath" -ForegroundColor Green

#=======================================================================
#   Reboot
#=======================================================================
#Write-Host -ForegroundColor Green "Herstart in 20 seconden..."
#Start-Sleep -Seconds 20
#wpeutil reboot
