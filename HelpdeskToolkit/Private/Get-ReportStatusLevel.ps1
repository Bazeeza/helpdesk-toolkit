function Get-ReportStatusLevel {
    <#
    .SYNOPSIS
        Maps a status word of the module to one of the four colour levels of
        the HTML report: ok, warn, crit or muted.

    .DESCRIPTION
        Private helper of the HTML report. The commands of the module use
        different words for the same idea (Pass for a network step, OK for a
        volume, Healthy for a drive). The report shows them with one colour
        per level, so a technician reads the page by colour first:

          ok      OK, Pass, Healthy
          warn    Warning
          crit    Critical, Fail, Unhealthy
          muted   Unknown, Skipped, Not collected, empty or any other word

        The comparison ignores case. An unknown word is never shown as
        healthy.

    .PARAMETER Status
        The status word to map. $null and an empty string give muted.

    .EXAMPLE
        Get-ReportStatusLevel -Status 'Pass'
        ok
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Status
    )

    switch -Regex ($Status) {
        '^\s*(OK|Pass|Healthy)\s*$' { return 'ok' }
        '^\s*Warning\s*$' { return 'warn' }
        '^\s*(Critical|Fail|Unhealthy)\s*$' { return 'crit' }
    }
    'muted'
}
