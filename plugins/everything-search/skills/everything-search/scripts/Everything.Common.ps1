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

function Assert-EverythingQueryTokenSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    if ($Token.TrimStart().TrimStart('"') -match '^[/-]') {
        throw "Query term '$Token' looks like an ES command-line option. Express exclusions with ! or use a structured script parameter."
    }
}

function New-EverythingSearchTerms {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Query,

        [string[]]$Extensions,
        [datetime]$ModifiedAfter,
        [datetime]$ModifiedBefore,
        [long]$MinSizeBytes,
        [long]$MaxSizeBytes
    )

    if ($PSBoundParameters.ContainsKey("ModifiedAfter") -and
        $PSBoundParameters.ContainsKey("ModifiedBefore") -and
        $ModifiedAfter -gt $ModifiedBefore) {
        throw "ModifiedAfter cannot be later than ModifiedBefore."
    }

    if ($PSBoundParameters.ContainsKey("MinSizeBytes") -and $MinSizeBytes -lt 0) {
        throw "MinSizeBytes cannot be negative."
    }
    if ($PSBoundParameters.ContainsKey("MaxSizeBytes") -and $MaxSizeBytes -lt 0) {
        throw "MaxSizeBytes cannot be negative."
    }
    if ($PSBoundParameters.ContainsKey("MinSizeBytes") -and
        $PSBoundParameters.ContainsKey("MaxSizeBytes") -and
        $MinSizeBytes -gt $MaxSizeBytes) {
        throw "MinSizeBytes cannot be greater than MaxSizeBytes."
    }

    $terms = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        foreach ($token in @(Split-EverythingQuery -Query $Query)) {
            Assert-EverythingQueryTokenSafe -Token $token
            $terms.Add($token)
        }
    }

    if ($Extensions) {
        $normalizedExtensions = [System.Collections.Generic.List[string]]::new()
        foreach ($extension in $Extensions) {
            $normalized = ([string]$extension).Trim().TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($normalized)) {
                throw "Extensions cannot contain an empty value."
            }
            if ($normalized -match '[\\/:*?"<>|;\s]') {
                throw "Extension '$extension' contains an invalid character."
            }
            if ($normalizedExtensions -notcontains $normalized) {
                $normalizedExtensions.Add($normalized)
            }
        }
        $terms.Add("ext:$($normalizedExtensions -join ';')")
    }

    $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($PSBoundParameters.ContainsKey("ModifiedAfter")) {
        $terms.Add("dm:>=$($ModifiedAfter.ToString('yyyy-MM-ddTHH:mm:ss', $invariantCulture))")
    }
    if ($PSBoundParameters.ContainsKey("ModifiedBefore")) {
        $terms.Add("dm:<=$($ModifiedBefore.ToString('yyyy-MM-ddTHH:mm:ss', $invariantCulture))")
    }
    if ($PSBoundParameters.ContainsKey("MinSizeBytes")) {
        $terms.Add("size:>=$MinSizeBytes")
    }
    if ($PSBoundParameters.ContainsKey("MaxSizeBytes")) {
        $terms.Add("size:<=$MaxSizeBytes")
    }

    return $terms.ToArray()
}

function Get-EverythingInstanceArguments {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance
    )

    if ([string]::IsNullOrWhiteSpace($Instance)) {
        return @()
    }
    if ($Instance -match '["\r\n]') {
        throw "Instance cannot contain quotes or line breaks."
    }

    return @("-instance", $Instance)
}

function Invoke-EverythingIpcProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EsPath,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(Get-EverythingInstanceArguments -Instance $Instance)) {
        $arguments.Add($argument)
    }
    $arguments.Add("-get-everything-version")

    return Invoke-EverythingEs -EsPath $EsPath -Arguments $arguments.ToArray()
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

    $seen = @{}
    $resolvedCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        try {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
        }
        catch {
            continue
        }
        if (-not $seen.ContainsKey($resolved)) {
            $seen[$resolved] = $true
            $resolvedCandidates.Add($resolved)
        }
    }

    return $resolvedCandidates.ToArray()
}

