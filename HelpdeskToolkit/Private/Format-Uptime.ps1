function Format-Uptime {
    <#
    .SYNOPSIS
        Converts a duration into a short text such as "12d 4h 7m".

    .DESCRIPTION
        Private helper used by the reports of the module. The uptime is kept
        as a TimeSpan in the objects (so it can be sorted and compared) and
        this text is added for people reading the report or the ticket.

        Days and hours are omitted while they are zero, minutes are always
        shown, seconds are dropped: "45m", "3h 0m", "12d 4h 7m".

    .PARAMETER Duration
        Duration to format. Zero or positive. Accepts pipeline input.

    .EXAMPLE
        Format-Uptime -Duration (New-TimeSpan -Days 12 -Hours 4 -Minutes 7)
        12d 4h 7m
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({ $_ -ge [timespan]::Zero })]
        [timespan]$Duration
    )

    process {
        # Days is not limited to 0-30: 400 days of uptime stays "400d"
        $parts = New-Object -TypeName 'System.Collections.Generic.List[string]'
        if ($Duration.Days -gt 0) {
            $parts.Add(('{0}d' -f $Duration.Days))
        }
        if ($Duration.Days -gt 0 -or $Duration.Hours -gt 0) {
            $parts.Add(('{0}h' -f $Duration.Hours))
        }
        $parts.Add(('{0}m' -f $Duration.Minutes))
        $parts -join ' '
    }
}
