# File: C:\Windows\Setup\Scripts\Create-RunOnce-CleanUp.ps1
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [string] $RunOnceTaskName = "Novoferm_OSDCleanUp_RunOnce",

    [Parameter(Mandatory = $false)]
    [string] $RunOnceScriptPath = "C:\Windows\Setup\Scripts\OSDCleanUp.ps1"
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
    $task.RegistrationInfo.Description = "Run-once Cleanup met SYSTEM-rechten bij eerstvolgende user logon. Verwijdert zichzelf na run."
    $task.Settings.Enabled = $true
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.AllowDemandStart = $true
    $task.Settings.MultipleInstances = 0
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.WakeToRun = $true
    $task.Settings.ExecutionTimeLimit = "PT0S"

    # Principal: SYSTEM
    $task.Principal.UserId = "NT AUTHORITY\SYSTEM"
    $task.Principal.LogonType = 5
    $task.Principal.RunLevel = 1

    # Trigger: bij logon
    $trigger = $task.Triggers.Create(9)
    $trigger.Enabled = $true
    $trigger.Delay = "PT15S"

    # Actie zonder parameters
    $wrapper = @"
& '$RunOnceScriptPath'
`$exitCode = if (`$LASTEXITCODE -ne `$null) { `$LASTEXITCODE } elseif (`$?) { 0 } else { 1 }
try { schtasks /Delete /TN '$RunOnceTaskName' /F | Out-Null } catch { }
exit `$exitCode
"@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrapper))

    $action = $task.Actions.Create(0)
    $action.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
    $action.WorkingDirectory = Split-Path -Path $RunOnceScriptPath -Parent

    $folder = $service.GetFolder("\")
    $null = $folder.RegisterTaskDefinition(
        $RunOnceTaskName,
        $task,
        6,
        $null,
        $null,
        5,
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
