function Format-ByteSize {
    <#
    .SYNOPSIS
        Converts a number of bytes into a readable size such as "465.76 GB".

    .DESCRIPTION
        Private helper shared by the reports of the module (memory, disks,
        installed software). It uses binary units (1 KB = 1024 bytes), the
        same convention as File Explorer and Disk Management, so the value a
        technician reads in the report matches what Windows shows.

        The decimal separator is always a dot, whatever the regional settings
        of the workstation, so reports stay comparable between computers.

    .PARAMETER Bytes
        Size in bytes. Zero or positive. Accepts pipeline input.

    .PARAMETER Decimals
        Number of decimals to keep (0 to 4). Trailing zeros are removed.

    .EXAMPLE
        Format-ByteSize -Bytes 500107862016
        465.76 GB

    .EXAMPLE
        (Get-CimInstance Win32_LogicalDisk).Size | Format-ByteSize -Decimals 1
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$Bytes,

        [ValidateRange(0, 4)]
        [int]$Decimals = 2
    )

    begin {
        $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
    }

    process {
        $value = $Bytes
        $index = 0
        while ($value -ge 1024 -and $index -lt ($units.Count - 1)) {
            $value = $value / 1024
            $index++
        }

        # Bytes are whole numbers: never show "512.00 B"
        if ($index -eq 0) {
            $Decimals = 0
        }

        # AwayFromZero: 2.5 becomes 3 as people expect, not 2 (banker's rounding)
        $rounded = [math]::Round($value, $Decimals, [System.MidpointRounding]::AwayFromZero)
        '{0} {1}' -f $rounded.ToString($culture), $units[$index]
    }
}
