# Changelog

## 0.2.0

- Make `Search-Everything.ps1` the single normal search entry point.
- Add bounded IPC retry, safe client auto-start, stable error JSON, and named
  instance propagation.
- Change the default result limit to 20 and add compact, metadata, and full
  output modes.
- Add structured extension, item type, modified-date, and size filters.
- Add optional final-candidate filesystem identity and SHA-256 inspection.
- Add offline query-construction and IPC-recovery regression tests with Windows
  PowerShell 5.1 / PowerShell 7 CI validation.
