function ConvertTo-StatusBadge {
    <#
    .SYNOPSIS
        Returns the HTML of a coloured status badge, for example
        <span class="badge badge-ok">Pass</span>.

    .DESCRIPTION
        Private helper of the HTML report. The colour comes from
        Get-ReportStatusLevel; the word itself is always written, so the
        status stays readable when the page is printed in black and white
        or read by a screen reader. The word is HTML-encoded.

    .PARAMETER Status
        The status word to show. $null or an empty string shows "Unknown".

    .EXAMPLE
        ConvertTo-StatusBadge -Status 'Warning'
        <span class="badge badge-warn">Warning</span>
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Status
    )

    $word = $Status
    if (-not $word -or -not $word.Trim()) {
        $word = 'Unknown'
    }
    '<span class="badge badge-{0}">{1}</span>' -f (Get-ReportStatusLevel -Status $word), (ConvertTo-HtmlText -Value $word.Trim())
}
