function Get-SystemReport {
    <#
    .SYNOPSIS
        Collects the system facts asked at the start of a ticket: Windows
        version, hardware, serial number, memory, disks and uptime.

    .DESCRIPTION
        Get-SystemReport reads five CIM classes and returns one object per
        computer, ready to be pasted in a ticket, exported to CSV or used by
        the HTML report of the module:

          Win32_OperatingSystem   Windows edition, version, build, memory, last boot
          Win32_ComputerSystem    manufacturer, model, installed memory
          Win32_BIOS              serial number, firmware version
          Win32_Processor         processor name, cores, logical processors
          Win32_LogicalDisk       local fixed disks (DriveType 3): size and free space

        The command only reads. It does not need administrator rights on the
        local computer.

        The uptime is computed from two values of the same computer (its
        current time and its last boot time), so it stays correct when the
        clock of the technician's computer is different.

        For a remote computer the query uses WinRM (WS-Management), the
        default protocol of Get-CimInstance: the remote computer must accept
        PowerShell remoting and the current user must be allowed to query it.
        A computer that cannot be reached produces a non-terminating error and
        the other computers are still reported.

    .PARAMETER ComputerName
        Computers to query. The default is the local computer. Accepts
        pipeline input, by value or from a ComputerName or Name property.
        ".", "localhost" and the local computer name are queried locally,
        without WinRM.

    .EXAMPLE
        Get-SystemReport

        Report of the local computer, displayed as a list.

    .EXAMPLE
        Get-SystemReport | Select-Object -ExpandProperty Disks

        Size, free space and free percentage of each local fixed disk.

    .EXAMPLE
        'PC-EXAMPLE01', 'PC-EXAMPLE02' | Get-SystemReport -ErrorAction Continue |
            Select-Object ComputerName, Model, SerialNumber, OperatingSystem, Build, UptimeText |
            Export-Csv -Path .\inventory.csv -NoTypeInformation

        Short inventory of two computers saved as a CSV file. A computer that
        does not answer is reported as an error and skipped.

    .EXAMPLE
        Get-SystemReport | Where-Object { $_.Uptime.TotalDays -gt 7 }

        Returns the report only if the computer has not restarted for more
        than a week, a common cause of pending updates and slow sessions.

    .INPUTS
        System.String

        Computer names, by value or from a ComputerName or Name property.

    .OUTPUTS
        HelpdeskToolkit.SystemReport

        One object per computer. The console shows a short view; use
        Select-Object * to see every property.

    .NOTES
        Read-only. No administrator rights needed on the local computer.
        Remote computers need WinRM and the right to query CIM. Works in
        Windows PowerShell 5.1 and PowerShell 7.

    .LINK
        https://github.com/Bazeeza/helpdesk-toolkit/blob/main/docs/commands/Get-SystemReport.md

    .LINK
        Export-HelpdeskReport

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.SystemReport')]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('CN', 'Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            # Local names are queried without -ComputerName: no WinRM needed
            $cimParameters = @{ ErrorAction = 'Stop' }
            if ($computer -notin @('.', 'localhost', $env:COMPUTERNAME)) {
                $cimParameters.ComputerName = $computer
            }

            try {
                Write-Verbose -Message "${computer}: reading CIM classes"
                $os = Get-CimInstance @cimParameters -ClassName 'Win32_OperatingSystem'
                $system = Get-CimInstance @cimParameters -ClassName 'Win32_ComputerSystem'
                $bios = Get-CimInstance @cimParameters -ClassName 'Win32_BIOS'
                $processors = @(Get-CimInstance @cimParameters -ClassName 'Win32_Processor')
                $logicalDisks = @(Get-CimInstance @cimParameters -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3')
            }
            catch {
                # Non-terminating: the next computers of the list are still reported
                $errorParameters = @{
                    Message      = "${computer}: cannot read the system information. $($_.Exception.Message)"
                    Category     = 'ConnectionError'
                    TargetObject = $computer
                }
                Write-Error @errorParameters
                continue
            }

            # Local fixed disks, sorted by letter
            $disks = @(
                foreach ($logicalDisk in ($logicalDisks | Sort-Object -Property DeviceID)) {
                    $size = [double]$logicalDisk.Size
                    $free = [double]$logicalDisk.FreeSpace
                    $freePercent = $null
                    if ($size -gt 0) {
                        $freePercent = [math]::Round(($free / $size) * 100, 1)
                    }

                    $disk = [pscustomobject]@{
                        PSTypeName  = 'HelpdeskToolkit.SystemReport.Disk'
                        Drive       = $logicalDisk.DeviceID
                        Label       = $logicalDisk.VolumeName
                        FileSystem  = $logicalDisk.FileSystem
                        Size        = Format-ByteSize -Bytes $size
                        Free        = Format-ByteSize -Bytes $free
                        FreePercent = $freePercent
                        SizeBytes   = [long]$size
                        FreeBytes   = [long]$free
                    }
                    # Readable in the list view of the report: "C: 120.5 GB free of 476.33 GB (25.3 %)"
                    $disk | Add-Member -MemberType ScriptMethod -Name 'ToString' -Force -Value {
                        '{0} {1} free of {2} ({3} %)' -f $this.Drive, $this.Free, $this.Size, $this.FreePercent
                    }
                    $disk
                }
            )

            # Win32_OperatingSystem gives memory sizes in kilobytes
            $visibleMemoryBytes = [double]$os.TotalVisibleMemorySize * 1KB
            $freeMemoryBytes = [double]$os.FreePhysicalMemory * 1KB
            $memoryUsedPercent = $null
            if ($visibleMemoryBytes -gt 0) {
                $memoryUsedPercent = [math]::Round((($visibleMemoryBytes - $freeMemoryBytes) / $visibleMemoryBytes) * 100, 1)
            }

            # Both dates come from the queried computer, so the clock of the
            # computer running the command does not matter
            $uptime = $os.LocalDateTime - $os.LastBootUpTime
            if ($uptime -lt [timespan]::Zero) {
                $uptime = [timespan]::Zero
            }

            # Some virtual machines and home-built computers have no serial number
            $serialNumber = $null
            if ($bios.SerialNumber -and $bios.SerialNumber.Trim()) {
                $serialNumber = $bios.SerialNumber.Trim()
            }

            $cores = 0
            $logicalProcessors = 0
            foreach ($processor in $processors) {
                $cores += [int]$processor.NumberOfCores
                $logicalProcessors += [int]$processor.NumberOfLogicalProcessors
            }
            $processorName = $null
            if ($processors.Count -gt 0 -and $processors[0].Name) {
                # Processor names are often padded with spaces
                $processorName = ($processors[0].Name -replace '\s+', ' ').Trim()
            }

            [pscustomobject]@{
                PSTypeName        = 'HelpdeskToolkit.SystemReport'
                ComputerName      = $system.Name
                Manufacturer      = $system.Manufacturer
                Model             = $system.Model
                SerialNumber      = $serialNumber
                BiosVersion       = $bios.SMBIOSBIOSVersion
                OperatingSystem   = ([string]$os.Caption).Trim()
                Version           = $os.Version
                Build             = $os.BuildNumber
                Architecture      = $os.OSArchitecture
                InstallDate       = $os.InstallDate
                Processor         = $processorName
                ProcessorCount    = $processors.Count
                Cores             = $cores
                LogicalProcessors = $logicalProcessors
                Memory            = Format-ByteSize -Bytes ([double]$system.TotalPhysicalMemory)
                MemoryUsedPercent = $memoryUsedPercent
                MemoryBytes       = [long]$system.TotalPhysicalMemory
                Disks             = $disks
                LastBootTime      = $os.LastBootUpTime
                Uptime            = $uptime
                UptimeText        = Format-Uptime -Duration $uptime
                CollectedAt       = $os.LocalDateTime
            }
        }
    }
}
