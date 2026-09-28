[CmdletBinding(DefaultParameterSetName = 'Login')]
param(
    [Parameter(ParameterSetName = 'Login')]
    [switch]$DeviceAuth,
    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$candidateExecutables = [System.Collections.Generic.List[string]]::new()
$bundledRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
$candidateExecutables.Add((Join-Path $bundledRoot 'codex.exe'))
if (Test-Path -LiteralPath $bundledRoot) {
    Get-ChildItem -LiteralPath $bundledRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        ForEach-Object { $candidateExecutables.Add((Join-Path $_.FullName 'codex.exe')) }
}
$candidateExecutables.Add((Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'))
$pathCommand = Get-Command codex.exe -ErrorAction SilentlyContinue
if ($pathCommand) {
    $candidateExecutables.Add($pathCommand.Source)
}
$selectedExecutable = $candidateExecutables |
    Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and ($_ -notlike '*\WindowsApps\*') } |
    Select-Object -First 1
if (-not $selectedExecutable) {
    throw 'Codex CLI nicht gefunden. Bitte Codex installieren und dieses Skript erneut starten.'
}

$dashboardProfile = Join-Path $env:LOCALAPPDATA 'OpenAIUsageDashboard\Codex'
if (-not (Test-Path -LiteralPath (Join-Path $dashboardProfile 'auth.json'))) {
    # Reuse a login written by a helper running inside the Codex MSIX package.
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packageRoot) {
        $cachedProfile = Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'OpenAI.Codex_*' |
            ForEach-Object { Join-Path $_.FullName 'LocalCache\Local\OpenAIUsageDashboard\Codex' } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ 'auth.json') } |
            Select-Object -First 1
        if ($cachedProfile) { $dashboardProfile = $cachedProfile }
    }
}
New-Item -ItemType Directory -Path $dashboardProfile -Force | Out-Null
if (-not $Status) {
    Write-Host 'Bitte mit dem ChatGPT-Konto anmelden, dessen Limits das Dashboard anzeigen soll.'
}
Write-Host "Dashboard-Profil: $dashboardProfile"

$loginStart = [System.Diagnostics.ProcessStartInfo]::new()
$loginStart.FileName = $selectedExecutable
$loginStart.WorkingDirectory = Split-Path -Parent $selectedExecutable
$loginStart.UseShellExecute = $false
$loginStart.CreateNoWindow = $true
$loginStart.RedirectStandardOutput = $true
$loginStart.RedirectStandardError = $true
$loginStart.EnvironmentVariables['CODEX_HOME'] = $dashboardProfile
if (-not $loginStart.EnvironmentVariables['HOME']) {
    $loginStart.EnvironmentVariables['HOME'] = $env:USERPROFILE
}
$loginStart.Arguments = '-c cli_auth_credentials_store=file -c forced_login_method=chatgpt login'
if ($Status) {
    $loginStart.Arguments += ' status'
}
elseif ($DeviceAuth) {
    $loginStart.Arguments += ' --device-auth'
}

$loginProcess = [System.Diagnostics.Process]::Start($loginStart)
try {
    # Stream both channels while login is pending so device codes remain visible.
    $outputRead = $loginProcess.StandardOutput.ReadLineAsync()
    $errorRead = $loginProcess.StandardError.ReadLineAsync()
    while (($null -ne $outputRead) -or ($null -ne $errorRead)) {
        $pendingReads = @($outputRead, $errorRead) | Where-Object { $null -ne $_ }
        [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$pendingReads, 250) | Out-Null
        if (($null -ne $outputRead) -and $outputRead.IsCompleted) {
            $outputLine = $outputRead.GetAwaiter().GetResult()
            $outputRead = $null
            if ($null -ne $outputLine) {
                Write-Host $outputLine
                $outputRead = $loginProcess.StandardOutput.ReadLineAsync()
            }
        }
        if (($null -ne $errorRead) -and $errorRead.IsCompleted) {
            $errorLine = $errorRead.GetAwaiter().GetResult()
            $errorRead = $null
            if ($null -ne $errorLine) {
                Write-Host $errorLine
                $errorRead = $loginProcess.StandardError.ReadLineAsync()
            }
        }
    }
    $loginProcess.WaitForExit()
    if ($loginProcess.ExitCode -ne 0) {
        throw "Die ChatGPT-Anmeldung wurde nicht abgeschlossen (Exitcode $($loginProcess.ExitCode))."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dashboardProfile 'auth.json'))) {
        throw 'Die Anmeldung hat keine Zugangsdaten im Dashboard-Profil gespeichert.'
    }
    if (-not $Status) {
        Write-Host 'ChatGPT-Anmeldung gespeichert. Das Dashboard kann die Daten bei der naechsten Aktualisierung abrufen.'
    }
}
finally {
    if (-not $loginProcess.HasExited) {
        $loginProcess.Kill()
        $loginProcess.WaitForExit()
    }
    $loginProcess.Dispose()
}
