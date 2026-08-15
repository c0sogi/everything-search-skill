[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$InstallIfMissing,
    [switch]$StartIfStopped,
    [string]$Instance,

    [ValidateRange(1, 60)]
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Everything.Common.ps1")

function Get-CurrentEverythingStatus {
    $parameters = @{}
    if (-not [string]::IsNullOrWhiteSpace($Instance)) {
        $parameters["Instance"] = $Instance
    }
    $json = & (Join-Path $PSScriptRoot "Get-EverythingStatus.ps1") @parameters
    return ($json | ConvertFrom-Json)
}

Assert-EverythingWindows
$status = Get-CurrentEverythingStatus

if ($status.ready) {
    $status | ConvertTo-Json -Depth 7
    return
}

if (-not $status.everything.installed) {
    if (-not $InstallIfMissing) {
        $status | ConvertTo-Json -Depth 7
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Everything is not installed and winget.exe is unavailable. Install Everything from https://www.voidtools.com/."
    }

    if (-not $PSCmdlet.ShouldProcess("voidtools Everything", "Install with WinGet")) {
        $status | ConvertTo-Json -Depth 7
        return
    }

    $wingetOutput = @(
        & $winget.Source install `
            --id voidtools.Everything `
            --exact `
            --source winget `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements `
            --disable-interactivity 2>&1
    )
    $wingetExitCode = $LASTEXITCODE
    if ($wingetExitCode -ne 0) {
        $message = ($wingetOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw "WinGet failed to install Everything (exit $wingetExitCode).`n$message"
    }

    $status = Get-CurrentEverythingStatus
}

if (-not $status.ready -and $StartIfStopped) {
    $candidates = @(Get-EverythingExecutableCandidates)
    if ($candidates.Count -eq 0) {
        throw "Everything appears installed, but Everything.exe could not be located."
    }

    $target = if ([string]::IsNullOrWhiteSpace($Instance)) {
        $candidates[0]
    }
    else {
        "$($candidates[0]) (instance: $Instance)"
    }

    if (-not $PSCmdlet.ShouldProcess($target, "Start Everything in the background")) {
        $status | ConvertTo-Json -Depth 7
        return
    }

    $startResult = Start-EverythingClient -Instance $Instance
    if (-not $startResult.started) {
        throw "Everything could not be started: $($startResult.error)"
    }
}

if ($StartIfStopped -or $InstallIfMissing) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $status = Get-CurrentEverythingStatus
    } while (-not $status.ready -and [DateTime]::UtcNow -lt $deadline)
}

$status | ConvertTo-Json -Depth 7
if (-not $status.ready -and ($StartIfStopped -or $InstallIfMissing)) {
    exit 8
}
