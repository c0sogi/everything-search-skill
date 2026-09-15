# Everything Search Skill

An MCP-free Codex Agent Skill for near-instant, bounded file and folder search
on Windows. It bundles the official, signed voidtools `es.exe` client for x64
and ARM64 and exposes a safe PowerShell wrapper designed for agent workflows.

## Install

Add this repository as a Codex plugin marketplace, then install the plugin:

```powershell
codex plugin marketplace add c0sogi/everything-search-skill
codex plugin add everything-search@everything-search-skill
```

Start a new Codex thread after installation. You can invoke
`$everything-search` explicitly or ask naturally:

- “Find all `AGENTS.md` files on this PC.”
- “Find `.cs` and `.shader` files modified today under `C:\Projects`.”
- “Locate the newest matching build artifact, but return only a small candidate set.”

Codex may install marketplace plugins in a host-managed cache. Integrations
should use the exact skill location supplied by the catalog and resolve bundled
scripts relative to `SKILL.md`; they should not assume the skill is directly
under `$CODEX_HOME\skills`.

## Design goals

- **One search entry point:** `Search-Everything.ps1` checks IPC readiness,
  retries one transient IPC failure, starts an installed Everything client when
  appropriate, and then performs the search.
- **Bounded context:** searches return at most 20 results by default and use a
  compact result schema unless more metadata is requested.
- **Structured filters:** common extension, item type, modified date, size,
  path, sort, and named-instance constraints do not require hand-written
  Everything syntax.
- **Safe execution:** the wrapper verifies the bundled ES hash and Authenticode
  signer and rejects query terms that resemble command-line switches.
- **Clear separation:** Everything locates indexed paths; `rg` searches file
  contents; `Get-FileIdentity.ps1` verifies only a small final candidate set.

No MCP server, listening port, Python runtime, or separately installed ES CLI
is required.

## Search examples

The normal path is to call the search script directly. A separate status call
is not required before each search.

```powershell
$skill = "<directory-containing-SKILL.md>"

# Compact path discovery; MaxResults defaults to 20
& "$skill\scripts\Search-Everything.ps1" -Query "AGENTS.md"

# Structured filters instead of embedding all syntax in Query
& "$skill\scripts\Search-Everything.ps1" `
  -Path "C:\Projects" `
  -Extensions cs,shader `
  -ItemType File `
  -ModifiedAfter "2026-08-01" `
  -Sort "date-modified-descending"

# Request metadata only when the next step needs it
& "$skill\scripts\Search-Everything.ps1" `
  -Query "report" `
  -Extensions pdf,docx `
  -OutputMode Metadata

# Target a named Everything instance consistently across readiness and search
& "$skill\scripts\Search-Everything.ps1" `
  -Query "dataset" `
  -Instance "Research Index"
```

`OutputMode` supports:

- `Compact` (default): `full_path`, `is_folder`
- `Metadata`: compact fields plus name, extension, size, and modified time
- `Full`: metadata fields plus parent path, created time, and raw attributes

The response uses normalized JSON with `ok`, `returned`, `limit_reached`, and
`results`. If the result limit is reached, refine the query rather than raising
the limit immediately.

## Setup and diagnostics

Everything Desktop must be installed because `es.exe` queries its local index.
A normal search may start an already installed Everything client, but it never
installs software.

```powershell
# Read-only diagnosis
& "$skill\scripts\Get-EverythingStatus.ps1"

# Named-instance diagnosis
& "$skill\scripts\Get-EverythingStatus.ps1" -Instance "Research Index"

# Install only after explicit approval, then start the client
& "$skill\scripts\Initialize-Everything.ps1" `
  -InstallIfMissing `
  -StartIfStopped
```

## Final-candidate identity checks

Search results are path locators, not proof that a file is authoritative. After
narrowing to a small set, inspect filesystem identity and optionally compute
SHA-256:

```powershell
& "$skill\scripts\Get-FileIdentity.ps1" `
  -Path "C:\Projects\build\artifact.zip" `
  -IncludeSha256
```

## Trust and licensing

This repository's original code is MIT licensed. The bundled ES 1.1.0.37
binaries come from the official voidtools ES release, retain the voidtools
Authenticode signature, and are covered by their included MIT license. Recorded
source and binary hashes are in
[`manifest.json`](plugins/everything-search/skills/everything-search/assets/es/manifest.json).
See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for attribution.

This project is independent and is not affiliated with or endorsed by
voidtools.

## Validate

On Windows:

```powershell
./tests/Test-Package.ps1 -RequireValidSignature
./tests/Test-QueryConstruction.ps1
./tests/Test-IpcRecovery.ps1

# Optional end-to-end check when Everything is installed and running
./tests/Test-Integration.ps1
```

CI runs package, query-construction, and IPC-recovery checks with both Windows
PowerShell 5.1 and PowerShell 7. The integration test additionally queries a live Everything
index, validates compact and metadata output, checks result limiting, and
exercises unsafe-option guards.
