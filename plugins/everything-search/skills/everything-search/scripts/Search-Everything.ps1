[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [ValidateRange(1, 200)]
    [int]$MaxResults = 50,

    [string]$Path,

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

    [switch]$FilesOnly,
    [switch]$FoldersOnly,
    [switch]$MatchPath,
    [switch]$MatchCase,
    [switch]$MatchWholeWord,
    [switch]$Regex,
    [string]$Instance
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Everything.Common.ps1")

if ($FilesOnly -and $FoldersOnly) {
    throw "FilesOnly and FoldersOnly cannot be used together."
}

Assert-EverythingWindows
$esPath = Get-BundledEverythingEsPath
$null = Assert-BundledEverythingEsTrusted -EsPath $esPath
$connection = Invoke-EverythingEs -EsPath $esPath -Arguments @("-get-everything-version")
if ($connection.ExitCode -ne 0) {
    throw "Everything IPC is unavailable (ES exit $($connection.ExitCode)). Run Get-EverythingStatus.ps1 and start or install Everything."
}

$arguments = [System.Collections.Generic.List[string]]::new()
$arguments.Add("-json")
$arguments.Add("-date-format")
$arguments.Add("1")
$arguments.Add("-n")
$arguments.Add([string]($MaxResults + 1))
$arguments.Add("-sort")
$arguments.Add($Sort)
$arguments.Add("-name")
$arguments.Add("-path-column")
$arguments.Add("-size")
$arguments.Add("-date-modified")
$arguments.Add("-extension")
$arguments.Add("-attributes")

if ($Path) {
    $arguments.Add("-path")
    $arguments.Add($Path)
}
if ($FilesOnly) {
    $arguments.Add("/a-d")
}
if ($FoldersOnly) {
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
if ($Instance) {
    $arguments.Add("-instance")
    $arguments.Add($Instance)
}

if ($Regex) {
    if ($Query.TrimStart() -match "^[/-]") {
        throw "The regular expression looks like an ES command-line option."
    }
    $arguments.Add("-regex")
    $arguments.Add($Query)
}
else {
    $queryTokens = @(Split-EverythingQuery -Query $Query)
    if ($queryTokens.Count -eq 0) {
        throw "The Everything query is empty."
    }

    foreach ($token in $queryTokens) {
        if ($token.TrimStart('"') -match "^[/-]") {
            throw "Query term '$token' looks like an ES command-line option. Express exclusions with ! or use a structured script parameter."
        }
        $arguments.Add($token)
    }
}

$search = Invoke-EverythingEs -EsPath $esPath -Arguments $arguments.ToArray()
if ($search.ExitCode -ne 0) {
    throw "Everything search failed (ES exit $($search.ExitCode)): $($search.Text)"
}

$rawResults = if ([string]::IsNullOrWhiteSpace($search.Text)) {
    @()
}
else {
    @($search.Text | ConvertFrom-Json)
}

$results = @(
    foreach ($item in $rawResults) {
        $nameProperty = $item.PSObject.Properties["name"]
        $pathProperty = $item.PSObject.Properties["path"]
        $sizeProperty = $item.PSObject.Properties["size"]
        $dateProperty = $item.PSObject.Properties["date_modified"]
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

        [pscustomobject]@{
            name = $name
            path = $parentPath
            full_path = $fullPath
            extension = if ($extensionProperty) { $extensionProperty.Value } else { $null }
            size_bytes = if ($sizeProperty) { [int64]$sizeProperty.Value } else { $null }
            date_modified = if ($dateProperty) { $dateProperty.Value } else { $null }
            is_folder = ($attributes -band 16) -ne 0
            attributes = $attributes
        }
    }
)

$limitReached = $results.Count -gt $MaxResults
if ($limitReached) {
    $results = @($results | Select-Object -First $MaxResults)
}

[pscustomobject]@{
    query = $Query
    path = $Path
    sort = $Sort
    max_results = $MaxResults
    returned = $results.Count
    limit_reached = $limitReached
    everything_version = $connection.Text
    es_version = (Invoke-EverythingEs -EsPath $esPath -Arguments @("-version")).Text
    results = $results
} | ConvertTo-Json -Depth 6
