# PowerShell-script voor het aanmaken van een **eenmalige, zelfverwijderende** geplande taak.
# De taak draait onder het **SYSTEM**-account (LogonTrigger) om 'OSUpdate.ps1' met hoge bevoegdheden uit te voeren,
# zonder onderbrekingen door energiebeheer.
#
# D.Bruins

# Pad naar het script
$ScriptPath = "C:\Windows\Setup\scripts\OSUpdate.ps1"
$TaskName = "RunOnce-OSUpdate"

# --- Instellingen voor zelfverwijdering ---
# Commando om de taak te verwijderen na uitvoering.
# WIJZIGING: Expliciet pad naar schtasks.exe voor robuustheid onder SYSTEM-account.
$DeleteCommand = "C:\Windows\System32\schtasks.exe /delete /tn `"$TaskName`" /f" 
# Gecombineerd commando: 1. Voer OSUpdate.ps1 uit, 2. Verwijder de scheduled task.
# De backticks zijn cruciaal voor correcte escaping binnen de COM object arguments.
$ActionCommand = " & `"$ScriptPath`" ; $DeleteCommand "

# Check of script bestaat
if (!(Test-Path $ScriptPath)) {
    Write-Host "FOUT: Scriptbestand niet gevonden op $ScriptPath" -ForegroundColor Red
    exit 1
}

# Connect met Task Scheduler
$service = New-Object -ComObject Schedule.Service
$service.Connect()

# Maak een nieuwe taak
$task = $service.NewTask(0)
$task.RegistrationInfo.Description = "Voert éénmalig OSUpdate uit bij gebruikerslogon en verwijderd zichzelf daarna."
$task.Settings.Enabled = $true
$task.Settings.AllowDemandStart = $true
$task.Settings.StartWhenAvailable = $true

# Gebruik het 'SYSTEM' account.
$task.Principal.UserId = "SYSTEM"
$task.Principal.LogonType = 5
$task.Principal.RunLevel = 1

# Taak uitvoeren, ook op batterij
$task.Settings.DisallowStartIfOnBatteries = $false
# Taak niet stoppen als de computer overschakelt op batterijstroom.
$task.Settings.StopIfGoingOnBatteries = $false
$task.Settings.IdleSettings.StopOnIdleEnd = $false
$task.Settings.IdleSettings.WaitTimeout = "PT0S" # Geen wachttijd

# Trigger: bij logon (LogonTrigger)
$trigger = $task.Triggers.Create(9)  # 9 = LogonTrigger
$trigger.Enabled = $true

# Actie: start PowerShell met het gecombineerde commando
$action = $task.Actions.Create(0) # 0 = Exec
$action.Path = "powershell.exe"
# Gebruik -Command om meerdere opdrachten in één regel uit te voeren
$action.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$ActionCommand`""

# Registreer de taak
# Gebruik $null voor de gebruiker en TaskLogonType 0 (Interactive) bij gebruik van SYSTEM
$folder = $service.GetFolder("\")
$folder.RegisterTaskDefinition($TaskName, $task, 6, $null, $null, 0) # 6 = CreateOrUpdate, 0 = TaskLogonInteractive

Write-Host "Taak '$TaskName' succesvol aangemaakt." -ForegroundColor Green
