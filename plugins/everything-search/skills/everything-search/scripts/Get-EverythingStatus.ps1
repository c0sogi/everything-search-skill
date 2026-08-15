[CmdletBinding()]
param(
    [string]$Instance
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Everything.Common.ps1")

Assert-EverythingWindows

$platform = Get-EverythingPlatform
$esPath = Get-BundledEverythingEsPath
$esFile = Get-Item -LiteralPath $esPath
$esTrust = Get-BundledEverythingEsTrust -EsPath $esPath
$esVersionResult = if ($esTrust.trusted) {
    Invoke-EverythingEs -EsPath $esPath -Arguments @("-version")
}
else {
    [pscustomobject]@{ ExitCode = -1; Text = $null }
}
$ipcResult = if ($esTrust.trusted) {
    Invoke-EverythingIpcProbe -EsPath $esPath -Instance $Instance
}
else {
    [pscustomobject]@{ ExitCode = -1; Text = $null }
}
$everythingExecutables = @(Get-EverythingExecutableCandidates)
$processes = @(Get-Process -Name Everything -ErrorAction SilentlyContinue)

$processPaths = @(
    foreach ($process in $processes) {
        try {
            if ($process.Path) {
                $process.Path
            }
        }
        catch {
            # Service-owned processes may hide their executable path.
        }
    }
) | Sort-Object -Unique

$everythingInstalled = ($everythingExecutables.Count -gt 0) -or ($processes.Count -gt 0)
$ipcReady = ($ipcResult.ExitCode -eq 0) -and -not [string]::IsNullOrWhiteSpace($ipcResult.Text)
$ready = $esTrust.trusted -and $ipcReady
$diagnosis = if ($esTrust.trusted -and -not $ipcReady) {
    Get-EverythingIpcDiagnosis -ExitCode $ipcResult.ExitCode -Instance $Instance
}
else {
    $null
}

$recommendedAction = if (-not $esTrust.trusted) {
    "reinstall-skill"
}
elseif ($ready) {
    "none"
}
elseif ($diagnosis.code -eq "everything_not_installed") {
    "install-everything"
}
elseif ($diagnosis.code -eq "ipc_elevation_mismatch") {
    "align-process-elevation"
}
elseif ($diagnosis.start_recommended) {
    "start-everything"
}
else {
    "inspect-everything-ipc"
}

[pscustomobject]@{
    ready = $ready
    instance = if ([string]::IsNullOrWhiteSpace($Instance)) { $null } else { $Instance }
    os = [Environment]::OSVersion.VersionString
    platform = $platform
    es = [pscustomobject]@{
        path = $esPath
        version = $esVersionResult.Text
        file_version = $esFile.VersionInfo.FileVersion
        trusted = $esTrust.trusted
        sha256 = $esTrust.sha256
        expected_sha256 = $esTrust.expected_sha256
        hash_matches_manifest = $esTrust.hash_matches_manifest
        signature_status = $esTrust.signature_status
        signer = $esTrust.signer
        expected_signer = $esTrust.expected_signer
        signer_matches = $esTrust.signer_matches
    }
    everything = [pscustomobject]@{
        installed = $everythingInstalled
        running = $processes.Count -gt 0
        process_ids = @($processes | ForEach-Object { $_.Id })
        process_paths = @($processPaths)
        executable_paths = @($everythingExecutables)
        ipc_ready = $ipcReady
        ipc_exit_code = $ipcResult.ExitCode
        ipc_diagnosis = $diagnosis
        version = if ($ipcReady) { $ipcResult.Text } else { $null }
    }
    recommended_action = $recommendedAction
} | ConvertTo-Json -Depth 7
