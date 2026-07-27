[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot "plugins\everything-search\skills\everything-search\scripts"
$statusScript = Join-Path $scriptRoot "Get-EverythingStatus.ps1"
$searchScript = Join-Path $scriptRoot "Search-Everything.ps1"
$initializeScript = Join-Path $scriptRoot "Initialize-Everything.ps1"

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

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $true)]
        [string]$MessagePattern
    )

    try {
        & $Action
        throw "Expected an error matching '$MessagePattern'."
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw
        }
    }
}

$status = & $statusScript | ConvertFrom-Json
Assert-Condition $status.ready "Everything is not ready. Run Initialize-Everything.ps1 after approving any required setup."
Assert-Condition ($status.es.version -eq "1.1.0.37") "Unexpected bundled ES version."

$readmePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot "README.md")).Path
$readmeSearch = & $searchScript `
    -Query "README.md ext:md" `
    -Path $repoRoot `
    -FilesOnly `
    -MaxResults 20 |
    ConvertFrom-Json
Assert-Condition ($readmeSearch.returned -eq 1) "Expected exactly one repository README result."
Assert-Condition (@($readmeSearch.results.full_path) -contains $readmePath) "The repository README path was not returned."

$limitedSearch = & $searchScript `
    -Query "ext:md" `
    -Path $repoRoot `
    -FilesOnly `
    -MaxResults 1 |
    ConvertFrom-Json
Assert-Condition ($limitedSearch.returned -eq 1) "The limited search returned an unexpected count."
Assert-Condition $limitedSearch.limit_reached "The limited search did not report truncation."

$emptySearch = & $searchScript `
    -Query "codex-no-such-file-7f1df8a7" `
    -Path $repoRoot `
    -MaxResults 20 |
    ConvertFrom-Json
Assert-Condition ($emptySearch.returned -eq 0) "The no-result query unexpectedly matched a path."
Assert-Condition (-not $emptySearch.limit_reached) "The no-result query reported truncation."

Assert-Throws { & $searchScript -Query "-exit" } "command-line option"
Assert-Throws { & $searchScript -Query '"-exit"' } "command-line option"
Assert-Throws { & $searchScript -Query "-exit" -Regex } "command-line option"
Assert-Throws { & $searchScript -Query '"unterminated' } "unmatched double quote"
Assert-Throws {
    & $searchScript -Query "README" -FilesOnly -FoldersOnly
} "cannot be used together"

$initializedStatus = & $initializeScript | ConvertFrom-Json
Assert-Condition $initializedStatus.ready "The initializer did not preserve the ready state."

Write-Output "Everything integration validation passed."
