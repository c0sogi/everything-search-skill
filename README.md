# Everything Search Skill

An MCP-free Codex Agent Skill for near-instant file and folder search on
Windows. It bundles the official, signed voidtools `es.exe` client for x64 and
ARM64, checks the local Everything setup, and gives the agent a safe structured
search wrapper.

## Install

Add this repository as a Codex plugin marketplace, then install the plugin:

```powershell
codex plugin marketplace add c0sogi/everything-search-skill
codex plugin add everything-search@everything-search-skill
```

Start a new Codex thread after installation. You can invoke
`$everything-search` explicitly or ask naturally:

- “Find all `AGENTS.md` files on this PC.”
- “Find `.cs` files modified today under `C:\Projects`.”
- “Check whether Everything search is ready.”

## What it does

- Searches indexed file and folder names, paths, extensions, sizes, attributes,
  and dates through Everything's local IPC interface.
- Returns normalized JSON with exact full paths and an explicit result-limit
  indicator.
- Detects the installed/running state of Everything and the bundled ES version,
  hash, and Authenticode signature.
- Starts an installed Everything app when a requested search needs it.
- Can install the official `voidtools.Everything` WinGet package when the user
  explicitly asks for setup.
- Directs searches inside file contents to `rg` (ripgrep).

No MCP server, listening port, Python runtime, or separately installed ES CLI
is required.

## Requirement

The [Everything desktop app](https://www.voidtools.com/) must be installed and
running because `es.exe` queries its local index. The skill can perform that
setup through WinGet after explicit approval. Windows x64 and ARM64 are
supported.

## Trust and licensing

This repository's original code is MIT licensed. The bundled ES 1.1.0.37
binaries come from the official [voidtools/ES
release](https://github.com/voidtools/ES/releases/tag/1.1.0.37), retain the
voidtools Authenticode signature, and are covered by their included MIT
license. Recorded source and binary hashes are in
[`manifest.json`](plugins/everything-search/skills/everything-search/assets/es/manifest.json).
See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for attribution.

This project is independent and is not affiliated with or endorsed by
voidtools.

## Validate

On Windows:

```powershell
./tests/Test-Package.ps1 -RequireValidSignature

# Optional end-to-end check when Everything is installed and running
./tests/Test-Integration.ps1
```

The test checks plugin metadata, skill structure, PowerShell syntax, bundled
binary hashes, signatures, and ES versions. The integration test also queries
the live Everything index and checks result limiting and unsafe-option guards.
