function Assert-EverythingWindows {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "Everything Search requires a local Windows host."
    }
}

function Get-EverythingPlatform {
    Assert-EverythingWindows

    $architecture = $null
    try {
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    catch {
        $architecture = if ($env:PROCESSOR_ARCHITEW6432) {
            $env:PROCESSOR_ARCHITEW6432
        }
        else {
            $env:PROCESSOR_ARCHITECTURE
        }
    }

    switch -Regex ($architecture) {
        '^(X64|AMD64)$' { return "win-x64" }
        '^ARM64$' { return "win-arm64" }
        default {
            throw "Unsupported Windows architecture '$architecture'. This release supports x64 and ARM64."
        }
    }
}

function Get-BundledEverythingEsPath {
    $platform = Get-EverythingPlatform
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $path = Join-Path $skillRoot "assets\es\$platform\es.exe"

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Bundled es.exe was not found at '$path'. Reinstall the skill."
    }

    return (Resolve-Path -LiteralPath $path).Path
}

function Get-BundledEverythingEsTrust {
    param(
        [string]$EsPath
    )

    if (-not $EsPath) {
        $EsPath = Get-BundledEverythingEsPath
    }

    $platform = Get-EverythingPlatform
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $manifestPath = Join-Path $skillRoot "assets\es\manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Bundled ES manifest was not found at '$manifestPath'. Reinstall the skill."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestKey = "$platform/es.exe"
    $recordProperty = $manifest.files.PSObject.Properties[$manifestKey]
    if (-not $recordProperty) {
        throw "Bundled ES manifest has no entry for '$manifestKey'. Reinstall the skill."
    }

    $record = $recordProperty.Value
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $EsPath).Hash.ToLowerInvariant()
    $expectedHash = ([string]$record.sha256).ToLowerInvariant()
    $signature = Get-AuthenticodeSignature -LiteralPath $EsPath
    $signerSubject = if ($signature.SignerCertificate) {
        [string]$signature.SignerCertificate.Subject
    }
    else {
        $null
    }
    $signatureValid = $signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid
    $signerMatches = $signerSubject -like "*$([string]$record.authenticode_signer)*"
    $hashMatches = $actualHash -eq $expectedHash

    return [pscustomobject]@{
        trusted = $hashMatches -and $signatureValid -and $signerMatches
        hash_matches_manifest = $hashMatches
        sha256 = $actualHash
        expected_sha256 = $expectedHash
        signature_status = [string]$signature.Status
        signature_valid = $signatureValid
        signer = $signerSubject
        expected_signer = [string]$record.authenticode_signer
        signer_matches = $signerMatches
    }
}

function Assert-BundledEverythingEsTrusted {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EsPath
    )

    $trust = Get-BundledEverythingEsTrust -EsPath $EsPath
    if (-not $trust.trusted) {
        throw "Bundled es.exe failed its hash or Authenticode verification. Reinstall the Everything Search skill."
    }

    return $trust
}

function Invoke-EverythingEs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EsPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $savedEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    }
    catch {
        # Continue with the host encoding when no console is attached.
    }

    try {
        $output = @(& $EsPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        try {
            [Console]::OutputEncoding = $savedEncoding
        }
        catch {
            # Restoring the encoding is best-effort for non-console hosts.
        }
    }

    $text = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = $text
    }
}

function Split-EverythingQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $insideQuotes = $false

    foreach ($character in $Query.ToCharArray()) {
        if ($character -eq '"') {
            $insideQuotes = -not $insideQuotes
            [void]$current.Append($character)
            continue
        }

        if ([char]::IsWhiteSpace($character) -and -not $insideQuotes) {
            if ($current.Length -gt 0) {
                $tokens.Add($current.ToString())
                [void]$current.Clear()
            }
            continue
        }

        [void]$current.Append($character)
    }

    if ($insideQuotes) {
        throw "The Everything query contains an unmatched double quote."
    }

    if ($current.Length -gt 0) {
        $tokens.Add($current.ToString())
    }

    return $tokens.ToArray()
}

function Get-EverythingExecutableCandidates {
    Assert-EverythingWindows

    $candidates = [System.Collections.Generic.List[string]]::new()
    $commonPaths = @(
        "$env:ProgramFiles\Everything\Everything.exe",
        "${env:ProgramFiles(x86)}\Everything\Everything.exe",
        "$env:LOCALAPPDATA\Everything\Everything.exe",
        "$env:LOCALAPPDATA\Programs\Everything\Everything.exe",
        "$env:ProgramFiles\Everything 1.5a\Everything.exe",
        "$env:USERPROFILE\scoop\apps\everything\current\Everything.exe"
    )

    foreach ($path in $commonPaths) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $candidates.Add($path)
        }
    }

    $pathCommand = Get-Command Everything.exe -ErrorAction SilentlyContinue
    if ($pathCommand -and $pathCommand.Source -and (Test-Path -LiteralPath $pathCommand.Source -PathType Leaf)) {
        $candidates.Add($pathCommand.Source)
    }

    $uninstallRoots = @(
        "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($entry in @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue)) {
        $displayNameProperty = $entry.PSObject.Properties["DisplayName"]
        if (-not $displayNameProperty -or [string]$displayNameProperty.Value -notlike "Everything*") {
            continue
        }

        $installLocationProperty = $entry.PSObject.Properties["InstallLocation"]
        if ($installLocationProperty -and $installLocationProperty.Value) {
            $path = Join-Path ([string]$installLocationProperty.Value) "Everything.exe"
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $candidates.Add($path)
            }
        }
    }

    foreach ($process in @(Get-Process -Name Everything -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -and (Test-Path -LiteralPath $process.Path -PathType Leaf)) {
                $candidates.Add($process.Path)
            }
        }
        catch {
            # Service-owned processes may hide their executable path.
        }
    }

    return @(
        $candidates |
            ForEach-Object { (Resolve-Path -LiteralPath $_).Path } |
            Sort-Object -Unique
    )
}
