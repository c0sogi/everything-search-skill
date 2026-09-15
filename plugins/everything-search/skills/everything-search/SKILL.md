---
name: everything-search
description: Search Windows files and folders instantly with the bundled voidtools Everything ES CLI, recover common local IPC startup failures, inspect or repair the Everything setup, and route file-content searches to rg. Use when the user asks to find files or folders by name, path, extension, size, or date; locate recent or duplicate files; count matching files; or diagnose Everything search on a local Windows machine.
---

# Everything Search

Use the bundled, signed `es.exe` for indexed file-system metadata searches. Do
not require a separately installed ES CLI or an MCP server.

Use the exact `SKILL.md` location supplied by the skill catalog. Do not rebuild
its absolute path from `CODEX_HOME`, a conventional `skills` directory, or a
plugin name: marketplace installs may live under a host-managed cache. Resolve
every relative path below against the directory containing that `SKILL.md`.

## Core workflow

1. Confirm the task is running on a local Windows host with shell access. This
   skill cannot query another machine's Everything index.
2. Invoke `scripts/Search-Everything.ps1` directly for normal searches. It
   checks IPC readiness, retries one transient IPC Error 8, and starts an
   already installed Everything client when that is the appropriate recovery.
3. Do not run a separate status command before every search. Use
   `scripts/Get-EverythingStatus.ps1` only for explicit diagnosis or setup.
4. If Everything is absent, install it only when the user explicitly requested
   setup or approved installation. Then invoke
   `scripts/Initialize-Everything.ps1 -InstallIfMissing -StartIfStopped`.
5. Keep the default `MaxResults` of 20 for ordinary discovery. If
   `limit_reached` is true, refine path, extension, date, size, or name filters
   before increasing the limit.
6. Keep `OutputMode Compact` unless the next step needs file metadata. Use
   `Metadata` or `Full` deliberately rather than returning unused fields.
7. Use `rg` for text inside files. Everything 1.4 does not index file contents,
   so `content:` searches can be slow.
8. Treat results as locators. Use `scripts/Get-FileIdentity.ps1` only after the
   candidate set is small, and compute SHA-256 only when identity verification
   is actually needed.

## Commands

Run these with Windows PowerShell or PowerShell 7:

```powershell
$skill = "<directory-containing-SKILL.md>"

# Compact path search
& "$skill\scripts\Search-Everything.ps1" -Query "AGENTS.md"

# Structured path, extension, type, and date filters
& "$skill\scripts\Search-Everything.ps1" `
  -Path "C:\Projects" `
  -Extensions cs,shader `
  -ItemType File `
  -ModifiedAfter "2026-08-01" `
  -Sort "date-modified-descending"

# Include metadata only when required
& "$skill\scripts\Search-Everything.ps1" `
  -Query "report" `
  -Extensions pdf,docx `
  -OutputMode Metadata

# Read-only health check
& "$skill\scripts\Get-EverythingStatus.ps1"

# Prepare Everything after explicit setup approval
& "$skill\scripts\Initialize-Everything.ps1" `
  -InstallIfMissing `
  -StartIfStopped
```

The search script returns normalized JSON. On success it includes `ok`,
`returned`, `limit_reached`, and `results`. Runtime IPC and search failures use
an `error` object with a stable code and indicate whether user action is
required.

## Safety and query rules

- Treat installation as a system change. Never pass `-InstallIfMissing` without
  explicit user intent or approval.
- Starting an already installed Everything client is allowed when needed to
  perform the requested search.
- Prefer structured parameters such as `-Path`, `-Extensions`, `-ItemType`,
  `-ModifiedAfter`, `-ModifiedBefore`, `-MinSizeBytes`, and `-MaxSizeBytes`.
- Do not call the bundled `es.exe` directly with arbitrary switches. The
  wrapper rejects query terms that could be interpreted as options.
- Do not expose ES mutation commands such as exit, reindex, save database, or
  settings changes.
- `-Instance` must be propagated to status, initialization, readiness probes,
  and search. Do not probe the unnamed instance for a named-instance search.
- Read `references/search-syntax.md` only when composing a query beyond the
  structured parameters and examples above.
