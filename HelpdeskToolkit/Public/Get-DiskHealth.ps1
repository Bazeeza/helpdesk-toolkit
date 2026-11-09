function Get-DiskHealth {
    <#
    .SYNOPSIS
        Checks the free space of every local fixed volume and the health
        reported by every physical disk, and gives one overall status.

    .DESCRIPTION
        Get-DiskHealth answers the two disk questions of a ticket: "is the
        computer running out of space?" and "is the drive itself failing?".

        Volumes are read from Win32_LogicalDisk (local fixed disks only). A
        volume is Warning below WarningPercent of free space and Critical
        below CriticalPercent.

        Physical disks are read from MSFT_PhysicalDisk, the class behind
        Get-PhysicalDisk. Its HealthStatus is the verdict of the drive and
        its driver (Healthy, Warning or Unhealthy). When Windows also gives
        the reliability counters (MSFT_StorageReliabilityCounter, usually
        only to an administrator), the command adds the temperature, the
        wear, the power-on hours and the uncorrected read and write errors.
        A disk is raised to Warning when it reports uncorrected errors, a
        wear of 100 % or more, or a temperature at or above its maximum.

        The overall Status is the worst status found, in this order: OK,
        Unknown, Warning, Critical. Issues lists each problem in one line,
        ready to paste in the ticket. The command only reads.

    .PARAMETER WarningPercent
        Free space, in percent of the volume size, under which a volume is
        reported as Warning. Default 15.

    .PARAMETER CriticalPercent
        Free space, in percent of the volume size, under which a volume is
        reported as Critical. Default 5. Must be lower than WarningPercent.

    .EXAMPLE
        Get-DiskHealth

        Overall status, the issues found, the volumes and the physical disks.

    .EXAMPLE
        Get-DiskHealth | Select-Object -ExpandProperty Issues

        Only the problems, one line each, to copy into the ticket.

    .EXAMPLE
        Get-DiskHealth | Select-Object -ExpandProperty PhysicalDisks | Format-List *

        Every value of every physical disk. Run PowerShell as administrator
        to get the temperature, wear and error counters.

    .EXAMPLE
        Get-DiskHealth -WarningPercent 20 -CriticalPercent 10

        Stricter thresholds, for example on a small SSD.

    .INPUTS
        None

        This command does not accept pipeline input.

    .OUTPUTS
        HelpdeskToolkit.DiskHealth

        One object with Status, Issues, Volumes and PhysicalDisks.

    .NOTES
        Read-only. Free space and HealthStatus need no administrator rights;
        the reliability counters usually do. A value that Windows does not
        give is reported as Unknown, never as OK. Local computer only.

    .LINK
        https://github.com/Bazeeza/helpdesk-toolkit/blob/main/docs/commands/Get-DiskHealth.md

    .LINK
        Clear-TempFiles

    .LINK
        https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-physicaldisk

    .LINK
        https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-storagereliabilitycounter
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.DiskHealth')]
    param(
        [ValidateRange(1, 99)]
        [int]$WarningPercent = 15,

        [ValidateRange(1, 99)]
        [int]$CriticalPercent = 5
    )

    if ($CriticalPercent -ge $WarningPercent) {
        throw [System.ArgumentException]::new("CriticalPercent ($CriticalPercent) must be lower than WarningPercent ($WarningPercent).")
    }

    # Worst status wins; Unknown is worse than OK because health is not proven
    $rank = @{ OK = 0; Unknown = 1; Warning = 2; Critical = 3 }
    $issues = [System.Collections.Generic.List[string]]::new()

    # --- Volumes: free space ------------------------------------------------
    try {
        $logicalDisks = @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' -ErrorAction Stop)
    }
    catch {
        Write-Error -Message "Cannot read the volumes of this computer. $($_.Exception.Message)" -Category 'ReadError'
        return
    }

    $volumes = @(
        foreach ($logicalDisk in ($logicalDisks | Sort-Object -Property DeviceID)) {
            $size = [double]$logicalDisk.Size
            $free = [double]$logicalDisk.FreeSpace
            $freePercent = $null
            $status = 'Unknown'
            if ($size -gt 0) {
                $freePercent = [math]::Round(($free / $size) * 100, 1)
                if ($freePercent -lt $CriticalPercent) {
                    $status = 'Critical'
                }
                elseif ($freePercent -lt $WarningPercent) {
                    $status = 'Warning'
                }
                else {
                    $status = 'OK'
                }
            }

            $volume = [pscustomobject]@{
                PSTypeName  = 'HelpdeskToolkit.DiskHealth.Volume'
                Drive       = $logicalDisk.DeviceID
                Label       = $logicalDisk.VolumeName
                FileSystem  = $logicalDisk.FileSystem
                Size        = Format-ByteSize -Bytes $size
                Free        = Format-ByteSize -Bytes $free
                FreePercent = $freePercent
                SizeBytes   = [long]$size
                FreeBytes   = [long]$free
                Status      = $status
            }
            $volume | Add-Member -MemberType ScriptMethod -Name 'ToString' -Force -Value {
                '{0} {1} free ({2} %) {3}' -f $this.Drive, $this.Free, $this.FreePercent, $this.Status
            }

            switch ($status) {
                'Critical' { $issues.Add(('{0} only {1} free ({2} %), critical below {3} %' -f $volume.Drive, $volume.Free, $freePercent, $CriticalPercent)) }
                'Warning' { $issues.Add(('{0} {1} free ({2} %), warning below {3} %' -f $volume.Drive, $volume.Free, $freePercent, $WarningPercent)) }
                'Unknown' { $issues.Add(('{0} size not reported, free space unknown' -f $volume.Drive)) }
            }
            $volume
        }
    )

    # --- Physical disks: health reported by the drive ------------------------
    try {
        $storageDisks = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName 'MSFT_PhysicalDisk' -ErrorAction Stop)
        if ($storageDisks.Count -eq 0) {
            $issues.Add('Physical disk health not available: Windows reported no physical disk')
        }
    }
    catch {
        # Missing on some virtual machines or when the storage service is stopped
        $storageDisks = @()
        $issues.Add("Physical disk health not available: $($_.Exception.Message)")
        Write-Warning -Message "Physical disk health not available: $($_.Exception.Message)"
    }

    # DeviceId is the disk number as text: sort 2 before 10
    $byNumber = {
        $number = 0
        if ([int]::TryParse([string]$_.DeviceId, [ref]$number)) { $number } else { [int]::MaxValue }
    }

    $physicalDisks = @(
        foreach ($storageDisk in ($storageDisks | Sort-Object -Property $byNumber)) {
            $healthStatus = ConvertFrom-StorageCode -Property 'HealthStatus' -Code $storageDisk.HealthStatus
            $operationalStatus = @(
                foreach ($code in @($storageDisk.OperationalStatus)) {
                    ConvertFrom-StorageCode -Property 'OperationalStatus' -Code $code
                }
            ) -join ', '

            $status = switch ($healthStatus) {
                'Healthy' { 'OK' }
                'Warning' { 'Warning' }
                'Unhealthy' { 'Critical' }
                default { 'Unknown' }
            }

            $name = ([string]$storageDisk.FriendlyName).Trim()
            $label = 'Disk {0} ({1})' -f $storageDisk.DeviceId, $name
            $diskIssues = [System.Collections.Generic.List[string]]::new()
            if ($status -ne 'OK') {
                $diskIssues.Add(('{0}: health {1}, operational status {2}' -f $label, $healthStatus, $operationalStatus))
            }

            # Counters: often empty without administrator rights
            $counter = Get-StorageReliability -PhysicalDisk $storageDisk
            $temperature = $null
            $temperatureMax = $null
            $wear = $null
            $powerOnHours = $null
            $readErrors = $null
            $writeErrors = $null
            if ($counter) {
                $temperature = $counter.Temperature
                $temperatureMax = $counter.TemperatureMax
                $wear = $counter.Wear
                $powerOnHours = $counter.PowerOnHours
                $readErrors = $counter.ReadErrorsUncorrected
                $writeErrors = $counter.WriteErrorsUncorrected

                $counterWarnings = @()
                if ([long]$readErrors -gt 0) { $counterWarnings += "$readErrors uncorrected read errors" }
                if ([long]$writeErrors -gt 0) { $counterWarnings += "$writeErrors uncorrected write errors" }
                if ($null -ne $wear -and [int]$wear -ge 100) { $counterWarnings += "wear $wear % (estimated limit reached)" }
                if ([int]$temperatureMax -gt 0 -and [int]$temperature -ge [int]$temperatureMax) {
                    $counterWarnings += "temperature $temperature C at or above its maximum of $temperatureMax C"
                }
                if ($counterWarnings.Count -gt 0) {
                    if ($rank[$status] -lt $rank['Warning']) {
                        $status = 'Warning'
                    }
                    $diskIssues.Add(('{0}: {1}' -f $label, ($counterWarnings -join ', ')))
                }
            }

            foreach ($diskIssue in $diskIssues) {
                $issues.Add($diskIssue)
            }

            $size = [double]$storageDisk.Size
            $physicalDisk = [pscustomobject]@{
                PSTypeName             = 'HelpdeskToolkit.DiskHealth.PhysicalDisk'
                DeviceId               = [string]$storageDisk.DeviceId
                Name                   = $name
                MediaType              = ConvertFrom-StorageCode -Property 'MediaType' -Code $storageDisk.MediaType
                BusType                = ConvertFrom-StorageCode -Property 'BusType' -Code $storageDisk.BusType
                Size                   = Format-ByteSize -Bytes $size
                SizeBytes              = [long]$size
                HealthStatus           = $healthStatus
                OperationalStatus      = $operationalStatus
                ReliabilityAvailable   = [bool]$counter
                Temperature            = $temperature
                TemperatureMax         = $temperatureMax
                Wear                   = $wear
                PowerOnHours           = $powerOnHours
                ReadErrorsUncorrected  = $readErrors
                WriteErrorsUncorrected = $writeErrors
                Status                 = $status
            }
            $physicalDisk | Add-Member -MemberType ScriptMethod -Name 'ToString' -Force -Value {
                'Disk {0} {1} {2} {3}' -f $this.DeviceId, $this.MediaType, $this.Size, $this.HealthStatus
            }
            $physicalDisk
        }
    )

    if (@($physicalDisks | Where-Object { -not $_.ReliabilityAvailable }).Count -gt 0) {
        Write-Verbose -Message 'Some reliability counters are not available; run PowerShell as administrator to read them.'
    }

    # --- Overall status -------------------------------------------------------
    $overall = 'OK'
    foreach ($item in @($volumes + $physicalDisks)) {
        if ($rank[$item.Status] -gt $rank[$overall]) {
            $overall = $item.Status
        }
    }
    if ($storageDisks.Count -eq 0 -and $rank[$overall] -lt $rank['Unknown']) {
        # Free space alone does not prove that the drives are healthy
        $overall = 'Unknown'
    }

    [pscustomobject]@{
        PSTypeName      = 'HelpdeskToolkit.DiskHealth'
        ComputerName    = $env:COMPUTERNAME
        Status          = $overall
        Healthy         = ($overall -eq 'OK')
        Issues          = [string[]]$issues.ToArray()
        Volumes         = $volumes
        PhysicalDisks   = $physicalDisks
        WarningPercent  = $WarningPercent
        CriticalPercent = $CriticalPercent
        CollectedAt     = Get-Date
    }
}
