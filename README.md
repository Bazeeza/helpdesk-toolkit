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
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Version-1.0.0-ffb454?style=flat-square" alt="Version 1.0.0"/></a>
</p>

> **En bref (français) :** module PowerShell de diagnostic pour le soutien technique, compatible avec Windows PowerShell 5.1 (le shell présent sur tous les postes Windows). **Version 1.0.0**, six commandes : `Get-SystemReport` (Windows, matériel, numéro de série, mémoire, disques, temps depuis le dernier démarrage), `Test-NetworkHealth` (diagnostic réseau couche par couche, avec la couche en panne et sa cause probable), `Get-InstalledSoftware` (logiciels lus dans le registre, jamais par `Win32_Product`), `Get-DiskHealth` (espace libre et santé des disques), `Clear-TempFiles` (la seule commande qui modifie le poste : aperçu avec `-WhatIf`, confirmation par défaut) et `Export-HelpdeskReport` (un rapport HTML autonome à joindre au billet, thème sombre ou clair). Chaque commande a une aide complète dans le terminal (`Get-Help <commande> -Full`, `Get-Help about_HelpdeskToolkit`), le dossier `examples` montre des scripts pour les billets courants, et les captures d'écran sont faites à partir de données fictives. Le code est vérifié à chaque modification : PSScriptAnalyzer et tests Pester sous PowerShell 5.1 et 7.

---

## Why this module

The first questions of almost every ticket are the same: *which Windows build, how much free space, is the network up to the gateway, is the software installed, since when has the computer been running?* Typing them by hand is slow and the answers end up as screenshots in the ticket.

`HelpdeskToolkit` answers them with commands that:

- **only read** the computer (the single command that cleans files, `Clear-TempFiles`, previews with `-WhatIf` and asks before acting; `Export-HelpdeskReport` only creates its report file);
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

### "My disk is full": Get-DiskHealth and Clear-TempFiles

```powershell
# Free space of each volume and health reported by each drive, with one overall status
Get-DiskHealth

# Only the problems, one line each, for the ticket
Get-DiskHealth | Select-Object -ExpandProperty Issues

# Preview: how much would removing temporary files older than 7 days free? Removes nothing
Clear-TempFiles -WhatIf

# Do it, after a confirmation
Clear-TempFiles
```

`Get-DiskHealth` flags a volume under 15 % (`Warning`) or 5 % (`Critical`) of free space and reads the health status that each physical disk reports; temperature, wear and error counters are added in an elevated session. Rules and output: [docs/commands/Get-DiskHealth.md](docs/commands/Get-DiskHealth.md).

`Clear-TempFiles` is the only command that changes the computer. It cleans fixed temporary folders only, keeps recent and busy files, never follows links, and asks before each folder unless `-Confirm:$false` is given. Safety checks and output: [docs/commands/Clear-TempFiles.md](docs/commands/Clear-TempFiles.md).

### Hand over the ticket: Export-HelpdeskReport

```powershell
# System, network, disk health and installed software in one HTML file, in the current folder
Export-HelpdeskReport

# On the desktop with the ticket number, then open it in the browser
Export-HelpdeskReport -Path "$env:USERPROFILE\Desktop" -TicketNumber 'INC-0042' -PassThru | Invoke-Item

# Only the sections that matter for this ticket
Export-HelpdeskReport -Section Network, Disk
```

One self-contained file to attach to the ticket: summary cards coloured by status, then the details of each section. The style sheet is embedded and the page runs no script, so it opens offline and from an e-mail. It follows the dark or light theme of the system, has a theme switch, and prints on white paper. A diagnostic that fails is written as *Not collected* with the reason, and every value read on the computer is HTML-encoded. Layout and design choices: [docs/commands/Export-HelpdeskReport.md](docs/commands/Export-HelpdeskReport.md).

> [!NOTE]
> The report contains the serial number and network addresses of the computer: share it through the ticket only.

## What the report looks like

Generated by [`examples/New-SampleReport.ps1`](examples/New-SampleReport.ps1) from **fictitious results** (computer `PC-EXAMPLE01`, documentation addresses `192.0.2.x`), never from a real computer. The gateway ignores ping while traffic goes through, and drive C: is under the 15 % threshold, so the page shows each status colour.

| Dark theme | Light theme |
|---|---|
| ![Report summary in the dark theme: header, four summary cards and the System section](docs/images/report-dark.png) | ![Report summary in the light theme: header, four summary cards and the System section](docs/images/report-light.png) |

<details>
<summary>Disk health and installed software sections</summary>

![Disk health section with one warning, physical disks and the installed software table, dark theme](docs/images/report-disk-dark.png)

</details>

## Commands

| Command | What it answers | Changes the computer? |
|---|---|---|
| [`Get-SystemReport`](docs/commands/Get-SystemReport.md) | Which Windows, which hardware, how much memory, since when is it running, what is the serial number? | No |
| [`Test-NetworkHealth`](docs/commands/Test-NetworkHealth.md) | Where does the network stop: adapter, IP address or APIPA, gateway, Internet, DNS or remote port? | No |
| [`Get-InstalledSoftware`](docs/commands/Get-InstalledSoftware.md) | Is the application installed, which version, since when? Read from the registry, never `Win32_Product`, ready for CSV | No |
| [`Get-DiskHealth`](docs/commands/Get-DiskHealth.md) | How much free space is left, and does the disk report a health problem? | No |
| [`Clear-TempFiles`](docs/commands/Clear-TempFiles.md) | Free space safely, with `-WhatIf` to preview and `-Confirm` to approve | Yes, after a confirmation |
| [`Export-HelpdeskReport`](docs/commands/Export-HelpdeskReport.md) | One self-contained HTML file to attach to the ticket, in a dark or light theme | Creates one file |

## Help in the shell

Every command has a complete help page, readable without a browser:

```powershell
Get-Help Test-NetworkHealth -Full        # description, parameters, examples, notes
Get-Help Test-NetworkHealth -Examples    # only the examples
Get-Help Test-NetworkHealth -Online      # opens the reference page of this repository
Get-Help about_HelpdeskToolkit           # overview: commands, safety, a typical ticket
```

## Examples

The [examples](examples/README.md) folder combines the commands for common tickets: a short summary for the ticket notes, a disk space triage that cleans only when asked, a software inventory as CSV, and the sample report above.

```powershell
.\examples\Get-TicketSummary.ps1 -TicketNumber 'INC-0042' -CopyToClipboard
.\examples\Invoke-DiskSpaceTriage.ps1
```

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
│   └── en-US/              about_HelpdeskToolkit help topic
├── examples/               scripts for common tickets and the sample report
├── Tests/                  Pester tests and analyzer settings for the tests
├── docs/                   architecture, design decisions, one page per command, screenshots
├── Invoke-Tests.ps1        PSScriptAnalyzer and Pester, locally and in the CI
├── CHANGELOG.md            what changed in each version
└── CONTRIBUTING.md         how to add a command and the rules it must follow
```

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before adding a command. Released under the [MIT License](LICENSE).
