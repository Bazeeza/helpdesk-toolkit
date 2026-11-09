# Examples

Scripts that combine the commands of the module for common tickets. Each one loads the module from this repository (`..\HelpdeskToolkit`), has its own help (`Get-Help .\examples\<script>.ps1 -Full`) and is checked by PSScriptAnalyzer and Pester like the module.

| Script | Ticket | Changes the computer? |
|---|---|---|
| [`Get-TicketSummary.ps1`](Get-TicketSummary.ps1) | Any ticket: a few lines for the notes (system, network result, disk issues), optionally copied to the clipboard | No |
| [`Invoke-DiskSpaceTriage.ps1`](Invoke-DiskSpaceTriage.ps1) | "My disk is full": disk health, cleanup preview, then cleanup only with `-Clean` | Only with `-Clean`, after a confirmation |
| [`Export-SoftwareInventory.ps1`](Export-SoftwareInventory.ps1) | "Which version is installed?": inventory as a CSV file that opens in Excel | Creates one CSV file |
| [`New-SampleReport.ps1`](New-SampleReport.ps1) | Demonstration: the HTML report built from fictitious results | Creates one HTML file |

```powershell
# From the root of the repository
.\examples\Get-TicketSummary.ps1 -TicketNumber 'INC-0042' -CopyToClipboard
.\examples\Invoke-DiskSpaceTriage.ps1
.\examples\Export-SoftwareInventory.ps1 -Name '*VPN*'
.\examples\New-SampleReport.ps1 -Path "$env:TEMP\sample.html" -Force | Invoke-Item
```

> [!NOTE]
> `Get-TicketSummary.ps1` leaves out the serial number, the MAC address and the IP address: the notes of a ticket are often read by more people than its attachments. The CSV inventory and the HTML report describe the real computer: attach them to the ticket only.

## Why a sample report

`Export-HelpdeskReport` always reads the computer it runs on, so a real report contains a real serial number, MAC address and program list. `New-SampleReport.ps1` gives the same page builder invented values instead: the name `PC-EXAMPLE01`, documentation addresses from `192.0.2.0/24` ([RFC 5737](https://www.rfc-editor.org/rfc/rfc5737)) and the documentation MAC block `00-00-5E-00-53-xx` ([RFC 7042](https://www.rfc-editor.org/rfc/rfc7042)). The screenshots of the [README](../README.md#what-the-report-looks-like) come from it.

The page builder is a private function of the module; the script calls it inside the scope of the module, which is fine for a demonstration but not for production scripts.
