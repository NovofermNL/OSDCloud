Write-Host -ForegroundColor Yellow "Starten van test installatie Windows 11 25H2 NL"

#################################################################
#   [PreOS] Update Module
#################################################################
Write-Host -ForegroundColor Green "Updaten OSD PowerShell Module"

# NuGet-provider en PSGallery vertrouwen (handig in WinPE/clean)
try { Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Out-Null }
catch { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }

try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch {}

Install-Module OSD -Force -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Green "Importeren OSD PowerShell Module"
Import-Module OSD -Force


#=======================================================================
#   [OS] Params and Start-OSDCloud
#=======================================================================
$Params = @{
    OSVersion = "Windows 11"
    OSBuild = "25H2"
    OSEdition = "Pro"
    OSLanguage = "nl-NL"
    OSLicense = "Retail"
    ZTI = $true
}
Start-OSDCloud @Params

#================================================
#  [PostOS] OOBEDeploy Configuration
#================================================
Write-Host -ForegroundColor Green "Create C:\ProgramData\OSDeploy\OSDeploy.OOBEDeploy.json"
$OOBEDeployJson = @'
{
    "Autopilot":  {
                      "IsPresent":  true
                  },
    "AddNetFX3":  {
                      "IsPresent":  true
                    },                     
    "RemoveAppx":  [
                       "Microsoft.549981C3F5F10",
                        "Microsoft.BingWeather",
                        "Microsoft.GetHelp",
                        "Microsoft.Getstarted",
                        "Microsoft.Microsoft3DViewer",
                        "Microsoft.MicrosoftOfficeHub",
                        "Microsoft.MicrosoftSolitaireCollection",
                        "Microsoft.MixedReality.Portal",
                        "Microsoft.People",
                        "Microsoft.SkypeApp",
                        "Microsoft.Wallet",
                        "Microsoft.WindowsCamera",
                        "microsoft.windowscommunicationsapps",
                        "Microsoft.WindowsFeedbackHub",
                        "Microsoft.WindowsMaps",
                        "Microsoft.Xbox.TCUI",
                        "Microsoft.XboxApp",
                        "Microsoft.XboxGameOverlay",
                        "Microsoft.XboxGamingOverlay",
                        "Microsoft.XboxIdentityProvider",
                        "Microsoft.XboxSpeechToTextOverlay",
                        "Microsoft.YourPhone",
                        "Microsoft.ZuneMusic",
                        "Microsoft.ZuneVideo"
                   ],
    "UpdateDrivers":  {
                          "IsPresent":  true
                      },
    "UpdateWindows":  {
                          "IsPresent":  true
                      }
}
'@
If (!(Test-Path "C:\ProgramData\OSDeploy")) {
    New-Item "C:\ProgramData\OSDeploy" -ItemType Directory -Force | Out-Null
}
$OOBEDeployJson | Out-File -FilePath "C:\ProgramData\OSDeploy\OSDeploy.OOBEDeploy.json" -Encoding ascii -Force

#================================================
#  [PostOS] AutopilotOOBE Configuration Staging
#================================================
<#
Write-Host -ForegroundColor Green "Create C:\ProgramData\OSDeploy\OSDeploy.AutopilotOOBE.json"
$AutopilotOOBEJson = @'
{
	"Assign": {
		"IsPresent": false
	},
	"GroupTag": "NL",
	"GroupTagOptions": [
		"NL",
		"BE"
	],
	"Hidden": [
		"AssignedComputerName",
		"AssignedUser",
		"PostAction",
		"Assign",
		"AddToGroup"
	],
	"PostAction": "Quit",
	"Run": "NetworkingWireless",
	"Docs": "https://google.com/",
	"Title": "Novoferm Nederland Autopilot Registrering"
}
'@
If (!(Test-Path "C:\ProgramData\OSDeploy")) {
    New-Item "C:\ProgramData\OSDeploy" -ItemType Directory -Force | Out-Null
}
$AutopilotOOBEJson | Out-File -FilePath "C:\ProgramData\OSDeploy\OSDeploy.AutopilotOOBE.json" -Encoding ascii -Force
#>

#================================================
#  [PostOS] OOBE.cmd (one-shot, geen expliciete reboot)
#================================================
Write-Host -ForegroundColor Green "Create C:\Windows\Setup\Scripts\OOBE.cmd"
$null = New-Item -ItemType Directory -Path 'C:\Windows\Setup\Scripts' -Force

$OOBECMD = @'
@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "MARKER=%ProgramData%\OSDeploy\OOBE.done"

rem -> voorkom herhaalde uitvoering
if exist "%MARKER%" goto :EOF

rem -> Start alleen OOBEDeploy; laat OOBEDeploy zelf herstarten indien nodig
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Import-Module OSD -Force; Start-OOBEDeploy"

rem -> markeer als voltooid
if not exist "%ProgramData%\OSDeploy" mkdir "%ProgramData%\OSDeploy"
if not exist "%MARKER%" ( >"%MARKER%" echo %DATE% %TIME% )

endlocal
exit /b 0
'@

$OOBECMD | Out-File -FilePath 'C:\Windows\Setup\Scripts\OOBE.cmd' -Encoding ascii -Force

#================================================
#  [PostOS] SetupComplete CMD Command Line
#================================================
<#
Write-Host -ForegroundColor Green "Create C:\Windows\Setup\Scripts\SetupComplete.cmd"
$SetupCompleteCMD = @'
RD C:\OSDCloud\OS /S /Q
RD C:\Drivers /S /Q
'@
$SetupCompleteCMD | Out-File -FilePath 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -Encoding ascii -Force
#>
#=======================================================================
#   Restart-Computer
#=======================================================================
Write-Host "Restarting in 20 seconds!" -ForegroundColor Green
Start-Sleep -Seconds 20
wpeutil reboot

