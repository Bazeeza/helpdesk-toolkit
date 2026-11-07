function ConvertFrom-StorageCode {
    <#
    .SYNOPSIS
        Converts a numeric code of the Windows storage classes into the text
        shown by Get-PhysicalDisk, such as 4 -> "SSD".

    .DESCRIPTION
        Private helper of Get-DiskHealth. The MSFT_PhysicalDisk class of the
        root/Microsoft/Windows/Storage namespace returns numbers; the
        Get-PhysicalDisk cmdlet translates them for display. Reading the
        class through Get-CimInstance keeps one mocking boundary for the
        tests, so the translation is done here, with the values documented
        by Microsoft.

        A code that is not in the table is returned as "Unknown (<code>)"
        rather than guessed, and an empty value returns "Unknown".

    .PARAMETER Property
        Which property the code comes from: HealthStatus, MediaType, BusType
        or OperationalStatus.

    .PARAMETER Code
        The numeric value read from the class.

    .EXAMPLE
        ConvertFrom-StorageCode -Property MediaType -Code 4
        SSD

    .EXAMPLE
        ConvertFrom-StorageCode -Property BusType -Code 17
        NVMe
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HealthStatus', 'MediaType', 'BusType', 'OperationalStatus')]
        [string]$Property,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Code
    )

    # MSFT_PhysicalDisk (Windows Storage Management API)
    $tables = @{
        HealthStatus      = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' }
        MediaType         = @{ 0 = 'Unspecified'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
        BusType           = @{
            0 = 'Unknown'; 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'
            6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'; 9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'
            12 = 'SD'; 13 = 'MMC'; 15 = 'File Backed Virtual'; 16 = 'Storage Spaces'; 17 = 'NVMe'
        }
        # Standard values of OperationalStatus (CIM_ManagedSystemElement)
        OperationalStatus = @{
            0 = 'Unknown'; 1 = 'Other'; 2 = 'OK'; 3 = 'Degraded'; 4 = 'Stressed'
            5 = 'Predictive Failure'; 6 = 'Error'; 7 = 'Non-Recoverable Error'; 8 = 'Starting'
            9 = 'Stopping'; 10 = 'Stopped'; 11 = 'In Service'; 12 = 'No Contact'
            13 = 'Lost Communication'; 14 = 'Aborted'; 15 = 'Dormant'
            16 = 'Supporting Entity in Error'; 17 = 'Completed'; 18 = 'Power Mode'
        }
    }

    $number = 0
    if ($null -eq $Code -or -not [int]::TryParse([string]$Code, [ref]$number)) {
        return 'Unknown'
    }

    $table = $tables[$Property]
    if ($table.ContainsKey($number)) {
        return $table[$number]
    }
    'Unknown ({0})' -f $number
}
