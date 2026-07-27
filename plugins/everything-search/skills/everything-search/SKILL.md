---
name: everything-search
description: Search Windows files and folders instantly with the bundled voidtools Everything ES CLI, inspect or repair the local Everything setup, and route file-content searches to rg. Use when the user asks to find files or folders by name, path, extension, size, or date; locate recent or duplicate files; count matching files; or diagnose Everything search on a local Windows machine.
---

# Everything Search

Use the bundled, signed `es.exe` for indexed file-system metadata searches. Do
not require a separately installed ES CLI or an MCP server.

Resolve every relative path below against the directory containing this
`SKILL.md`.

## Workflow

1. Confirm the task is running on a local Windows host with shell access. If it
   is not, explain that this skill cannot search another machine's Everything
   index.
2. Run `scripts/Get-EverythingStatus.ps1` before the first Everything search in
   a task.
3. Interpret the status:
   - If `ready` is `true`, search immediately.
   - If Everything is installed but stopped, run
     `scripts/Initialize-Everything.ps1 -StartIfStopped`.
   - If Everything is absent, install it only when the user explicitly asked
     for setup or approved installation. Then run
     `scripts/Initialize-Everything.ps1 -InstallIfMissing -StartIfStopped`.
   - Never install the separate ES CLI. This skill already bundles it.
4. Choose the search mechanism:
   - Use `scripts/Search-Everything.ps1` for file or folder names, paths,
     extensions, sizes, attributes, and dates.
   - Use `rg` for text inside files. Everything 1.4 does not index file
     contents, so `content:` can be slow.
5. Return exact full paths. State when the result limit was reached and refine
   the query instead of silently treating a limited result set as complete.

## Commands

Run these with Windows PowerShell or PowerShell 7:

```powershell
$skill = "<directory-containing-SKILL.md>"

# Read-only health check
& "$skill\scripts\Get-EverythingStatus.ps1"

# Search by name
& "$skill\scripts\Search-Everything.ps1" -Query "AGENTS.md" -MaxResults 50

# Search a path and multiple extensions
& "$skill\scripts\Search-Everything.ps1" `
  -Query "ext:cs;shader dm:thisweek" `
  -Path "C:\Projects" `
  -FilesOnly `
  -Sort "date-modified-descending"

# Prepare Everything after explicit setup approval
& "$skill\scripts\Initialize-Everything.ps1" `
  -InstallIfMissing `
  -StartIfStopped
```

The search script returns JSON with normalized full paths and a
`limit_reached` flag. Keep `MaxResults` at or below 200.

## Safety and query rules

- Treat setup as a system change. Do not pass `-InstallIfMissing` without
  explicit user intent or confirmation.
- Starting an already installed Everything client is allowed when needed to
  perform the requested search.
- Do not call the bundled `es.exe` directly with arbitrary switches. Use the
  wrapper, which rejects query terms that could be interpreted as command-line
  options.
- Do not expose ES mutation commands such as exit, reindex, save database, or
  settings changes.
- Read `references/search-syntax.md` only when composing a query beyond the
  examples above.
