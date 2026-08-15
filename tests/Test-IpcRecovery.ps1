[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $repoRoot "plugins\everything-search\skills\everything-search\scripts\Everything.Common.ps1"
. $commonScript

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$script:probeSequence = @()
$script:probeIndex = 0
$script:diagnosis = $null
$script:startResult = $null
$script:waitResult = $null
$script:startCalls = 0

function Set-TestScenario {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$ProbeSequence,

        [object]$Diagnosis,
        [object]$StartResult,
        [object]$WaitResult
    )

    $script:probeSequence = $ProbeSequence
    $script:probeIndex = 0
    $script:diagnosis = $Diagnosis
    $script:startResult = $StartResult
    $script:waitResult = $WaitResult
    $script:startCalls = 0
}

# Override only the side-effecting dependencies. Ensure-EverythingIpcReady
# remains the production implementation under test.
function Invoke-EverythingIpcProbe {
    param(
        [string]$EsPath,
        [string]$Instance
    )

    $index = [Math]::Min($script:probeIndex, $script:probeSequence.Count - 1)
    $exitCode = $script:probeSequence[$index]
    $script:probeIndex++
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = if ($exitCode -eq 0) { "1.4.1.1028" } else { "" }
    }
}

function Get-EverythingIpcDiagnosis {
    param(
        [int]$ExitCode,
        [string]$Instance
    )

    return $script:diagnosis
}

function Start-EverythingClient {
    param(
        [string]$Instance
    )

    $script:startCalls++
    return $script:startResult
}

function Wait-EverythingIpc {
    param(
        [string]$EsPath,
        [string]$Instance,
        [int]$TimeoutMilliseconds
    )

    return $script:waitResult
}

$startRecommended = [pscustomobject]@{
    code = "everything_not_running"
    message = "Everything is not running."
    recoverable = $true
    user_action_required = $false
    start_recommended = $true
    exit_code = 8
}
$manualAction = [pscustomobject]@{
    code = "ipc_elevation_mismatch"
    message = "Elevation mismatch."
    recoverable = $false
    user_action_required = $true
    start_recommended = $false
    exit_code = 8
}
$startSucceeded = [pscustomobject]@{
    started = $true
    path = "C:\Program Files\Everything\Everything.exe"
    process_id = 1234
    error = $null
}

Set-TestScenario -ProbeSequence 8, 0
$transient = Ensure-EverythingIpcReady `
    -EsPath "C:\fixture\es.exe" `
    -RetryDelayMilliseconds 100
Assert-Condition $transient.ready "A one-time IPC Error 8 was not recovered."
Assert-Condition $transient.ipc_retry_used "The transient retry was not reported."
Assert-Condition (-not $transient.client_started) "The client was started for a transient-only failure."
Assert-Condition ($script:startCalls -eq 0) "The transient-only case unexpectedly started Everything."

Set-TestScenario `
    -ProbeSequence 8, 8 `
    -Diagnosis $startRecommended `
    -StartResult $startSucceeded `
    -WaitResult ([pscustomobject]@{ ExitCode = 0; Text = "1.4.1.1028" })
$started = Ensure-EverythingIpcReady `
    -EsPath "C:\fixture\es.exe" `
    -AutoStart `
    -RetryDelayMilliseconds 100 `
    -StartupTimeoutMilliseconds 500
Assert-Condition $started.ready "Auto-start did not recover IPC readiness."
Assert-Condition $started.client_started "Auto-start recovery was not reported."
Assert-Condition ($script:startCalls -eq 1) "Auto-start was not bounded to one attempt."

Set-TestScenario `
    -ProbeSequence 8, 8 `
    -Diagnosis $manualAction `
    -StartResult $startSucceeded
$blocked = Ensure-EverythingIpcReady `
    -EsPath "C:\fixture\es.exe" `
    -AutoStart `
    -RetryDelayMilliseconds 100
Assert-Condition (-not $blocked.ready) "A manual-action diagnosis was incorrectly treated as ready."
Assert-Condition ($blocked.diagnosis.code -eq "ipc_elevation_mismatch") "The manual-action diagnosis changed unexpectedly."
Assert-Condition ($script:startCalls -eq 0) "Everything was started despite a non-recoverable diagnosis."

Set-TestScenario `
    -ProbeSequence 8, 8 `
    -Diagnosis $startRecommended `
    -StartResult $startSucceeded `
    -WaitResult ([pscustomobject]@{ ExitCode = 8; Text = "" })
$timedOut = Ensure-EverythingIpcReady `
    -EsPath "C:\fixture\es.exe" `
    -AutoStart `
    -RetryDelayMilliseconds 100 `
    -StartupTimeoutMilliseconds 500
Assert-Condition (-not $timedOut.ready) "A failed post-start probe was incorrectly treated as ready."
Assert-Condition ($timedOut.diagnosis.code -eq "ipc_unavailable_after_start") "The post-start timeout did not return a stable diagnosis."
Assert-Condition $timedOut.diagnosis.user_action_required "The post-start timeout did not request user action."
Assert-Condition ($script:startCalls -eq 1) "The post-start timeout retried client startup unexpectedly."

Write-Output "IPC recovery validation passed."
