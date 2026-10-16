param([string]$RunnerPath = (Join-Path $PSScriptRoot 'Invoke-CodexWarm.ps1'))
$ErrorActionPreference = 'Stop'
$warmerTaskName = 'CodexUsageWarmer'
$warmerRunner = (Resolve-Path -LiteralPath $RunnerPath).Path
$warmerPrincipalId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$warmerAction = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -File "' + $warmerRunner + '"')
$warmerTimer = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 30)
$warmerLogon = New-ScheduledTaskTrigger -AtLogOn -User $warmerPrincipalId
$warmerSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$warmerPrincipal = New-ScheduledTaskPrincipal -UserId $warmerPrincipalId -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $warmerTaskName -Action $warmerAction -Trigger @($warmerTimer, $warmerLogon) -Settings $warmerSettings -Principal $warmerPrincipal -Description 'Codex usage-window warm-up, adapted from viseshb/claude-codex-warmer. Checks every 30 minutes while signed in; sends hi only after the window expires.' -Force | Out-Null
Write-Output ('Registered ' + $warmerTaskName + '. Runs while this Windows user is signed in.')
