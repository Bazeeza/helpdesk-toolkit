#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Get-CimInstance is mocked: the tests never read the computer they run
    on, so they give the same result on a laptop, in the CI and without
    administrator rights. All values are fictitious.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    # One fictitious computer: 2 processors, 16 GB of memory, 2 disks,
    # last boot 3 days 2 hours 30 minutes before the time of the query
    function New-FakeComputer {
        @{
            OS         = [pscustomobject]@{
                Caption                = 'Microsoft Windows 11 Pro '
                Version                = '10.0.26100'
                BuildNumber            = '26100'
                OSArchitecture         = '64-bit'
                InstallDate            = [datetime]'2025-01-15T09:00:00'
                TotalVisibleMemorySize = 16777216
                FreePhysicalMemory     = 4194304
                LastBootUpTime         = [datetime]'2026-11-01T08:00:00'
                LocalDateTime          = [datetime]'2026-11-04T10:30:00'
            }
            System     = [pscustomobject]@{
                Name                = 'PC-EXAMPLE01'
                Manufacturer        = 'Contoso'
                Model               = 'Laptop 14'
                TotalPhysicalMemory = 17179869184
            }
            Bios       = [pscustomobject]@{
                SerialNumber      = '  SN-EXAMPLE-0001 '
                SMBIOSBIOSVersion = '1.2.3'
            }
            Processors = @(
                [pscustomobject]@{ Name = 'Example CPU   8-Core  Processor   '; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
                [pscustomobject]@{ Name = 'Example CPU   8-Core  Processor   '; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
            )
            # Returned out of order on purpose: the report sorts them
            Disks      = @(
                [pscustomobject]@{ DeviceID = 'D:'; VolumeName = 'Data'; FileSystem = 'NTFS'; Size = 1099511627776; FreeSpace = 274877906944 }
                [pscustomobject]@{ DeviceID = 'C:'; VolumeName = ''; FileSystem = 'NTFS'; Size = 500107862016; FreeSpace = 107374182400 }
            )
        }
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-SystemReport' {
    BeforeEach {
        $script:fake = New-FakeComputer

        Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -MockWith {
            if ($ComputerName -contains 'PC-OFFLINE') {
                throw 'The WinRM client cannot process the request.'
            }
            switch ($ClassName) {
                'Win32_OperatingSystem' { $script:fake.OS }
                'Win32_ComputerSystem' { $script:fake.System }
                'Win32_BIOS' { $script:fake.Bios }
                'Win32_Processor' { $script:fake.Processors }
                'Win32_LogicalDisk' { $script:fake.Disks }
            }
        }
    }

    Context 'Report of one computer' {
        BeforeEach {
            $report = Get-SystemReport
        }

        It 'returns one HelpdeskToolkit.SystemReport object' {
            @($report) | Should -HaveCount 1
            $report.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.SystemReport'
        }

        It 'reports the name, manufacturer and model of the computer' {
            $report.ComputerName | Should -Be 'PC-EXAMPLE01'
            $report.Manufacturer | Should -Be 'Contoso'
            $report.Model | Should -Be 'Laptop 14'
        }

        It 'trims the operating system name and keeps version, build and architecture' {
            $report.OperatingSystem | Should -Be 'Microsoft Windows 11 Pro'
            $report.Version | Should -Be '10.0.26100'
            $report.Build | Should -Be '26100'
            $report.Architecture | Should -Be '64-bit'
        }

        It 'trims the serial number and keeps the firmware version' {
            $report.SerialNumber | Should -Be 'SN-EXAMPLE-0001'
            $report.BiosVersion | Should -Be '1.2.3'
        }

        It 'adds the cores and logical processors of every processor' {
            $report.Processor | Should -Be 'Example CPU 8-Core Processor'
            $report.ProcessorCount | Should -Be 2
            $report.Cores | Should -Be 16
            $report.LogicalProcessors | Should -Be 32
        }

        It 'reports the memory in bytes, as text and as a used percentage' {
            $report.MemoryBytes | Should -Be 17179869184
            $report.Memory | Should -Be '16 GB'
            $report.MemoryUsedPercent | Should -Be 75
        }

        It 'lists the fixed disks sorted by drive letter' {
            @($report.Disks) | Should -HaveCount 2
            ($report.Disks | ForEach-Object { $_.Drive }) -join ',' | Should -Be 'C:,D:'
        }

        It 'gives the size, free space and free percentage of each disk' {
            $report.Disks[0].Size | Should -Be '465.76 GB'
            $report.Disks[0].Free | Should -Be '100 GB'
            $report.Disks[0].FreePercent | Should -Be 21.5
            $report.Disks[1].SizeBytes | Should -Be 1099511627776
            $report.Disks[1].FreeBytes | Should -Be 274877906944
        }

        It 'shows each disk as one readable line' {
            $report.Disks[1].ToString() | Should -Be 'D: 256 GB free of 1 TB (25 %)'
        }

        It 'computes the uptime from the clock of the queried computer' {
            $report.LastBootTime | Should -Be ([datetime]'2026-11-01T08:00:00')
            $report.Uptime | Should -Be (New-TimeSpan -Days 3 -Hours 2 -Minutes 30)
            $report.UptimeText | Should -Be '3d 2h 30m'
            $report.CollectedAt | Should -Be ([datetime]'2026-11-04T10:30:00')
        }

        It 'shows a short default view in the console but keeps every property' {
            $default = $report.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $default | Should -Contain 'SerialNumber'
            $default | Should -Contain 'UptimeText'
            $default | Should -Not -Contain 'MemoryBytes'
            $report.PSObject.Properties.Name | Should -Contain 'MemoryBytes'
        }

        It 'asks Win32_LogicalDisk for local fixed disks only' {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_LogicalDisk' -and $Filter -eq 'DriveType = 3'
            }
        }
    }

    Context 'Missing or unusual values' {
        It 'returns no serial number when the firmware has none' {
            $script:fake.Bios.SerialNumber = '   '
            (Get-SystemReport).SerialNumber | Should -BeNullOrEmpty
        }

        It 'returns an empty disk list when there is no fixed disk' {
            $script:fake.Disks = @()
            @((Get-SystemReport).Disks) | Should -HaveCount 0
        }

        It 'never returns a negative uptime' {
            $script:fake.OS.LastBootUpTime = [datetime]'2026-11-04T10:31:00'
            (Get-SystemReport).Uptime | Should -Be ([timespan]::Zero)
        }
    }

    Context 'Local and remote computers' {
        It 'queries the local computer without -ComputerName (no WinRM) for "<Name>"' -ForEach @(
            @{ Name = '.' }
            @{ Name = 'localhost' }
        ) {
            $null = Get-SystemReport -ComputerName $Name
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -Times 5 -Exactly -ParameterFilter {
                -not $ComputerName
            }
        }

        It 'queries a remote computer with -ComputerName' {
            $null = Get-SystemReport -ComputerName 'PC-EXAMPLE02'
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -Times 5 -Exactly -ParameterFilter {
                $ComputerName -contains 'PC-EXAMPLE02'
            }
        }

        It 'accepts computer names from the pipeline, by value and by property name' {
            @('PC-EXAMPLE02', 'PC-EXAMPLE03' | Get-SystemReport) | Should -HaveCount 2
            @([pscustomobject]@{ Name = 'PC-EXAMPLE04' } | Get-SystemReport) | Should -HaveCount 1
        }
    }

    Context 'Computer that cannot be reached' {
        It 'writes one error naming the computer and still reports the others' {
            $errors = $null
            $reports = @('PC-OFFLINE', 'PC-EXAMPLE02' | Get-SystemReport -ErrorAction SilentlyContinue -ErrorVariable errors)

            $reports | Should -HaveCount 1
            # -ErrorVariable also collects the error caught inside the function,
            # so only the error written by Get-SystemReport is checked
            $reported = @($errors | Where-Object { $_.TargetObject -eq 'PC-OFFLINE' })
            $reported | Should -HaveCount 1
            $reported[0].CategoryInfo.Category | Should -Be 'ConnectionError'
            $reported[0].Exception.Message | Should -BeLike 'PC-OFFLINE: *'
        }

        It 'stops with -ErrorAction Stop' {
            { Get-SystemReport -ComputerName 'PC-OFFLINE' -ErrorAction Stop } | Should -Throw '*PC-OFFLINE*'
        }
    }
}
