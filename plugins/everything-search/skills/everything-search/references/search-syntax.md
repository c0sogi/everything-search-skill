# Everything search syntax

Use these forms inside `Search-Everything.ps1 -Query`. Prefer the script's
structured parameters such as `-Path`, `-FilesOnly`, and `-Sort` when they cover
the request.

## Operators

| Form | Meaning | Example |
| --- | --- | --- |
| space | AND | `report ext:pdf` |
| `|` | OR | `ext:docx|ext:pdf` |
| `!` | NOT | `report !draft` |
| `"..."` | exact phrase | `"meeting notes"` |
| `<...>` | group | `<report invoice> ext:pdf` |

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

For a directory boundary, prefer the wrapper's `-Path "C:\Projects"` parameter
instead of embedding a path as a raw query term:

```powershell
& "$skill\scripts\Search-Everything.ps1" `
  -Query "ext:cs;shader dm:thisweek" `
  -Path "C:\Projects" `
  -FilesOnly `
  -Sort "date-modified-descending"
```

Do not put ES command-line switches such as `-n`, `-sort`, `/ad`, or `/a-d` in
`-Query`. The wrapper rejects terms beginning with `-` or `/`; use its
parameters instead.

Everything 1.4 searches indexed names and metadata. For text inside files,
first use Everything to narrow the directory or file set when useful, then use
`rg`:

```powershell
rg --line-number --hidden --glob "!Library/**" "needle" "C:\Projects"
```

Official references:

- <https://www.voidtools.com/support/everything/searching/>
- <https://www.voidtools.com/support/everything/command_line_interface/>
- <https://github.com/voidtools/ES>
