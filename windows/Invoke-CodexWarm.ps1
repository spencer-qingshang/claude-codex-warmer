param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexUsageWarmer'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$warmerLog = Join-Path $StateRoot 'warmer.log'
function Write-WarmerLog([string]$Message) {
    $warmerEntry = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') + ' ' + $Message
    Add-Content -LiteralPath $warmerLog -Value $warmerEntry -Encoding UTF8
    Write-Output $warmerEntry
}

$warmerMutex = New-Object Threading.Mutex($false, 'Local\CodexUsageWarmer')
$warmerLocked = $false
try {
    try { $warmerLocked = $warmerMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $warmerLocked = $true }
    if (!$warmerLocked) { Write-WarmerLog 'SKIP: another warm-up is running.'; exit 0 }

    $warmerConfig = Get-Content -Raw -LiteralPath (Join-Path $StateRoot 'config.json') | ConvertFrom-Json
    if ($warmerConfig.model -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid configured model name.' }
    if (!(Test-Path -LiteralPath $warmerConfig.codexPath)) { throw 'Pinned Codex CLI is missing.' }
    $warmerAuthHome = Join-Path $StateRoot 'auth'
    $warmerAuthPath = Join-Path $warmerAuthHome 'auth.json'
    if (!(Test-Path -LiteralPath $warmerAuthPath)) { throw 'Codex login is missing.' }

    # Follow the same Windows proxy settings used by the user's browser.
    $warmerProxy = $env:HTTPS_PROXY
    $warmerProxySettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($warmerProxySettings.ProxyEnable -eq 1 -and $warmerProxySettings.ProxyServer) {
        $warmerProxy = [string]$warmerProxySettings.ProxyServer
        if ($warmerProxy -match '=') {
            $warmerProxyEntries = @{}
            foreach ($warmerEntry in ($warmerProxy -split ';')) {
                $warmerPair = $warmerEntry -split '=', 2
                if ($warmerPair.Count -eq 2) { $warmerProxyEntries[$warmerPair[0]] = $warmerPair[1] }
            }
            $warmerProxy = $warmerProxyEntries['https']
            if (!$warmerProxy) { $warmerProxy = $warmerProxyEntries['http'] }
        }
        if ($warmerProxy -and $warmerProxy -notmatch '^\w+://') { $warmerProxy = 'http://' + $warmerProxy }
    }

    $warmerNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $warmerStatePath = Join-Path $StateRoot 'state.json'
    $warmerLast = 0L
    if (Test-Path -LiteralPath $warmerStatePath) {
        $warmerState = Get-Content -Raw -LiteralPath $warmerStatePath | ConvertFrom-Json
        $warmerLast = [long]$warmerState.lastWarmEpoch
    }
    $warmerElapsed = $warmerNow - $warmerLast
    $warmerSend = $Force.IsPresent
    if (!$Force) {
        $warmerMeterAvailable = $false
        try {
            $warmerAuth = Get-Content -Raw -LiteralPath $warmerAuthPath | ConvertFrom-Json
            $warmerHeaders = @{ Authorization = 'Bearer ' + $warmerAuth.tokens.access_token; 'chatgpt-account-id' = $warmerAuth.tokens.account_id }
            $warmerRequest = @{ Uri='https://chatgpt.com/backend-api/wham/usage'; Headers=$warmerHeaders; TimeoutSec=20 }
            if ($warmerProxy) { $warmerRequest.Proxy = $warmerProxy }
            $warmerUsage = Invoke-RestMethod @warmerRequest
            $warmerWindow = $warmerUsage.rate_limit.primary_window
            if ($null -ne $warmerWindow.reset_after_seconds) {
                $warmerMeterAvailable = $true
                $warmerWindowLength = 18000L
                if ($warmerWindow.limit_window_seconds) { $warmerWindowLength = [long]$warmerWindow.limit_window_seconds }
                $warmerWeekly = $warmerUsage.rate_limit.secondary_window
                if ($null -ne $warmerWeekly -and $warmerWeekly.used_percent -ge 100) {
                    Write-WarmerLog 'SKIP: weekly quota is exhausted.'; exit 0
                }
                if ([long]$warmerWindow.reset_after_seconds -lt ($warmerWindowLength - 120)) {
                    Write-WarmerLog ('SKIP: usage window is active; resets in ' + $warmerWindow.reset_after_seconds + ' seconds.'); exit 0
                }
                if ($warmerElapsed -lt [long]$warmerConfig.minimumIntervalSeconds) {
                    Write-WarmerLog 'SKIP: minimum five-hour interval has not elapsed.'; exit 0
                }
                $warmerSend = $true
            }
        } catch {
            Write-WarmerLog ('Usage meter unavailable (' + $_.Exception.GetType().Name + '); using last successful warm-up time.')
        } finally {
            $warmerHeaders = $null
            $warmerAuth = $null
            $warmerRequest = $null
        }
        if (!$warmerMeterAvailable) {
            $warmerSend = $warmerElapsed -ge [long]$warmerConfig.fallbackIntervalSeconds
            if (!$warmerSend) { Write-WarmerLog 'SKIP: fallback five-hour-one-minute interval has not elapsed.'; exit 0 }
        }
    }

    if ($warmerSend) {
        $warmerScratch = Join-Path $StateRoot 'scratch'
        New-Item -ItemType Directory -Force -Path $warmerScratch | Out-Null
        $warmerResponsePath = Join-Path $StateRoot 'last-response.txt'
        $warmerCliLogPath = Join-Path $StateRoot 'last-cli.log'
        for ($warmerAttempt = 1; $warmerAttempt -le 3; $warmerAttempt++) {
            $warmerStart = New-Object Diagnostics.ProcessStartInfo
            $warmerStart.FileName = $warmerConfig.codexPath
            $warmerStart.Arguments = 'exec --skip-git-repo-check --ignore-user-config --ephemeral --sandbox read-only --color never -m ' + $warmerConfig.model + ' -c model_reasoning_effort=low --output-last-message "' + $warmerResponsePath + '" hi'
            $warmerStart.WorkingDirectory = $warmerScratch
            $warmerStart.UseShellExecute = $false
            $warmerStart.CreateNoWindow = $true
            $warmerStart.RedirectStandardInput = $true
            $warmerStart.RedirectStandardOutput = $true
            $warmerStart.RedirectStandardError = $true
            $warmerStart.EnvironmentVariables['CODEX_HOME'] = $warmerAuthHome
            if ($warmerProxy) {
                $warmerStart.EnvironmentVariables['HTTPS_PROXY'] = $warmerProxy
                $warmerStart.EnvironmentVariables['HTTP_PROXY'] = $warmerProxy
                $warmerStart.EnvironmentVariables['ALL_PROXY'] = $warmerProxy
            }
            $warmerProcess = New-Object Diagnostics.Process
            $warmerProcess.StartInfo = $warmerStart
            try {
                [void]$warmerProcess.Start()
                $warmerProcess.StandardInput.Close()
                $warmerStdout = $warmerProcess.StandardOutput.ReadToEndAsync()
                $warmerStderr = $warmerProcess.StandardError.ReadToEndAsync()
                if (!$warmerProcess.WaitForExit(180000)) {
                    $warmerProcess.Kill()
                    $warmerProcess.WaitForExit()
                    Write-WarmerLog ('Attempt ' + $warmerAttempt + ' timed out.')
                } else {
                    $warmerOutText = $warmerStdout.GetAwaiter().GetResult()
                    $warmerErrText = $warmerStderr.GetAwaiter().GetResult()
                    Set-Content -LiteralPath $warmerCliLogPath -Value ($warmerErrText + "`r`n" + $warmerOutText) -Encoding UTF8
                    if ($warmerProcess.ExitCode -eq 0) {
                        @{ lastWarmEpoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); model=$warmerConfig.model } | ConvertTo-Json | Set-Content -LiteralPath $warmerStatePath -Encoding UTF8
                        Write-WarmerLog ('SUCCESS: sent hi to ' + $warmerConfig.model + '.'); exit 0
                    }
                    Write-WarmerLog ('Attempt ' + $warmerAttempt + ' failed with exit code ' + $warmerProcess.ExitCode + '. See last-cli.log.')
                    if ($warmerErrText -match 'token_revoked|refresh_token_reused|refresh token was already used') { throw 'Codex credentials need a fresh official login.' }
                }
            } finally { $warmerProcess.Dispose() }
            if ($warmerAttempt -lt 3) { Start-Sleep -Seconds 10 }
        }
        throw 'All warm-up attempts failed.'
    }
} catch {
    Write-WarmerLog ('ERROR: ' + $_.Exception.Message)
    exit 1
} finally {
    if ($warmerLocked) { $warmerMutex.ReleaseMutex() }
    $warmerMutex.Dispose()
}
