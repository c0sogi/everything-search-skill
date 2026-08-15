# Everything search syntax

Prefer the structured parameters of `Search-Everything.ps1` whenever they cover
the request:

- `-Path`
- `-Extensions`
- `-ItemType Any|File|Folder`
- `-ModifiedAfter` and `-ModifiedBefore`
- `-MinSizeBytes` and `-MaxSizeBytes`
- `-Sort`
- `-Instance`

Use raw Everything syntax inside `-Query` only for expressions that cannot be
represented cleanly with those parameters.

## Operators

| Form | Meaning | Example |
| --- | --- | --- |
| space | AND | `report final` |
| `|` | OR | `invoice|receipt` |
| `!` | NOT | `report !draft` |
| `"..."` | exact phrase | `"meeting notes"` |
| `<...>` | group | `<report invoice> final` |

## Useful functions

| Function | Purpose | Example |
| --- | --- | --- |
| `ext:` | Match one or more extensions | `ext:cs;shader` |
| `file:` | Files only | `file: README` |
| `folder:` | Folders only | `folder: Library` |
| `dm:` | Date modified | `dm:today`, `dm:thisweek` |
| `dc:` | Date created | `dc:yesterday` |
| `size:` | File size | `size:>100mb` |
| `empty:` | Empty files or folders | `empty:` |
| `dupe:` | Duplicate property value | `dupe:size;name` |
| `regex:` | Regular expression | `regex:^AGENTS\.md$` |

For common filters, prefer this:

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "report" `
  -Path "C:\Projects" `
  -Extensions pdf,docx `
  -ItemType File `
  -ModifiedAfter "2026-08-01"
```

instead of embedding every constraint into a single raw query string. The
wrapper keeps independent search terms as independent native arguments, which
also avoids Windows PowerShell 5.1 argument-construction pitfalls.

Do not put ES command-line switches such as `-n`, `-sort`, `/ad`, or `/a-d` in
`-Query`. The wrapper rejects terms beginning with `-` or `/`; use its
parameters instead.

`-Regex` applies to the complete `Query` value and cannot be combined with the
structured extension, date, or size filters. Put the complete expression in
`Query`, or use normal Everything syntax without `-Regex`.

Everything searches indexed names and metadata. For text inside files, first
use Everything to narrow the directory or candidate file set when useful, then
use `rg`:

```powershell
rg --line-number --hidden --glob "!Library/**" "needle" "C:\Projects"
```

Official references:

- <https://www.voidtools.com/support/everything/searching/>
- <https://www.voidtools.com/support/everything/command_line_interface/>
- <https://github.com/voidtools/ES>
