[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot "plugins\everything-search\skills\everything-search\scripts"
$statusScript = Join-Path $scriptRoot "Get-EverythingStatus.ps1"
$searchScript = Join-Path $scriptRoot "Search-Everything.ps1"
$initializeScript = Join-Path $scriptRoot "Initialize-Everything.ps1"
$identityScript = Join-Path $scriptRoot "Get-FileIdentity.ps1"

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

    $caught = $null
    try {
        & $Action
    }
    catch {
        $caught = $_
    }

    if ($null -eq $caught) {
        throw "Expected an error matching '$MessagePattern', but no error was raised."
    }
    if ($caught.Exception.Message -notmatch $MessagePattern) {
        throw $caught
    }
}

# Search is the normal entry point and performs its own readiness handling.
$readmePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot "README.md")).Path
$readmeSearch = & $searchScript `
    -Query "README.md" `
    -Extensions md `
    -Path $repoRoot `
    -ItemType File |
    ConvertFrom-Json
Assert-Condition $readmeSearch.ok "The compact search did not report success."
Assert-Condition ($readmeSearch.returned -eq 1) "Expected exactly one repository README result."
$compactResult = @($readmeSearch.results)[0]
Assert-Condition ($compactResult.full_path -eq $readmePath) "The repository README path was not returned."
Assert-Condition (-not $compactResult.is_folder) "The repository README was reported as a folder."
Assert-Condition ($null -eq $compactResult.PSObject.Properties["name"]) "Compact mode returned unused metadata."

$metadataSearch = & $searchScript `
    -Query "README.md" `
    -Path $repoRoot `
    -ItemType File `
    -OutputMode Metadata |
    ConvertFrom-Json
$metadataResult = @($metadataSearch.results)[0]
Assert-Condition ($metadataResult.name -eq "README.md") "Metadata mode did not return the file name."
Assert-Condition ($null -ne $metadataResult.PSObject.Properties["size_bytes"]) "Metadata mode did not return size_bytes."
Assert-Condition ($null -ne $metadataResult.PSObject.Properties["date_modified"]) "Metadata mode did not return date_modified."

$limitedSearch = & $searchScript `
    -Extensions md `
    -Path $repoRoot `
    -ItemType File `
    -MaxResults 1 |
    ConvertFrom-Json
Assert-Condition ($limitedSearch.returned -eq 1) "The limited search returned an unexpected count."
Assert-Condition $limitedSearch.limit_reached "The limited search did not report truncation."

$emptySearch = & $searchScript `
    -Query "codex-no-such-file-7f1df8a7" `
    -Path $repoRoot |
    ConvertFrom-Json
Assert-Condition ($emptySearch.returned -eq 0) "The no-result query unexpectedly matched a path."
Assert-Condition (-not $emptySearch.limit_reached) "The no-result query reported truncation."

$identity = & $identityScript -Path $readmePath -IncludeSha256 | ConvertFrom-Json
Assert-Condition ($identity.returned -eq 1) "File identity returned an unexpected count."
$identityResult = @($identity.results)[0]
Assert-Condition $identityResult.exists "File identity did not find README.md."
Assert-Condition ($identityResult.sha256 -match '^[0-9a-f]{64}$') "File identity returned an invalid SHA-256 value."

Assert-Throws { & $searchScript -Query "-exit" } "command-line option"
Assert-Throws { & $searchScript -Query '"-exit"' } "command-line option"
Assert-Throws { & $searchScript -Query "-exit" -Regex } "command-line option"
Assert-Throws { & $searchScript -Query '"unterminated' } "unmatched double quote"
Assert-Throws { & $searchScript -Query "README" -FilesOnly -FoldersOnly } "cannot be used together"
Assert-Throws { & $searchScript -Query "README" -Regex -Extensions md } "cannot be combined with Regex"
Assert-Throws { & $searchScript -Query "README" -FilesOnly -ItemType Folder } "conflicts"
Assert-Throws { & $searchScript } "Provide Query, Path"

$status = & $statusScript | ConvertFrom-Json
Assert-Condition $status.ready "Everything is not ready after the search."
Assert-Condition ($status.es.version -eq "1.1.0.37") "Unexpected bundled ES version."

$initializedStatus = & $initializeScript | ConvertFrom-Json
Assert-Condition $initializedStatus.ready "The initializer did not preserve the ready state."

Write-Output "Everything integration validation passed."
