# Pad naar het script dat je wil uitvoeren
$ScriptPath = "C:\Windows\Setup\scripts\OSUpdate.ps1"
$TaskName   = "RunOnce-SetHKCU"

# Check of script bestaat
if (!(Test-Path $ScriptPath)) {
    Write-Host "ERROR: Scriptbestand niet gevonden op $ScriptPath" -ForegroundColor Red
    exit 1
}

# Connect met Task Scheduler
$service = New-Object -ComObject Schedule.Service
$service.Connect()

# Maak een nieuwe taak
$task = $service.NewTask(0)
$task.RegistrationInfo.Description = "Voert éénmalig een script uit bij gebruikerslogon"
$task.Settings.Enabled = $true
$task.Settings.AllowDemandStart = $true
$task.Settings.StartWhenAvailable = $true
$task.Principal.UserId = "$env:USERNAME"
$task.Principal.LogonType = 3   # InteractiveToken (User context)
$task.Principal.RunLevel = 1    # Least privileges (dus niet als admin)

# Trigger: bij logon, zonder vertraging
$trigger = $task.Triggers.Create(9)  # 9 = LogonTrigger
$trigger.Enabled = $true

# Actie: start PowerShell met script
$action = $task.Actions.Create(0)  # 0 = Exec
$action.Path = "powershell.exe"
$action.Arguments = "-ExecutionPolicy Bypass -NoLogo -WindowStyle Hidden -File `"$ScriptPath`""

# Registreer de taak onder de ingelogde gebruiker
$folder = $service.GetFolder("\")
$folder.RegisterTaskDefinition($TaskName, $task, 6, $env:USERNAME, $null, 3)  # 6 = CreateOrUpdate, 3 = InteractiveToken
