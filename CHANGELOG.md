# Changelog

All notable changes to this module are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-11-08

HTML report for the ticket.

### Added

- `Export-HelpdeskReport`: runs `Get-SystemReport`, `Test-NetworkHealth`, `Get-DiskHealth` and `Get-InstalledSoftware` on the local computer and writes one self-contained HTML file: header with the computer, ticket number and time, one summary card per section coloured by status, then the details. Choose the sections with `-Section`; a section that fails is written as *Not collected* with the reason and a warning. Supports `-WhatIf` (collects and writes nothing) and `-Confirm`; an existing file is replaced only with `-Force`; `-PassThru` returns the file.
- Dark and light themes that follow the system, a theme switch without JavaScript, and a print layout on white paper. Every status colour has a contrast ratio of at least 4.5:1, checked by a test.
- Private helpers `ConvertTo-HtmlText` (invariant text, control characters removed, HTML-encoded), `Get-ReportStatusLevel` and `ConvertTo-StatusBadge` (one colour level for `Pass`, `OK` and `Healthy`), `ConvertTo-ReportTable` (encoded tables with badges and percentage bars), `Get-ReportStyleSheet` (embedded CSS) and `ConvertTo-ReportHtml` (the page, with a Content-Security-Policy that allows no script).
- Pester tests for the command with mocked diagnostics on `TestDrive`, and for each helper with fictitious results, including values that try to inject HTML.
- Reference page [docs/commands/Export-HelpdeskReport.md](docs/commands/Export-HelpdeskReport.md).

## [0.5.0] - 2026-11-07

Disk health and safe cleanup.

### Added

- `Get-DiskHealth`: free space of every local fixed volume against two thresholds (`-WarningPercent` 15 and `-CriticalPercent` 5 by default), health and operational status reported by every physical disk (`MSFT_PhysicalDisk`), and, in an elevated session, temperature, wear, power-on hours and uncorrected errors (`MSFT_StorageReliabilityCounter`). One overall status (`OK`, `Unknown`, `Warning`, `Critical`) and one line per issue.
- `Clear-TempFiles`: removes files older than `-OlderThanDays` (7 by default) from the temporary folder of the current user and, optionally, `C:\Windows\Temp`. Supports `-WhatIf` and `-Confirm` with a `High` impact, so it asks by default. Fixed locations only, five safety checks on the path, links never followed, files in use skipped and counted.
- Private helpers `ConvertFrom-StorageCode` (documented storage codes to text), `Get-StorageReliability` (reliability counters or nothing), `Get-TempFileCandidate` (folder walk that never enters a link) and `Get-TempLocation` (the fixed cleanup folders).
- Default console views for disk health results, volumes, physical disks and cleanup results.
- Pester tests for both commands and the four helpers; the cleanup tests remove real files in Pester's `TestDrive` only.
- Reference pages [docs/commands/Get-DiskHealth.md](docs/commands/Get-DiskHealth.md) and [docs/commands/Clear-TempFiles.md](docs/commands/Clear-TempFiles.md).

## [0.4.0] - 2026-11-06

Software inventory.

### Added

- `Get-InstalledSoftware`: programs of the local computer read from the 64-bit, 32-bit (`WOW6432Node`) and current user uninstall keys, never from `Win32_Product`. Name, version, publisher, install date, scope, architecture, estimated size, MSI product code and uninstall commands in flat objects ready for `Export-Csv`. Filters by display name with wildcards and by scope; system components and updates are hidden like in Programs and Features unless `-IncludeHidden` is used.
- Private helper `Get-UninstallRegistryEntry`: reads an uninstall key in an explicit 64-bit or 32-bit registry view, so a 32-bit PowerShell is not redirected.
- Private helper `ConvertTo-InstallDate`: reads install dates such as `20260115` or `1/15/2026` with the invariant culture.
- Default console view for installed software.
- Pester tests for `Get-InstalledSoftware` with mocked registry lists, for `Get-UninstallRegistryEntry` against Pester's `TestRegistry:` drive, and for `ConvertTo-InstallDate`.
- Reference page [docs/commands/Get-InstalledSoftware.md](docs/commands/Get-InstalledSoftware.md).

### Fixed

- The PSScriptAnalyzer job of the CI failed on five findings in the test files (fictitious computer names and `New-Fake*` fixtures). The two rules are now excluded for the tests only, with the reason in `Tests/PSScriptAnalyzerSettings.psd1`.

### Changed

- GitHub Actions use `actions/checkout@v5` and `actions/upload-artifact@v5`, which run on Node.js 24.

## [0.3.0] - 2026-11-05

Network diagnosis.

### Added

- `Test-NetworkHealth`: the six steps of the network troubleshooting runbook on the local computer (link, IPv4 address or APIPA, default gateway, public IP address, DNS resolution, TCP port of a service). Returns the status of each step (`Pass`, `Warning`, `Fail`, `Skipped`), the first step that failed and a diagnosis. A ping that fails while a higher test succeeds is a `Warning`, not a failure.
- Private helpers `Test-IcmpEcho` (.NET `Ping` class) and `Test-TcpPort` (.NET `TcpClient` with a timeout), identical in Windows PowerShell 5.1 and PowerShell 7.
- Default console views for network health results and their checks.
- Pester tests for `Test-NetworkHealth` with a mocked network stack, and loopback tests for the two helpers.
- Reference page [docs/commands/Test-NetworkHealth.md](docs/commands/Test-NetworkHealth.md).

## [0.2.0] - 2026-11-04

First public command.

### Added

- `Get-SystemReport`: Windows edition, version and build, manufacturer, model, serial number, firmware version, processors, memory, local fixed disks, last boot time and uptime, read from five CIM classes. Works on the local computer without WinRM and on remote computers through WinRM; an unreachable computer is reported as a non-terminating error.
- Private helper `Format-Uptime`: short uptime text such as `12d 4h 7m`.
- `HelpdeskToolkit.Types.ps1xml`: short default console view for system reports and disks.
- Pester tests for `Get-SystemReport` with mocked CIM classes, and for `Format-Uptime`.
- Reference page [docs/commands/Get-SystemReport.md](docs/commands/Get-SystemReport.md).

### Changed

- Author name in the license, manifest and README is now `bazeeza`.
- Type files are checked out with CRLF and tested as valid XML.

## [0.1.0] - 2026-11-03

First skeleton of the module: structure, tests and CI, no public command yet.

### Added

- Module manifest and root module that loads `Private` then `Public` and exports only the public commands.
- Private helper `Format-ByteSize`: readable sizes in binary units with a dot as decimal separator on every workstation.
- Pester 5 tests: manifest, exported commands, help of every public command, file encoding and syntax, `Format-ByteSize`.
- `Invoke-Tests.ps1`: PSScriptAnalyzer and Pester with the same settings on a workstation and in the CI.
- GitHub Actions: PSScriptAnalyzer on Linux, Pester on Windows PowerShell 5.1 and PowerShell 7, Markdown lint and relative link check.
- Documentation: README, architecture and design decisions, contributing guide, MIT license.
