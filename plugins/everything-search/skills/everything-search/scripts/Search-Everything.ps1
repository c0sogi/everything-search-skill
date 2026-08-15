[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Query = "",

    [ValidateRange(1, 200)]
    [int]$MaxResults = 20,

    [string]$Path,
    [string[]]$Extensions,

    [ValidateSet("Any", "File", "Folder")]
    [string]$ItemType = "Any",

    [datetime]$ModifiedAfter,
    [datetime]$ModifiedBefore,
    [long]$MinSizeBytes,
    [long]$MaxSizeBytes,

    [ValidateSet(
        "name-ascending",
        "name-descending",
        "path-ascending",
        "path-descending",
        "size-ascending",
        "size-descending",
        "extension-ascending",
        "extension-descending",
        "date-created-ascending",
        "date-created-descending",
        "date-modified-ascending",
        "date-modified-descending"
    )]
    [string]$Sort = "name-ascending",

    [ValidateSet("Compact", "Metadata", "Full")]
    [string]$OutputMode = "Compact",

    [switch]$FilesOnly,
    [switch]$FoldersOnly,
    [switch]$MatchPath,
    [switch]$MatchCase,
    [switch]$MatchWholeWord,
    [switch]$Regex,
    [string]$Instance,

    [ValidateRange(500, 30000)]
    [int]$TimeoutMilliseconds = 5000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Everything.Common.ps1")

if ($FilesOnly -and $FoldersOnly) {
    throw "FilesOnly and FoldersOnly cannot be used together."
}

$effectiveItemType = $ItemType
if ($FilesOnly) {
    if ($ItemType -eq "Folder") {
        throw "FilesOnly conflicts with ItemType Folder."
    }
    $effectiveItemType = "File"
}
if ($FoldersOnly) {
    if ($ItemType -eq "File") {
        throw "FoldersOnly conflicts with ItemType File."
    }
    $effectiveItemType = "Folder"
}

$structuredFilterNames = @("Extensions", "ModifiedAfter", "ModifiedBefore", "MinSizeBytes", "MaxSizeBytes")
if ($Regex) {
    if ([string]::IsNullOrWhiteSpace($Query)) {
        throw "Query is required when Regex is enabled."
    }
    Assert-EverythingQueryTokenSafe -Token $Query
    foreach ($filterName in $structuredFilterNames) {
        if ($PSBoundParameters.ContainsKey($filterName)) {
            throw "$filterName cannot be combined with Regex. Put the complete expression in Query or disable Regex."
        }
    }
    $searchTerms = @()
}
else {
    $termParameters = @{ Query = $Query }
    foreach ($filterName in $structuredFilterNames) {
        if ($PSBoundParameters.ContainsKey($filterName)) {
            $termParameters[$filterName] = $PSBoundParameters[$filterName]
        }
    }
    $searchTerms = @(New-EverythingSearchTerms @termParameters)
}

if (-not $Regex -and $searchTerms.Count -eq 0 -and [string]::IsNullOrWhiteSpace($Path)) {
    throw "Provide Query, Path, or at least one structured filter."
}

Assert-EverythingWindows
$esPath = Get-BundledEverythingEsPath
$null = Assert-BundledEverythingEsTrusted -EsPath $esPath
$readiness = Ensure-EverythingIpcReady `
    -EsPath $esPath `
    -Instance $Instance `
    -AutoStart `
    -StartupTimeoutMilliseconds $TimeoutMilliseconds

if (-not $readiness.ready) {
    New-EverythingErrorPayload -Diagnosis $readiness.diagnosis -Instance $Instance |
        ConvertTo-Json -Depth 6
    exit $readiness.exit_code
}

$arguments = [System.Collections.Generic.List[string]]::new()
foreach ($argument in @(Get-EverythingInstanceArguments -Instance $Instance)) {
    $arguments.Add($argument)
}
$arguments.Add("-json")
$arguments.Add("-date-format")
$arguments.Add("1")
$arguments.Add("-timeout")
$arguments.Add([string]$TimeoutMilliseconds)
$arguments.Add("-n")
$arguments.Add([string]($MaxResults + 1))
$arguments.Add("-sort")
$arguments.Add($Sort)
$arguments.Add("-name")
$arguments.Add("-path-column")
$arguments.Add("-attributes")

if ($OutputMode -in @("Metadata", "Full")) {
    $arguments.Add("-extension")
    $arguments.Add("-size")
    $arguments.Add("-size-format")
    $arguments.Add("1")
    $arguments.Add("-no-digit-grouping")
    $arguments.Add("-date-modified")
}
if ($OutputMode -eq "Full") {
    $arguments.Add("-date-created")
}

if (-not [string]::IsNullOrWhiteSpace($Path)) {
    $arguments.Add("-path")
    $arguments.Add($Path)
}
if ($effectiveItemType -eq "File") {
    $arguments.Add("/a-d")
}
elseif ($effectiveItemType -eq "Folder") {
    $arguments.Add("/ad")
}
if ($MatchPath) {
    $arguments.Add("-match-path")
}
if ($MatchCase) {
    $arguments.Add("-case")
}
if ($MatchWholeWord) {
    $arguments.Add("-whole-word")
}

if ($Regex) {
    $arguments.Add("-regex")
    $arguments.Add($Query)
}
else {
    foreach ($term in $searchTerms) {
        $arguments.Add($term)
    }
}

$search = Invoke-EverythingEs -EsPath $esPath -Arguments $arguments.ToArray()
$searchRetryUsed = $false
if ($search.ExitCode -eq 8) {
    Start-Sleep -Milliseconds 750
    $searchRetryUsed = $true
    $search = Invoke-EverythingEs -EsPath $esPath -Arguments $arguments.ToArray()
}

if ($search.ExitCode -ne 0) {
    $diagnosis = if ($search.ExitCode -eq 8) {
        Get-EverythingIpcDiagnosis -ExitCode $search.ExitCode -Instance $Instance
    }
    else {
        [pscustomobject]@{
            code = "search_failed"
            message = "Everything search failed (ES exit $($search.ExitCode)): $($search.Text)"
            recoverable = $false
            user_action_required = $true
            exit_code = $search.ExitCode
        }
    }

    New-EverythingErrorPayload -Diagnosis $diagnosis -Instance $Instance |
        ConvertTo-Json -Depth 6
    exit $search.ExitCode
}

try {
    $rawResults = if ([string]::IsNullOrWhiteSpace($search.Text)) {
        @()
    }
    else {
        @($search.Text | ConvertFrom-Json)
    }
}
catch {
    $diagnosis = [pscustomobject]@{
        code = "invalid_es_json"
        message = "Everything returned invalid JSON: $($_.Exception.Message)"
        recoverable = $false
        user_action_required = $true
        exit_code = 1
    }
    New-EverythingErrorPayload -Diagnosis $diagnosis -Instance $Instance |
        ConvertTo-Json -Depth 6
    exit 1
}

$results = @(
    foreach ($item in $rawResults) {
        $nameProperty = $item.PSObject.Properties["name"]
        $pathProperty = $item.PSObject.Properties["path"]
        $sizeProperty = $item.PSObject.Properties["size"]
        $dateCreatedProperty = $item.PSObject.Properties["date_created"]
        $dateModifiedProperty = $item.PSObject.Properties["date_modified"]
        $extensionProperty = $item.PSObject.Properties["extension"]
        $attributesProperty = $item.PSObject.Properties["attributes"]

        $name = if ($nameProperty) { [string]$nameProperty.Value } else { $null }
        $parentPath = if ($pathProperty) { [string]$pathProperty.Value } else { $null }
        $attributes = if ($attributesProperty) { [int64]$attributesProperty.Value } else { 0 }
        $fullPath = if ($parentPath -and $name) {
            Join-Path $parentPath $name
        }
        else {
            $name
        }

        $record = [ordered]@{
            full_path = $fullPath
            is_folder = ($attributes -band 16) -ne 0
        }

        if ($OutputMode -in @("Metadata", "Full")) {
            $record["name"] = $name
            $record["extension"] = if ($extensionProperty) { $extensionProperty.Value } else { $null }
            $record["size_bytes"] = if ($sizeProperty) { [int64]$sizeProperty.Value } else { $null }
            $record["date_modified"] = if ($dateModifiedProperty) { $dateModifiedProperty.Value } else { $null }
        }
        if ($OutputMode -eq "Full") {
            $record["path"] = $parentPath
            $record["date_created"] = if ($dateCreatedProperty) { $dateCreatedProperty.Value } else { $null }
            $record["attributes"] = $attributes
        }

        [pscustomobject]$record
    }
)

$limitReached = $results.Count -gt $MaxResults
if ($limitReached) {
    $results = @($results | Select-Object -First $MaxResults)
}

$response = [ordered]@{
    ok = $true
    returned = $results.Count
    limit_reached = $limitReached
    results = $results
}

if ($readiness.ipc_retry_used -or $readiness.client_started -or $searchRetryUsed) {
    $response["recovered"] = $true
}

[pscustomobject]$response | ConvertTo-Json -Depth 6
