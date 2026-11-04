<h1 align="center">Helpdesk Toolkit</h1>

<p align="center">
  <b>A PowerShell module that turns the first minutes of a help desk ticket into repeatable, read-only checks.</b><br>
  System report · Network health · Installed software · Disk health · HTML report for the ticket
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207-2b9dff?style=flat-square&logo=powershell&logoColor=white" alt="Windows PowerShell 5.1 and PowerShell 7"/>
  <img src="https://img.shields.io/badge/Tests-Pester%205-3fe0a0?style=flat-square" alt="Tested with Pester 5"/>
  <img src="https://img.shields.io/badge/License-MIT-555?style=flat-square" alt="MIT License"/>
  <img src="https://img.shields.io/badge/Author-bazeeza-c792ea?style=flat-square" alt="Author: bazeeza"/>
  <br>
  <a href="https://github.com/Bazeeza/helpdesk-toolkit/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Bazeeza/helpdesk-toolkit/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"/></a>
  <a href="https://github.com/Bazeeza/helpdesk-toolkit/actions/workflows/markdown.yml"><img src="https://img.shields.io/github/actions/workflow/status/Bazeeza/helpdesk-toolkit/markdown.yml?branch=main&style=flat-square&label=Markdown" alt="Markdown CI status"/></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Version-0.1.0-ffb454?style=flat-square" alt="Version 0.1.0"/></a>
</p>

> **En bref (français) :** module PowerShell de diagnostic pour le soutien technique, compatible avec Windows PowerShell 5.1 (le shell présent sur tous les postes Windows). Chaque commande lit l'état du poste sans le modifier et renvoie des objets réutilisables (CSV, rapport HTML). Le code est vérifié à chaque modification : PSScriptAnalyzer, tests Pester sous PowerShell 5.1 et 7. **Version 0.1.0 :** ossature, tests et CI ; les commandes arrivent une à une (voir la feuille de route).

---

## Why this module

The first questions of almost every ticket are the same: *which Windows build, how much free space, is the network up to the gateway, is the software installed, since when has the computer been running?* Typing them by hand is slow and the answers end up as screenshots in the ticket.

`HelpdeskToolkit` answers them with commands that:

- **only read** the computer (the single command that cleans files will support `-WhatIf` and `-Confirm`);
- return **objects**, so the same data can be filtered, exported to CSV or put in an HTML report;
- run in **Windows PowerShell 5.1**, already installed on every Windows 10 and Windows 11 workstation;
- are **tested** with Pester and mocks, so the tests never depend on the computer they run on.

## Architecture

```mermaid
flowchart LR
    T["Technician"] -->|"Import-Module"| PSD["HelpdeskToolkit.psd1<br/>manifest"]
    PSD --> PSM["HelpdeskToolkit.psm1<br/>loader"]
    PSM -->|"dot-source first"| PRIV["Private<br/>helpers"]
    PSM -->|"dot-source and export"| PUB["Public<br/>commands"]
    PUB -.->|"use"| PRIV
    PUB -->|"read"| SRC["CIM, registry,<br/>network stack"]
    PUB -->|"objects"| OUT["Console, CSV,<br/>HTML report"]

    classDef entry fill:#070d1c,stroke:#c792ea,color:#ffffff
    classDef module fill:#070d1c,stroke:#2b9dff,color:#ffffff
    classDef code fill:#070d1c,stroke:#3fe0a0,color:#ffffff
    classDef data fill:#070d1c,stroke:#ffb454,color:#ffffff
    class T entry
    class PSD,PSM module
    class PRIV,PUB code
    class SRC,OUT data
```

Details and the reasons behind each choice: [docs/architecture.md](docs/architecture.md).

## Quick start

```powershell
# Get the code
git clone https://github.com/Bazeeza/helpdesk-toolkit.git
cd helpdesk-toolkit

# If the files came from a downloaded ZIP, remove the "downloaded from the Internet" mark
Get-ChildItem -Recurse -File | Unblock-File

# Load the module for the current session and list its commands
Import-Module .\HelpdeskToolkit\HelpdeskToolkit.psd1
Get-Command -Module HelpdeskToolkit
```

> [!NOTE]
> Version 0.1.0 is the skeleton of the module: loader, private helper, tests and CI. It does not export any command yet, so `Get-Command` returns nothing. Commands are added one at a time, each with its tests.

## Roadmap

| Command | What it answers | Status |
|---|---|---|
| `Get-SystemReport` | Which Windows, which hardware, how much memory, since when is it running, what is the serial number? | Planned |
| `Test-NetworkHealth` | Where does the network stop: adapter, IP address or APIPA, gateway, DNS or remote port? | Planned |
| `Get-InstalledSoftware` | Is the application installed, which version, since when? Read from the registry, exported to CSV | Planned |
| `Get-DiskHealth` | How much free space is left, and does the disk report a health problem? | Planned |
| `Clear-TempFiles` | Free space safely, with `-WhatIf` to preview and `-Confirm` to approve | Planned |
| `Export-HelpdeskReport` | One self-contained HTML file to attach to the ticket | Planned |

`Test-NetworkHealth` automates the layer-by-layer method of the [Network Troubleshooting runbook](https://github.com/Bazeeza/Technical-Runbooks/blob/main/04-Network-Troubleshooting/README.md) from [Technical Runbooks](https://github.com/Bazeeza/Technical-Runbooks).

## Quality checks

| Check | Where | What it catches |
|---|---|---|
| PSScriptAnalyzer | Linux runner | Unapproved verbs, unused variables, syntax that Windows PowerShell 5.1 does not understand |
| Pester 5 | Windows PowerShell 5.1 and PowerShell 7 | Wrong results, missing help, exports that do not match the manifest, files that 5.1 would misread |
| markdownlint and lychee | Linux runner | Broken Markdown and broken links between the documents |

The same analysis and tests run on a workstation with one command:

```powershell
.\Invoke-Tests.ps1
```

## Repository layout

```text
helpdesk-toolkit/
├── HelpdeskToolkit/        the module: manifest, loader, Public and Private functions
├── Tests/                  Pester tests and analyzer settings for the tests
├── docs/                   architecture and design decisions
├── Invoke-Tests.ps1        PSScriptAnalyzer and Pester, locally and in the CI
├── CHANGELOG.md            what changed in each version
└── CONTRIBUTING.md         how to add a command and the rules it must follow
```

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before adding a command. Released under the [MIT License](LICENSE).
