[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$InstallIfMissing,
    [switch]$StartIfStopped,

    [ValidateRange(1, 60)]
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Everything.Common.ps1")

function Get-CurrentEverythingStatus {
    $json = & (Join-Path $PSScriptRoot "Get-EverythingStatus.ps1")
    return ($json | ConvertFrom-Json)
}

Assert-EverythingWindows
$status = Get-CurrentEverythingStatus

if ($status.ready) {
    $status | ConvertTo-Json -Depth 6
    return
}

if (-not $status.everything.installed) {
    if (-not $InstallIfMissing) {
        $status | ConvertTo-Json -Depth 6
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Everything is not installed and winget.exe is unavailable. Install Everything from https://www.voidtools.com/."
    }

    if (-not $PSCmdlet.ShouldProcess("voidtools Everything", "Install with WinGet")) {
        $status | ConvertTo-Json -Depth 6
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

if (-not $status.everything.running -and $StartIfStopped) {
    $candidates = @(Get-EverythingExecutableCandidates)
    if ($candidates.Count -eq 0) {
        throw "Everything appears installed, but Everything.exe could not be located."
    }

    $everythingPath = $candidates[0]
    if (-not $PSCmdlet.ShouldProcess($everythingPath, "Start Everything in the background")) {
        $status | ConvertTo-Json -Depth 6
        return
    }

    Start-Process -FilePath $everythingPath -ArgumentList "-startup"
}

if ($StartIfStopped -or $InstallIfMissing) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $status = Get-CurrentEverythingStatus
    } while (-not $status.ready -and [DateTime]::UtcNow -lt $deadline)
}

$status | ConvertTo-Json -Depth 6
if (-not $status.ready -and ($StartIfStopped -or $InstallIfMissing)) {
    exit 8
}
