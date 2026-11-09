#Requires -Version 5.1

<#
.SYNOPSIS
    Saves the software inventory of the computer as a CSV file that opens
    directly in Excel.

.DESCRIPTION
    Writes the result of Get-InstalledSoftware with the columns a ticket
    or an audit needs: computer, name, version, publisher, install date,
    scope and architecture. Use it to compare two computers, to check a
    version before an update, or to attach the list to a ticket.

    The file is UTF-8 with a byte order mark, so Excel shows accented
    publisher names correctly. An existing file is replaced only with
    -Force. The script supports -WhatIf.

.PARAMETER Path
    CSV file to create. The default is
    software-<computer>-<yyyyMMdd>.csv in the current folder.

.PARAMETER Name
    Display names to keep, with wildcards, for example '*Office*'. All
    programs by default.

.PARAMETER Force
    Replaces the file if it already exists.

.EXAMPLE
    .\examples\Export-SoftwareInventory.ps1

    Inventory of every program in the current folder.

.EXAMPLE
    .\examples\Export-SoftwareInventory.ps1 -Name '*VPN*', '*Remote*' -Path .\remote-tools.csv

    Only the VPN and remote support tools, for example before an audit.

.OUTPUTS
    System.IO.FileInfo
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([System.IO.FileInfo])]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Path = ('software-{0}-{1}.csv' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd')),

    [ValidateNotNullOrEmpty()]
    [string[]]$Name = @('*'),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$manifest = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
Import-Module -Name $manifest -Force

$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
if ((Test-Path -LiteralPath $target) -and -not $Force) {
    throw "The file '$target' already exists. Use -Force to replace it."
}

$programs = @(Get-InstalledSoftware -Name $Name)
if ($PSCmdlet.ShouldProcess($target, "Write the inventory of $($programs.Count) program(s)")) {
    $rows = $programs | Select-Object -Property ComputerName, Name, Version, Publisher,
    @{ Name = 'InstallDate'; Expression = { if ($_.InstallDate) { $_.InstallDate.ToString('yyyy-MM-dd') } } },
    Scope, Architecture
    # Export-Csv -Encoding UTF8 writes a BOM in Windows PowerShell 5.1 but not in 7: write it explicitly
    $csv = ($rows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($target, $csv + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($true))
    Get-Item -LiteralPath $target
}
