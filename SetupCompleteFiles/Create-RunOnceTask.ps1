# File: C:\Windows\Setup\Scripts\Create-RunOnceTask.ps1
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [string] $RunOnceTaskName = "Novoferm_OSUpdate_RunOnce",

    [Parameter(Mandatory = $false)]
    [string] $RunOnceScriptPath = "C:\Windows\Setup\Scripts\OSUpdate.ps1",

    [Parameter(Mandatory = $false)]
    [string] $ScriptParameters = "-Reboot Soft"
)

$ErrorActionPreference = 'Stop'
function Get-Ts { Get-Date -Format 'dd-MM-yyyy HH:mm:ss' }
Write-Output "$(Get-Ts) Start: taakregistratie (run-once, self-delete)."

if (!(Test-Path -Path $RunOnceScriptPath -PathType Leaf)) {
    Write-Error "$(Get-Ts) FOUT: Script niet gevonden: $RunOnceScriptPath"
    exit 1
}

try {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()

    $task = $service.NewTask(0)
    $task.RegistrationInfo.Description = "Run-once OS/Driver updates met SYSTEM-rechten bij eerstvolgende user logon. Verwijdert zichzelf na run."
    $task.Settings.Enabled = $true
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.AllowDemandStart = $true
    $task.Settings.MultipleInstances = 0           # IgnoreNew
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.WakeToRun = $true
    $task.Settings.ExecutionTimeLimit = "PT0S"     # Geen time limit
    # GEEN DeleteExpiredTaskAfter ⇒ geen EndBoundary-issues

    # Principal: SYSTEM
    $task.Principal.UserId = "NT AUTHORITY\SYSTEM"
    $task.Principal.LogonType = 5                  # TASK_LOGON_SERVICE_ACCOUNT
    $task.Principal.RunLevel = 1                   # Highest

    # Trigger: bij logon (alle users), kleine delay
    $trigger = $task.Triggers.Create(9)            # TASK_TRIGGER_LOGON
    $trigger.Enabled = $true
    $trigger.Delay = "PT15S"

    # Actie: wrapper die script runt, taak daarna verwijdert, exitcode doorgeeft
    $wrapper = @"
& '$RunOnceScriptPath' $ScriptParameters
`$exitCode = if (`$LASTEXITCODE -ne `$null) { `$LASTEXITCODE } elseif (`$?) { 0 } else { 1 }
try { schtasks /Delete /TN '$RunOnceTaskName' /F | Out-Null } catch { }
exit `$exitCode
"@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrapper))

    $action = $task.Actions.Create(0)              # TASK_ACTION_EXEC
    $action.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
    $action.WorkingDirectory = Split-Path -Path $RunOnceScriptPath -Parent

    $folder = $service.GetFolder("\")
    $null = $folder.RegisterTaskDefinition(
        $RunOnceTaskName,
        $task,
        6,      # CreateOrUpdate
        $null,  # user
        $null,  # password
        5,      # TASK_LOGON_SERVICE_ACCOUNT (SYSTEM)
        $null
    )

    Write-Output "$(Get-Ts) OK: Taak '$RunOnceTaskName' geregistreerd. Script: $RunOnceScriptPath"
    Write-Output "$(Get-Ts) De taak verwijdert zichzelf direct na uitvoeren."

}
catch {
    Write-Error "$(Get-Ts) FATAAL: $($_.Exception.Message)"
    exit 1
}

Write-Output "$(Get-Ts) Klaar."
