# Changelog

All notable changes to this module are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
