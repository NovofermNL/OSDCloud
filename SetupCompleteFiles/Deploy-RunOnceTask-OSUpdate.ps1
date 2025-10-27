# Config
$ScriptPath = "C:\Windows\Setup\Scripts\OSUpdate.ps1"
$TaskName   = "RunOnce-OSUpdate"

if (!(Test-Path $ScriptPath)) {
    Write-Host "FOUT: Scriptbestand niet gevonden op $ScriptPath" -ForegroundColor Red
    exit 1
}

# COM connect
$service = New-Object -ComObject Schedule.Service
$service.Connect()
$task = $service.NewTask(0)

$task.RegistrationInfo.Description = "Voert éénmalig OSUpdate uit bij gebruikerslogon en verwijdert zichzelf daarna."
$task.Settings.Enabled = $true
$task.Settings.AllowDemandStart = $true
$task.Settings.StartWhenAvailable = $true
$task.Settings.DisallowStartIfOnBatteries = $false
$task.Settings.StopIfGoingOnBatteries = $false
$task.Settings.IdleSettings.StopOnIdleEnd = $false
$task.Settings.IdleSettings.WaitTimeout = "PT0S"

# SYSTEM, highest
$task.Principal.UserId = "SYSTEM"
$task.Principal.LogonType = 5   # Service account
$task.Principal.RunLevel = 1    # Highest

# Trigger: Logon + kleine delay
$trigger = $task.Triggers.Create(9)  # LogonTrigger
$trigger.Enabled = $true
$trigger.Delay = "PT10S"

# Actie
$DeleteCommand = "$env:SystemRoot\System32\schtasks.exe /delete /tn `"$TaskName`" /f"
$ActionCommand = "& '$ScriptPath'; $DeleteCommand"

$action = $task.Actions.Create(0) # Exec
$action.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$action.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$ActionCommand`""

# Register
$folder = $service.GetFolder("\")
$folder.RegisterTaskDefinition($TaskName, $task, 6, $null, $null, 0) | Out-Null

# start
try {
    ($folder.GetTask($TaskName)).Run($null) | Out-Null
    Write-Host "Taak '$TaskName' aangemaakt en direct gestart."
}
catch {
    Write-Host "Taak '$TaskName' aangemaakt, maar direct starten faalde: $($_.Exception.Message)"
    # fallback
    Start-Process -FilePath "$env:SystemRoot\System32\schtasks.exe" -ArgumentList "/Run /TN `"$TaskName`"" -WindowStyle Hidden -Wait
}
