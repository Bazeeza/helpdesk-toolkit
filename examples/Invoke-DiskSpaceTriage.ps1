#Requires -Version 5.1

<#
.SYNOPSIS
    "My disk is full": checks the disks, previews what a cleanup of the
    temporary folders would free, and cleans only when asked.

.DESCRIPTION
    The usual order of a low disk space ticket, in one script:

      1  Get-DiskHealth           which volume is low, and is the drive healthy?
      2  Clear-TempFiles -WhatIf  how much would removing old temporary files free?
      3  Clear-TempFiles          only with -Clean, and Clear-TempFiles still asks
                                  before each folder
      4  Get-DiskHealth           the free space after the cleanup

    Without -Clean, nothing is removed. A drive that reports a health
    problem is a hardware ticket: the script says so and does not clean,
    because freeing space does not fix a failing drive and the user's data
    should be backed up first.

.PARAMETER OlderThanDays
    Minimum age of the temporary files to remove. Default 7.

.PARAMETER Clean
    Removes the files after the preview. Clear-TempFiles asks for a
    confirmation before each folder.

.EXAMPLE
    .\examples\Invoke-DiskSpaceTriage.ps1

    Disk status and cleanup preview. Removes nothing.

.EXAMPLE
    .\examples\Invoke-DiskSpaceTriage.ps1 -Clean

    Same preview, then the cleanup after a confirmation, then the new free
    space.

.OUTPUTS
    None. The steps are written to the information stream and the console.
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 3650)]
    [int]$OlderThanDays = 7,

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$manifest = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
Import-Module -Name $manifest -Force

Write-Information -MessageData '1. Disk health' -InformationAction Continue
$before = Get-DiskHealth
$before.Volumes | Format-Table -Property Drive, Label, Size, Free, FreePercent, Status -AutoSize | Out-Host
foreach ($issue in $before.Issues) {
    Write-Warning -Message $issue
}

$failing = @($before.PhysicalDisks | Where-Object { $_.HealthStatus -in 'Warning', 'Unhealthy' })
if ($failing.Count -gt 0) {
    Write-Warning -Message ('{0} physical disk(s) report a health problem: back up the data and escalate as hardware. No cleanup is done.' -f $failing.Count)
    return
}

Write-Information -MessageData "2. Cleanup preview (files older than $OlderThanDays days)" -InformationAction Continue
$preview = Clear-TempFiles -OlderThanDays $OlderThanDays -WhatIf
$preview | Format-Table -Property Location, Path, FilesFound, SizeFound -AutoSize | Out-Host

if (-not $Clean) {
    Write-Information -MessageData 'Nothing was removed. Run again with -Clean to remove these files.' -InformationAction Continue
    return
}

Write-Information -MessageData '3. Cleanup' -InformationAction Continue
$result = Clear-TempFiles -OlderThanDays $OlderThanDays
$result | Format-Table -Property Location, FilesRemoved, FilesSkipped, Freed -AutoSize | Out-Host

Write-Information -MessageData '4. Free space after the cleanup' -InformationAction Continue
(Get-DiskHealth).Volumes | Format-Table -Property Drive, Free, FreePercent, Status -AutoSize | Out-Host
