# Changelog

All notable changes to this module are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-03

First skeleton of the module: structure, tests and CI, no public command yet.

### Added

- Module manifest and root module that loads `Private` then `Public` and exports only the public commands.
- Private helper `Format-ByteSize`: readable sizes in binary units with a dot as decimal separator on every workstation.
- Pester 5 tests: manifest, exported commands, help of every public command, file encoding and syntax, `Format-ByteSize`.
- `Invoke-Tests.ps1`: PSScriptAnalyzer and Pester with the same settings on a workstation and in the CI.
- GitHub Actions: PSScriptAnalyzer on Linux, Pester on Windows PowerShell 5.1 and PowerShell 7, Markdown lint and relative link check.
- Documentation: README, architecture and design decisions, contributing guide, MIT license.
