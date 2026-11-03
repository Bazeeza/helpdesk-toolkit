# Contributing

Thank you for helping improve `HelpdeskToolkit`. Every change goes through a pull request and must pass the [CI](.github/workflows/ci.yml).

## Before you open a pull request

```powershell
# Once, for the current user only
Install-Module -Name Pester -MinimumVersion 5.2.0 -Scope CurrentUser -SkipPublisherCheck -Force
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Every time: the same checks as the CI
.\Invoke-Tests.ps1
```

Run it in **Windows PowerShell 5.1** (`powershell.exe`) at least once: it is the shell the module targets.

## Adding a command

1. Create `HelpdeskToolkit/Public/<Verb>-<Noun>.ps1` containing one function with the same name.
2. Add the name to `FunctionsToExport` in `HelpdeskToolkit/HelpdeskToolkit.psd1`.
3. Create `Tests/Public/<Verb>-<Noun>.Tests.ps1`. Mock every CIM, registry and network call: tests must pass on any computer, without administrator rights and without reading real data.
4. Add a line to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md).

`Tests/Module.Tests.ps1` then checks the new command automatically: approved verb, advanced function, synopsis, description, example, help for every parameter, file encoding.

## Rules for every command

| Rule | Why |
|---|---|
| Use an approved verb (`Get-Verb`) | PowerShell warns on import otherwise, and users guess command names from the verb. |
| `[CmdletBinding()]` and comment-based help | Gives `-Verbose`, `-ErrorAction` and a complete `Get-Help` page. |
| Return objects, never formatted text | Output can be filtered, exported to CSV and reused by `Export-HelpdeskReport`. |
| Read-only unless the name says otherwise | A diagnostic tool must not change the computer it diagnoses. |
| Any change uses `SupportsShouldProcess` | `-WhatIf` shows what would happen and `-Confirm` asks first; call `$PSCmdlet.ShouldProcess()` right before each change. |
| No `Win32_Product` | Querying it starts a Windows Installer consistency check on every MSI package (see [architecture](docs/architecture.md#why-the-registry-and-not-win32_product)). |
| Windows PowerShell 5.1 syntax | No ternary `? :`, no `??`, no `&&` / `\|\|` between commands; PSScriptAnalyzer checks this. |
| ASCII source files | Windows PowerShell 5.1 misreads UTF-8 without a byte order mark. |
| No personal or company data | No real computer names, user names, serial numbers or IP addresses in code, tests, examples or screenshots. Use `PC-EXAMPLE01`, `jdoe`, `192.0.2.10` (documentation range). |

## Commit messages

Imperative mood, in English, one logical change per commit: `Add Get-SystemReport with CIM mocks in tests`, not `Update files`.

---

**Reference:** [Approved verbs for PowerShell commands (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) · [Everything you wanted to know about ShouldProcess (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess) · [Pester documentation](https://pester.dev/docs/quick-start) · [RFC 5737, IPv4 addresses reserved for documentation](https://www.rfc-editor.org/rfc/rfc5737)