function Test-CurrentProcessElevated {
    Assert-EverythingWindows

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-EverythingSettingsFileCandidates {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance,

        [string[]]$ExecutablePaths
    )

    $fileNames = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Instance)) {
        $fileNames.Add("Everything.ini")
    }
    else {
        $fileNames.Add("Everything-$($Instance.ToUpperInvariant()).ini")
        $fileNames.Add("Everything-$Instance.ini")
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    if ($env:APPDATA) {
        foreach ($fileName in $fileNames) {
            $paths.Add((Join-Path (Join-Path $env:APPDATA "Everything") $fileName))
        }
    }

    foreach ($executablePath in @($ExecutablePaths)) {
        if ([string]::IsNullOrWhiteSpace($executablePath)) {
            continue
        }
        $directory = Split-Path -Parent $executablePath
        foreach ($fileName in $fileNames) {
            $paths.Add((Join-Path $directory $fileName))
        }
    }

    return @($paths | Select-Object -Unique)
}

function Get-EverythingIniSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance,

        [string[]]$ExecutablePaths
    )

    $pattern = '^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*)\s*$'
    foreach ($path in @(Get-EverythingSettingsFileCandidates -Instance $Instance -ExecutablePaths $ExecutablePaths)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $match = Select-String -LiteralPath $path -Pattern $pattern | Select-Object -First 1
        if ($match) {
            return $match.Matches[0].Groups[1].Value.Trim()
        }
    }

    return $null
}

function Get-EverythingIpcDiagnosis {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance
    )

    if ($ExitCode -eq 0) {
        return [pscustomobject]@{
            code = "ready"
            message = "Everything IPC is ready."
            recoverable = $true
            user_action_required = $false
            start_recommended = $false
            exit_code = 0
        }
    }

    if ($ExitCode -notin @(7, 8)) {
        return [pscustomobject]@{
            code = "es_probe_failed"
            message = "The bundled ES client failed during its IPC probe with exit code $ExitCode."
            recoverable = $false
            user_action_required = $true
            start_recommended = $false
            exit_code = $ExitCode
        }
    }

    $processes = @(Get-Process -Name Everything -ErrorAction SilentlyContinue)
    $executablePaths = @(Get-EverythingExecutableCandidates)
    $installed = ($processes.Count -gt 0) -or ($executablePaths.Count -gt 0)

    if (-not $installed) {
        return [pscustomobject]@{
            code = "everything_not_installed"
            message = "Everything is not installed. Install it only after explicit user approval."
            recoverable = $false
            user_action_required = $true
            start_recommended = $false
            exit_code = $ExitCode
        }
    }

    $currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $interactiveProcesses = @($processes | Where-Object { $_.SessionId -eq $currentSession })
    $runAsAdmin = Get-EverythingIniSetting -Name "run_as_admin" -Instance $Instance -ExecutablePaths $executablePaths
    $isElevated = Test-CurrentProcessElevated

    if ($runAsAdmin -eq "1" -and -not $isElevated) {
        return [pscustomobject]@{
            code = "ipc_elevation_mismatch"
            message = "Everything is configured to run elevated while the current shell is not. Run both at the same elevation level."
            recoverable = $false
            user_action_required = $true
            start_recommended = $false
            exit_code = $ExitCode
        }
    }

    if ($interactiveProcesses.Count -eq 0) {
        $code = if ([string]::IsNullOrWhiteSpace($Instance)) { "everything_not_running" } else { "everything_instance_not_running" }
        $message = if ([string]::IsNullOrWhiteSpace($Instance)) {
            "Everything is installed but no interactive client is running in this session."
        }
        else {
            "Everything instance '$Instance' is not available in this session."
        }
        return [pscustomobject]@{
            code = $code
            message = $message
            recoverable = $true
            user_action_required = $false
            start_recommended = $true
            exit_code = $ExitCode
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Instance)) {
        return [pscustomobject]@{
            code = "everything_instance_unavailable"
            message = "Everything instance '$Instance' is not responding over IPC."
            recoverable = $true
            user_action_required = $false
            start_recommended = $true
            exit_code = $ExitCode
        }
    }

    return [pscustomobject]@{
        code = "ipc_unavailable"
        message = "The unnamed Everything instance is not responding over IPC."
        recoverable = $true
        user_action_required = $false
        start_recommended = $true
        exit_code = $ExitCode
    }
}

