function Get-StorageReliability {
    <#
    .SYNOPSIS
        Returns the reliability counters of one physical disk (temperature,
        wear, power-on hours, uncorrected errors), or nothing when Windows
        does not give them.

    .DESCRIPTION
        Private helper of Get-DiskHealth. The counters are the
        MSFT_StorageReliabilityCounter instance associated with an
        MSFT_PhysicalDisk instance, the same data as the
        Get-StorageReliabilityCounter cmdlet.

        Windows usually returns the counters only to an elevated session:
        without administrator rights the association is simply empty, with
        no error. Some drives (USB adapters, virtual disks) never report
        them. In every case this helper returns nothing instead of failing,
        and Get-DiskHealth marks the counters as not available.

    .PARAMETER PhysicalDisk
        An MSFT_PhysicalDisk CIM instance, as returned by Get-CimInstance.

    .EXAMPLE
        $disk = Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName 'MSFT_PhysicalDisk' | Select-Object -First 1
        Get-StorageReliability -PhysicalDisk $disk
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param(
        # Typed [object] so that the tests of Get-DiskHealth can pass fake
        # disks; anything that is not a CIM instance returns nothing
        [Parameter(Mandatory = $true)]
        [object]$PhysicalDisk
    )

    if ($PhysicalDisk -isnot [Microsoft.Management.Infrastructure.CimInstance]) {
        Write-Verbose -Message 'Reliability counters not available: the disk is not a CIM instance'
        return
    }

    try {
        Get-CimAssociatedInstance -InputObject $PhysicalDisk -ResultClassName 'MSFT_StorageReliabilityCounter' -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Verbose -Message "Reliability counters not available: $($_.Exception.Message)"
    }
}
