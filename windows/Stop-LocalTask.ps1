$ErrorActionPreference = 'Stop'
Disable-ScheduledTask -TaskName 'CodexUsageWarmer' | Out-Null
Stop-ScheduledTask -TaskName 'CodexUsageWarmer'
Write-Output 'CodexUsageWarmer is disabled.'
