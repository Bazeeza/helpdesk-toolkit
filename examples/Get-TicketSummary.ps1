#Requires -Version 5.1

<#
.SYNOPSIS
    Runs the read-only checks of the module and writes a short plain-text
    summary to paste in the notes of a ticket.

.DESCRIPTION
    The HTML report is the evidence to attach; the ticket notes need a few
    lines that the next technician reads in ten seconds. This script runs
    Get-SystemReport, Test-NetworkHealth and Get-DiskHealth on the local
    computer and writes:

      - the computer, its model, Windows build and uptime;
      - the network result: every step answered, or the layer that failed
        and its diagnosis;
      - the disk status and each issue found.

    Nothing is changed on the computer. With -CopyToClipboard the text is
    also copied, ready to paste in the ticket.

    The summary leaves out the serial number, the MAC address and the IP
    address on purpose: the notes of a ticket are often read by more people
    than its attachments.

.PARAMETER TicketNumber
    Ticket number written on the first line, for example INC-0042.

.PARAMETER CopyToClipboard
    Also copies the summary to the clipboard.

.EXAMPLE
    .\examples\Get-TicketSummary.ps1 -TicketNumber 'INC-0042'

    Writes the summary in the console.

.EXAMPLE
    .\examples\Get-TicketSummary.ps1 -TicketNumber 'INC-0042' -CopyToClipboard

    Writes the summary and copies it, ready to paste in the ticket notes.

.OUTPUTS
    System.String
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [ValidatePattern('^[A-Za-z0-9._#-]{1,40}$')]
    [string]$TicketNumber,

    [switch]$CopyToClipboard
)

$ErrorActionPreference = 'Stop'
$manifest = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
Import-Module -Name $manifest -Force

$system = Get-SystemReport
$network = Test-NetworkHealth
$disk = Get-DiskHealth

$lines = [System.Collections.Generic.List[string]]::new()
$title = 'Checks on {0}, {1}' -f $system.ComputerName, (Get-Date -Format 'yyyy-MM-dd HH:mm')
if ($TicketNumber) {
    $title = "$TicketNumber - $title"
}
$lines.Add($title)
$lines.Add(('System : {0} {1}, {2} build {3}, up {4}' -f $system.Manufacturer, $system.Model, $system.OperatingSystem, $system.Build, $system.UptimeText))

if ($network.Healthy) {
    $warnings = @($network.Checks | Where-Object { $_.Status -eq 'Warning' } | ForEach-Object { $_.Name })
    $text = 'every step answered'
    if ($warnings.Count -gt 0) {
        $text += ' (warning: {0})' -f ($warnings -join ', ')
    }
    $lines.Add("Network: $text")
}
else {
    $lines.Add(('Network: stops at {0} - {1}' -f $network.FailedStep, $network.Diagnosis))
}

$lines.Add("Disk   : $($disk.Status)")
foreach ($issue in $disk.Issues) {
    $lines.Add("         - $issue")
}

$summary = $lines -join [Environment]::NewLine
if ($CopyToClipboard) {
    Set-Clipboard -Value $summary
    Write-Verbose -Message 'Summary copied to the clipboard.'
}
$summary
