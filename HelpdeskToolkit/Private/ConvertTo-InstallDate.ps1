function ConvertTo-InstallDate {
    <#
    .SYNOPSIS
        Converts the InstallDate text of an uninstall registry key into a date.

    .DESCRIPTION
        Private helper used by Get-InstalledSoftware. Windows Installer writes
        InstallDate as text in the yyyyMMdd format (for example "20260115"),
        but other installers write what they want: "2026-01-15", "1/15/2026"
        or nothing at all.

        The helper tries the known formats with the invariant culture, so the
        result does not depend on the regional settings of the workstation.
        A value it cannot read, or a date before 1980, returns nothing
        instead of a wrong date: an empty install date is honest, a date in
        year 1601 or 9999 is not.

    .PARAMETER Value
        Raw InstallDate value read from the registry. Empty values are
        accepted and return nothing.

    .EXAMPLE
        ConvertTo-InstallDate -Value '20260115'

        Returns the date January 15, 2026.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    begin {
        # yyyyMMdd is the documented format; the others are seen in the wild
        $formats = [string[]]@('yyyyMMdd', 'yyyy-MM-dd', 'yyyy/MM/dd', 'M/d/yyyy')
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $style = [System.Globalization.DateTimeStyles]::None
        $oldest = [datetime]'1980-01-01'
    }

    process {
        if ($null -eq $Value) {
            return
        }
        $text = ([string]$Value).Trim()
        if (-not $text) {
            return
        }

        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($text, $formats, $culture, $style, [ref]$parsed) -and $parsed -ge $oldest) {
            $parsed
        }
    }
}
