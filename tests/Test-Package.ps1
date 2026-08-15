[CmdletBinding()]
param(
    [switch]$RequireValidSignature
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot "plugins\everything-search"
$skillRoot = Join-Path $pluginRoot "skills\everything-search"
$assetsRoot = Join-Path $skillRoot "assets\es"

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

$requiredPaths = @(
    ".agents\plugins\marketplace.json",
    ".github\workflows\test.yml",
    "plugins\everything-search\.codex-plugin\plugin.json",
    "plugins\everything-search\skills\everything-search\SKILL.md",
    "plugins\everything-search\skills\everything-search\agents\openai.yaml",
    "plugins\everything-search\skills\everything-search\references\search-syntax.md",
    "plugins\everything-search\skills\everything-search\scripts\Everything.Common.ps1",
    "plugins\everything-search\skills\everything-search\scripts\Get-EverythingStatus.ps1",
    "plugins\everything-search\skills\everything-search\scripts\Initialize-Everything.ps1",
    "plugins\everything-search\skills\everything-search\scripts\Search-Everything.ps1",
    "plugins\everything-search\skills\everything-search\scripts\Get-FileIdentity.ps1",
    "plugins\everything-search\skills\everything-search\assets\es\manifest.json",
    "plugins\everything-search\skills\everything-search\assets\es\LICENSE-voidtools-ES.txt",
    "plugins\everything-search\skills\everything-search\assets\es\win-x64\es.exe",
    "plugins\everything-search\skills\everything-search\assets\es\win-arm64\es.exe",
    "tests\Test-Package.ps1",
    "tests\Test-QueryConstruction.ps1",
    "tests\Test-IpcRecovery.ps1",
    "tests\Test-Integration.ps1",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md"
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repoRoot $relativePath
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "Required file is missing: $relativePath"
}

$marketplace = Get-Content -LiteralPath (Join-Path $repoRoot ".agents\plugins\marketplace.json") -Raw |
    ConvertFrom-Json
$plugin = Get-Content -LiteralPath (Join-Path $pluginRoot ".codex-plugin\plugin.json") -Raw |
    ConvertFrom-Json
$assetManifest = Get-Content -LiteralPath (Join-Path $assetsRoot "manifest.json") -Raw |
    ConvertFrom-Json

Assert-Condition ($marketplace.name -eq "everything-search-skill") "Unexpected marketplace name."
Assert-Condition ($marketplace.plugins.Count -eq 1) "Marketplace must contain exactly one plugin."
Assert-Condition ($marketplace.plugins[0].name -eq "everything-search") "Marketplace plugin name does not match."
Assert-Condition ($plugin.name -eq "everything-search") "Unexpected plugin name."
Assert-Condition ($plugin.version -eq "0.2.0") "Unexpected plugin version."
Assert-Condition ($assetManifest.version -eq "1.1.0.37") "Unexpected bundled ES version."

$skillText = Get-Content -LiteralPath (Join-Path $skillRoot "SKILL.md") -Raw
Assert-Condition ($skillText -match "(?m)^name:\s*everything-search\s*$") "SKILL.md name is missing or incorrect."
Assert-Condition ($skillText -match "(?m)^description:\s*\S") "SKILL.md description is missing."
Assert-Condition ($skillText -match "MaxResults.*20") "SKILL.md does not describe the bounded default result limit."

$searchText = Get-Content -LiteralPath (Join-Path $skillRoot "scripts\Search-Everything.ps1") -Raw
Assert-Condition ($searchText -match '\[int\]\$MaxResults\s*=\s*20') "Search default MaxResults is not 20."
Assert-Condition ($searchText -match '\[string\]\$OutputMode\s*=\s*"Compact"') "Search default OutputMode is not Compact."
Assert-Condition ($searchText -match 'Ensure-EverythingIpcReady') "Search does not own its readiness workflow."
Assert-Condition ($searchText -match '"-size-format"') "Metadata output does not force byte-sized numeric values."
Assert-Condition ($searchText -match '"-no-digit-grouping"') "Metadata output does not disable numeric digit grouping."

$textFiles = @(
    Get-ChildItem -LiteralPath $pluginRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".md", ".json", ".yaml", ".yml", ".ps1") }
)
$todoHits = @($textFiles | Select-String -Pattern "[TODO:" -SimpleMatch)
Assert-Condition ($todoHits.Count -eq 0) "Unresolved scaffold TODO found in plugin files."

$scriptFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $skillRoot "scripts") -Filter "*.ps1" -File
    Get-ChildItem -LiteralPath (Join-Path $repoRoot "tests") -Filter "*.ps1" -File
)
Assert-Condition ($scriptFiles.Count -ge 9) "Expected PowerShell scripts were not found."
foreach ($scriptFile in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Assert-Condition ($parseErrors.Count -eq 0) "PowerShell parse error in $($scriptFile.Name): $($parseErrors -join '; ')"
}

$binaryKeys = @("win-x64/es.exe", "win-arm64/es.exe")
foreach ($binaryKey in $binaryKeys) {
    $recordProperty = $assetManifest.files.PSObject.Properties[$binaryKey]
    Assert-Condition ($null -ne $recordProperty) "Manifest entry is missing: $binaryKey"

    $binaryPath = Join-Path $assetsRoot ($binaryKey -replace "/", "\")
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $binaryPath).Hash.ToLowerInvariant()
    $expectedHash = ([string]$recordProperty.Value.sha256).ToLowerInvariant()
    Assert-Condition ($actualHash -eq $expectedHash) "SHA256 mismatch for $binaryKey."

    $signature = Get-AuthenticodeSignature -LiteralPath $binaryPath
    $signerSubject = if ($signature.SignerCertificate) {
        [string]$signature.SignerCertificate.Subject
    }
    else {
        ""
    }
    Assert-Condition ($signerSubject -like "*voidtools PTY LTD*") "Unexpected or missing signer for $binaryKey."
    if ($RequireValidSignature) {
        Assert-Condition (
            $signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid
        ) "Authenticode signature is not valid for ${binaryKey}: $($signature.Status)"
    }
}

$x64EsPath = Join-Path $assetsRoot "win-x64\es.exe"
$versionOutput = @(& $x64EsPath -version 2>&1)
$versionExitCode = $LASTEXITCODE
$versionText = (($versionOutput | ForEach-Object { [string]$_ }) -join "`n").Trim()
Assert-Condition ($versionExitCode -eq 0) "Bundled x64 ES version command failed."
Assert-Condition ($versionText -eq "1.1.0.37") "Bundled x64 ES reported unexpected version '$versionText'."

Write-Output "Package validation passed."
