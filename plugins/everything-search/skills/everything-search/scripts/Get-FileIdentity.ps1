[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias("FullName", "FullPath", "full_path")]
    [string[]]$Path,

    [switch]$IncludeSha256,

    [ValidateRange(1, 20)]
    [int]$MaxItems = 10
)

begin {
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = "Stop"
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
}

process {
    foreach ($candidate in $Path) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            throw "Path cannot contain an empty value."
        }
        if ($candidatePaths.Count -ge $MaxItems) {
            throw "Get-FileIdentity accepts at most $MaxItems paths per invocation."
        }
        $candidatePaths.Add($candidate)
    }
}

end {
    $results = @(
        foreach ($candidate in $candidatePaths) {
            if (-not (Test-Path -LiteralPath $candidate)) {
                [pscustomobject]@{
                    full_path = $candidate
                    exists = $false
                }
                continue
            }

            $item = Get-Item -LiteralPath $candidate -Force
            $record = [ordered]@{
                full_path = $item.FullName
                exists = $true
                is_folder = $item.PSIsContainer
                size_bytes = if ($item.PSIsContainer) { $null } else { [int64]$item.Length }
                last_write_time = $item.LastWriteTime.ToString("o")
            }

            if ($IncludeSha256 -and -not $item.PSIsContainer) {
                $record["sha256"] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }

            [pscustomobject]$record
        }
    )

    [pscustomobject]@{
        returned = $results.Count
        sha256_included = [bool]$IncludeSha256
        results = $results
    } | ConvertTo-Json -Depth 5
}
