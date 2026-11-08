function ConvertTo-ReportTable {
    <#
    .SYNOPSIS
        Builds the HTML of a table from objects: one row per object, one
        column per property, every cell HTML-encoded.

    .DESCRIPTION
        Private helper of the HTML report. ConvertTo-Html exists in
        PowerShell, but it writes a whole page, cannot colour a status cell
        and differs between Windows PowerShell 5.1 and PowerShell 7. This
        helper only writes a <table>, the same way in both:

          - a property listed in StatusProperty is shown as a coloured badge
          - a property listed in MeterProperty (a percentage from 0 to 100)
            is shown as a small bar followed by the value
          - every other value goes through ConvertTo-HtmlText

        A property that an object does not have gives an empty cell. When
        there is no object, a short paragraph replaces the table.

        The table is wrapped in a <div class="table-wrap"> so that a wide
        table scrolls on a narrow screen instead of breaking the page.

    .PARAMETER InputObject
        Objects to show, one per row. $null items are ignored.

    .PARAMETER Property
        Names of the properties to show, in column order.

    .PARAMETER Header
        Column titles, in the same order as Property. By default the
        property names are used.

    .PARAMETER StatusProperty
        Properties shown as a status badge.

    .PARAMETER MeterProperty
        Properties shown as a percentage bar.

    .PARAMETER Class
        Extra CSS class of the table, for example "facts" for a two-column
        list of names and values. Letters, digits and dashes only.

    .PARAMETER NoHeader
        Writes no header row, for a list of names and values.

    .PARAMETER EmptyText
        Text shown instead of the table when there is no object.

    .EXAMPLE
        ConvertTo-ReportTable -InputObject $health.Checks -Property Step, Name, Status, Detail -StatusProperty Status
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Property,

        [string[]]$Header,

        [string[]]$StatusProperty = @(),

        [string[]]$MeterProperty = @(),

        [ValidatePattern('^[A-Za-z0-9-]*$')]
        [string]$Class,

        [switch]$NoHeader,

        [string]$EmptyText = 'Nothing to show.'
    )

    $rows = @($InputObject | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        return '<p class="empty">{0}</p>' -f (ConvertTo-HtmlText -Value $EmptyText)
    }

    if (-not $Header) {
        $Header = $Property
    }
    if ($Header.Count -ne $Property.Count) {
        throw [System.ArgumentException]::new("Header has $($Header.Count) titles for $($Property.Count) properties.")
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $tableClass = 'report'
    if ($Class) {
        $tableClass = "report $Class"
    }

    $html = [System.Text.StringBuilder]::new()
    [void]$html.Append('<div class="table-wrap"><table class="').Append($tableClass).Append('">')

    if (-not $NoHeader) {
        [void]$html.Append('<thead><tr>')
        foreach ($title in $Header) {
            [void]$html.Append('<th scope="col">').Append((ConvertTo-HtmlText -Value $title)).Append('</th>')
        }
        [void]$html.Append('</tr></thead>')
    }

    [void]$html.Append('<tbody>')
    foreach ($row in $rows) {
        [void]$html.Append('<tr>')
        foreach ($name in $Property) {
            $value = $null
            $member = $row.PSObject.Properties[$name]
            if ($member) {
                $value = $member.Value
            }

            if ($name -in $StatusProperty) {
                $cell = ConvertTo-StatusBadge -Status ([string]$value)
            }
            elseif ($name -in $MeterProperty -and $null -ne $value -and "$value" -ne '') {
                # Clamp to 0..100 so a wrong value cannot draw outside the cell.
                # Double literals on purpose: with 0 and 100, PowerShell picks
                # the Int32 overload of Min and Max and rounds 25.3 to 25.
                $percent = [math]::Min([double]100, [math]::Max([double]0, [double]$value))
                $width = $percent.ToString('0.#', $culture)
                $cell = '<span class="meter"><span style="width:{0}%"></span></span> {1} %' -f $width, (ConvertTo-HtmlText -Value $value)
            }
            else {
                $cell = ConvertTo-HtmlText -Value $value
            }
            [void]$html.Append('<td>').Append($cell).Append('</td>')
        }
        [void]$html.Append('</tr>')
    }
    [void]$html.Append('</tbody></table></div>')

    $html.ToString()
}
