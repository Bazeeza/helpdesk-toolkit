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
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Version-0.3.0-ffb454?style=flat-square" alt="Version 0.3.0"/></a>
</p>

> **En bref (français) :** module PowerShell de diagnostic pour le soutien technique, compatible avec Windows PowerShell 5.1 (le shell présent sur tous les postes Windows). Chaque commande lit l'état du poste sans le modifier et renvoie des objets réutilisables (CSV, rapport HTML). Le code est vérifié à chaque modification : PSScriptAnalyzer, tests Pester sous PowerShell 5.1 et 7. **Version 0.3.0 :** `Get-SystemReport` (Windows, matériel, numéro de série, mémoire, disques, temps depuis le dernier démarrage) et `Test-NetworkHealth` (diagnostic réseau couche par couche : lien, adresse IP ou APIPA, passerelle, Internet, DNS, port TCP, avec la couche en panne et sa cause probable). **Version 0.4.0 :** `Get-InstalledSoftware` (logiciels installés lus dans le registre, 64 bits, 32 bits et par utilisateur, prêts pour un export CSV, sans jamais interroger `Win32_Product`, qui peut lancer une réparation des paquets MSI) ; les autres commandes arrivent une à une (voir la feuille de route).

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

### First ticket check: Get-SystemReport

```powershell
# Windows edition and build, model, serial number, memory, disks and uptime
Get-SystemReport

# Has the computer really restarted this week?
Get-SystemReport | Where-Object { $_.Uptime.TotalDays -gt 7 }

# Free space of each fixed disk, as a table
Get-SystemReport | Select-Object -ExpandProperty Disks
```

The console shows a short view; every property stays on the object (`Select-Object *`). All properties, data sources and remote requirements: [docs/commands/Get-SystemReport.md](docs/commands/Get-SystemReport.md).

### "I have no Internet": Test-NetworkHealth

```powershell
# Link, IPv4 address or APIPA, gateway, public IP, DNS and HTTPS port, in that order
Test-NetworkHealth

# The six steps as a table: Pass, Warning, Fail or Skipped
Test-NetworkHealth | Select-Object -ExpandProperty Checks

# Can this computer reach the network printer on its printing port?
Test-NetworkHealth -TargetHost 'print01.corp.example.com' -Port 9100
```

The result names the first layer that failed (`FailedStep`) and what it means (`Diagnosis`), for example *DHCP problem* for an address in `169.254.x.x`. A gateway that ignores ping is reported as a `Warning` when traffic still goes through. Steps, statuses and design choices: [docs/commands/Test-NetworkHealth.md](docs/commands/Test-NetworkHealth.md).

### "Is it installed, which version?": Get-InstalledSoftware

```powershell
# Is a browser installed, which version and since when?
Get-InstalledSoftware -Name '*Chrome*', '*Firefox*'

# What changed last? The ten most recently installed or updated programs
Get-InstalledSoftware | Sort-Object -Property InstallDate -Descending | Select-Object -First 10

# Software inventory as a CSV file for the ticket
Get-InstalledSoftware | Export-Csv -Path .\software.csv -NoTypeInformation -Encoding UTF8
```

The list is the one of *Programs and Features*: 64-bit, 32-bit (`WOW6432Node`) and per-user programs, read from the registry. The command never queries `Win32_Product`, which makes Windows Installer check and possibly repair every MSI package. Sources, hidden entries and output: [docs/commands/Get-InstalledSoftware.md](docs/commands/Get-InstalledSoftware.md).

> [!NOTE]
> Version 0.4.0 exports three commands, `Get-SystemReport`, `Test-NetworkHealth` and `Get-InstalledSoftware`. The other commands of the roadmap are added one at a time, each with its tests and its reference page.

## Roadmap

| Command | What it answers | Status |
|---|---|---|
| [`Get-SystemReport`](docs/commands/Get-SystemReport.md) | Which Windows, which hardware, how much memory, since when is it running, what is the serial number? | Available |
| [`Test-NetworkHealth`](docs/commands/Test-NetworkHealth.md) | Where does the network stop: adapter, IP address or APIPA, gateway, Internet, DNS or remote port? | Available |
| [`Get-InstalledSoftware`](docs/commands/Get-InstalledSoftware.md) | Is the application installed, which version, since when? Read from the registry, never `Win32_Product`, ready for CSV | Available |
| `Get-DiskHealth` | How much free space is left, and does the disk report a health problem? | Planned |
| `Clear-TempFiles` | Free space safely, with `-WhatIf` to preview and `-Confirm` to approve | Planned |
| `Export-HelpdeskReport` | One self-contained HTML file to attach to the ticket | Planned |

`Test-NetworkHealth` automates the six steps of the layer-by-layer method of the [Network Troubleshooting runbook](https://github.com/Bazeeza/Technical-Runbooks/blob/main/04-Network-Troubleshooting/README.md) from [Technical Runbooks](https://github.com/Bazeeza/Technical-Runbooks).

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
├── docs/                   architecture, design decisions and one page per command
├── Invoke-Tests.ps1        PSScriptAnalyzer and Pester, locally and in the CI
├── CHANGELOG.md            what changed in each version
└── CONTRIBUTING.md         how to add a command and the rules it must follow
```

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before adding a command. Released under the [MIT License](LICENSE).