function Start-EverythingClient {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance
    )

    $candidates = @(Get-EverythingExecutableCandidates)
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            started = $false
            path = $null
            error = "Everything.exe could not be located."
        }
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Instance)) {
        if ($Instance -match '["\r\n]') {
            throw "Instance cannot contain quotes or line breaks."
        }
        $arguments.Add("-instance")
        $arguments.Add('"' + $Instance + '"')
    }
    $arguments.Add("-startup")

    try {
        $process = Start-Process `
            -FilePath $candidates[0] `
            -ArgumentList $arguments.ToArray() `
            -WindowStyle Minimized `
            -PassThru

        return [pscustomobject]@{
            started = $true
            path = $candidates[0]
            process_id = $process.Id
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            started = $false
            path = $candidates[0]
            process_id = $null
            error = $_.Exception.Message
        }
    }
}

function Wait-EverythingIpc {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EsPath,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance,

        [ValidateRange(500, 30000)]
        [int]$TimeoutMilliseconds = 5000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $lastProbe = $null
    do {
        $lastProbe = Invoke-EverythingIpcProbe -EsPath $EsPath -Instance $Instance
        if ($lastProbe.ExitCode -eq 0) {
            return $lastProbe
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return $lastProbe
}

function Ensure-EverythingIpcReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EsPath,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance,

        [switch]$AutoStart,

        [ValidateRange(100, 5000)]
        [int]$RetryDelayMilliseconds = 750,

        [ValidateRange(500, 30000)]
        [int]$StartupTimeoutMilliseconds = 5000
    )

    $probe = Invoke-EverythingIpcProbe -EsPath $EsPath -Instance $Instance
    if ($probe.ExitCode -eq 0) {
        return [pscustomobject]@{
            ready = $true
            version = $probe.Text
            ipc_retry_used = $false
            client_started = $false
            diagnosis = $null
            exit_code = 0
        }
    }

    $ipcRetryUsed = $false
    if ($probe.ExitCode -eq 8) {
        Start-Sleep -Milliseconds $RetryDelayMilliseconds
        $ipcRetryUsed = $true
        $probe = Invoke-EverythingIpcProbe -EsPath $EsPath -Instance $Instance
        if ($probe.ExitCode -eq 0) {
            return [pscustomobject]@{
                ready = $true
                version = $probe.Text
                ipc_retry_used = $true
                client_started = $false
                diagnosis = $null
                exit_code = 0
            }
        }
    }

    $diagnosis = Get-EverythingIpcDiagnosis -ExitCode $probe.ExitCode -Instance $Instance
    if ($AutoStart -and $diagnosis.start_recommended) {
        $startResult = Start-EverythingClient -Instance $Instance
        if ($startResult.started) {
            $probe = Wait-EverythingIpc `
                -EsPath $EsPath `
                -Instance $Instance `
                -TimeoutMilliseconds $StartupTimeoutMilliseconds

            if ($probe.ExitCode -eq 0) {
                return [pscustomobject]@{
                    ready = $true
                    version = $probe.Text
                    ipc_retry_used = $ipcRetryUsed
                    client_started = $true
                    diagnosis = $null
                    exit_code = 0
                }
            }
            $targetDescription = if ([string]::IsNullOrWhiteSpace($Instance)) {
                "The unnamed Everything instance"
            }
            else {
                "Everything instance '$Instance'"
            }
            $diagnosis = [pscustomobject]@{
                code = "ipc_unavailable_after_start"
                message = "$targetDescription was started, but did not become available within $StartupTimeoutMilliseconds ms."
                recoverable = $false
                user_action_required = $true
                start_recommended = $false
                exit_code = $probe.ExitCode
            }
        }
        elseif ($startResult.error) {
            $diagnosis = [pscustomobject]@{
                code = "everything_start_failed"
                message = "Everything could not be started: $($startResult.error)"
                recoverable = $false
                user_action_required = $true
                start_recommended = $false
                exit_code = $probe.ExitCode
            }
        }
    }

    return [pscustomobject]@{
        ready = $false
        version = $null
        ipc_retry_used = $ipcRetryUsed
        client_started = $false
        diagnosis = $diagnosis
        exit_code = $probe.ExitCode
    }
}

function New-EverythingErrorPayload {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Diagnosis,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Instance
    )

    return [pscustomobject]@{
        ok = $false
        error = [pscustomobject]@{
            code = [string]$Diagnosis.code
            message = [string]$Diagnosis.message
            recoverable = [bool]$Diagnosis.recoverable
            user_action_required = [bool]$Diagnosis.user_action_required
            exit_code = [int]$Diagnosis.exit_code
            instance = if ([string]::IsNullOrWhiteSpace($Instance)) { $null } else { $Instance }
        }
    }
}
