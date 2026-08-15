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

$splitTerms = @(Split-EverythingQuery -Query 'report_2026 ext:pdf;docx')
Assert-Condition ($splitTerms.Count -eq 2) "Independent Everything terms were collapsed."
Assert-Condition ($splitTerms[0] -eq "report_2026") "The basename term changed unexpectedly."
Assert-Condition ($splitTerms[1] -eq "ext:pdf;docx") "The extension term changed unexpectedly."

$unicodePhrase = -join @([char]0xBD84, [char]0xC11D, [char]0x20, [char]0xACB0, [char]0xACFC)
$quotedUnicodePhrase = '"' + $unicodePhrase + '"'

$terms = @(
    New-EverythingSearchTerms `
        -Query "$quotedUnicodePhrase report" `
        -Extensions ".PDF", "docx", "pdf" `
        -ModifiedAfter ([datetime]"2026-08-01T12:30:00") `
        -ModifiedBefore ([datetime]"2026-08-15T18:00:00") `
        -MinSizeBytes 1024 `
        -MaxSizeBytes 1048576
)

$expectedTerms = @(
    $quotedUnicodePhrase,
    "report",
    "ext:PDF;docx",
    "dm:>=2026-08-01T12:30:00",
    "dm:<=2026-08-15T18:00:00",
    "size:>=1024",
    "size:<=1048576"
)
Assert-Condition ($terms.Count -eq $expectedTerms.Count) "Structured search produced an unexpected term count."
for ($index = 0; $index -lt $expectedTerms.Count; $index++) {
    Assert-Condition ($terms[$index] -eq $expectedTerms[$index]) "Unexpected term at index ${index}: '$($terms[$index])'."
}

$instanceArguments = @(Get-EverythingInstanceArguments -Instance "Research Index")
Assert-Condition ($instanceArguments.Count -eq 2) "Named-instance arguments have an unexpected shape."
Assert-Condition ($instanceArguments[0] -eq "-instance") "Named-instance switch is missing."
Assert-Condition ($instanceArguments[1] -eq "Research Index") "Named-instance value changed unexpectedly."

$settingsCandidates = @(
    Get-EverythingSettingsFileCandidates `
        -Instance "Research Index" `
        -ExecutablePaths @("C:\Tools\Everything.exe")
)
Assert-Condition ($settingsCandidates -contains "C:\Tools\Everything-RESEARCH INDEX.ini") "Uppercase named-instance settings path is missing."
Assert-Condition ($settingsCandidates -contains "C:\Tools\Everything-Research Index.ini") "Exact-case named-instance settings path is missing."
Assert-Condition ($settingsCandidates -notcontains "C:\Tools\Everything.ini") "Named-instance diagnosis must not fall back to unnamed-instance settings."

Assert-Throws { Split-EverythingQuery -Query '"unterminated' } "unmatched double quote"
Assert-Throws { New-EverythingSearchTerms -Query "-exit" } "command-line option"
Assert-Throws { New-EverythingSearchTerms -Query '"-exit"' } "command-line option"
Assert-Throws { New-EverythingSearchTerms -Extensions "bad;ext" } "invalid character"
Assert-Throws {
    New-EverythingSearchTerms `
        -ModifiedAfter ([datetime]"2026-08-15") `
        -ModifiedBefore ([datetime]"2026-08-01")
} "ModifiedAfter"
Assert-Throws { New-EverythingSearchTerms -MinSizeBytes 20 -MaxSizeBytes 10 } "MinSizeBytes"
Assert-Throws { Get-EverythingInstanceArguments -Instance 'bad"instance' } "quotes"

Write-Output "Query construction validation passed."
