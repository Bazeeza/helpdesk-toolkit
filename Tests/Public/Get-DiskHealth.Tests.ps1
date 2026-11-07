#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Get-CimInstance and the private helper Get-StorageReliability are
    mocked: the tests never read the disks of the computer they run on.
    Each test changes the fictitious volumes, disks or counters it needs.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    function New-FakeVolume {
        param([string]$Drive, [double]$SizeGB, [double]$FreeGB)
        [pscustomobject]@{
            DeviceID   = $Drive
            VolumeName = 'Example'
            FileSystem = 'NTFS'
            Size       = [uint64]($SizeGB * 1GB)
            FreeSpace  = [uint64]($FreeGB * 1GB)
        }
    }

    function New-FakeDisk {
        param([string]$DeviceId, [int]$HealthStatus = 0, [int[]]$OperationalStatus = @(2), [int]$MediaType = 4, [int]$BusType = 17)
        [pscustomobject]@{
            DeviceId          = $DeviceId
            FriendlyName      = "Example Drive $DeviceId "
            HealthStatus      = [uint16]$HealthStatus
            OperationalStatus = [uint16[]]$OperationalStatus
            MediaType         = [uint16]$MediaType
            BusType           = [uint16]$BusType
            Size              = [uint64](512GB)
        }
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-DiskHealth' {
    BeforeEach {
        $script:volumes = @(
            New-FakeVolume -Drive 'D:' -SizeGB 1000 -FreeGB 600
            New-FakeVolume -Drive 'C:' -SizeGB 500 -FreeGB 200
        )
        $script:disks = @(New-FakeDisk -DeviceId '0')
        $script:counters = @{}

        Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } -MockWith { $script:volumes }
        Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } -MockWith { $script:disks }
        Mock -CommandName 'Get-StorageReliability' -ModuleName 'HelpdeskToolkit' -MockWith { $script:counters[[string]$PhysicalDisk.DeviceId] }
    }

    Context 'Healthy computer' {
        BeforeEach {
            $result = Get-DiskHealth
        }

        It 'returns one OK result without issue' {
            $result.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.DiskHealth'
            $result.Status | Should -Be 'OK'
            $result.Healthy | Should -BeTrue
            $result.Issues | Should -HaveCount 0
            , $result.Issues | Should -BeOfType [string[]]
        }

        It 'reports the volumes sorted by letter with their free space' {
            ($result.Volumes.Drive) -join ',' | Should -Be 'C:,D:'
            $result.Volumes[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.DiskHealth.Volume'
            $result.Volumes[0].FreePercent | Should -Be 40
            $result.Volumes[0].Free | Should -Be '200 GB'
            $result.Volumes[0].FreeBytes | Should -Be ([long](200GB))
            $result.Volumes[0].Status | Should -Be 'OK'
            $result.Volumes[0].ToString() | Should -Be 'C: 200 GB free (40 %) OK'
        }

        It 'translates the codes of the physical disk' {
            $disk = $result.PhysicalDisks[0]
            $disk.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.DiskHealth.PhysicalDisk'
            $disk.Name | Should -Be 'Example Drive 0'
            $disk.MediaType | Should -Be 'SSD'
            $disk.BusType | Should -Be 'NVMe'
            $disk.HealthStatus | Should -Be 'Healthy'
            $disk.OperationalStatus | Should -Be 'OK'
            $disk.Size | Should -Be '512 GB'
            $disk.Status | Should -Be 'OK'
        }

        It 'marks the counters as not available when Windows gives none' {
            $result.PhysicalDisks[0].ReliabilityAvailable | Should -BeFalse
            $result.PhysicalDisks[0].Temperature | Should -BeNullOrEmpty
            $result.PhysicalDisks[0].Wear | Should -BeNullOrEmpty
        }

        It 'records the thresholds used' {
            $result.WarningPercent | Should -Be 15
            $result.CriticalPercent | Should -Be 5
        }

        It 'shows a short default view' {
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ',' |
                Should -Be 'ComputerName,Status,Issues,Volumes,PhysicalDisks'
        }
    }

    Context 'Free space thresholds' {
        It 'reports <Free> GB free of 100 GB as <Expected>' -ForEach @(
            @{ Free = 50; Expected = 'OK' }
            @{ Free = 15; Expected = 'OK' }
            @{ Free = 14.9; Expected = 'Warning' }
            @{ Free = 5; Expected = 'Warning' }
            @{ Free = 4.9; Expected = 'Critical' }
            @{ Free = 0; Expected = 'Critical' }
        ) {
            $script:volumes = @(New-FakeVolume -Drive 'C:' -SizeGB 100 -FreeGB $Free)
            $result = Get-DiskHealth
            $result.Volumes[0].Status | Should -Be $Expected
            $result.Status | Should -Be $Expected
        }

        It 'explains a full volume in one line' {
            $script:volumes = @(New-FakeVolume -Drive 'C:' -SizeGB 100 -FreeGB 3)
            (Get-DiskHealth).Issues | Should -Be 'C: only 3 GB free (3 %), critical below 5 %'
        }

        It 'uses the thresholds given as parameters' {
            $script:volumes = @(New-FakeVolume -Drive 'C:' -SizeGB 100 -FreeGB 18)
            (Get-DiskHealth -WarningPercent 20 -CriticalPercent 10).Volumes[0].Status | Should -Be 'Warning'
        }

        It 'rejects a critical threshold that is not lower than the warning threshold' {
            { Get-DiskHealth -WarningPercent 10 -CriticalPercent 10 } | Should -Throw '*must be lower*'
        }

        It 'reports a volume without size as Unknown' {
            $script:volumes = @(New-FakeVolume -Drive 'C:' -SizeGB 0 -FreeGB 0)
            $result = Get-DiskHealth
            $result.Volumes[0].Status | Should -Be 'Unknown'
            $result.Volumes[0].FreePercent | Should -BeNullOrEmpty
            $result.Status | Should -Be 'Unknown'
        }
    }

    Context 'Health reported by the drives' {
        It 'maps HealthStatus <Code> to the status <Expected>' -ForEach @(
            @{ Code = 0; Expected = 'OK' }
            @{ Code = 1; Expected = 'Warning' }
            @{ Code = 2; Expected = 'Critical' }
            @{ Code = 5; Expected = 'Unknown' }
        ) {
            $script:disks = @(New-FakeDisk -DeviceId '0' -HealthStatus $Code)
            $result = Get-DiskHealth
            $result.PhysicalDisks[0].Status | Should -Be $Expected
            $result.Status | Should -Be $Expected
        }

        It 'names the failing disk and its operational status in the issues' {
            $script:disks = @(New-FakeDisk -DeviceId '1' -HealthStatus 1 -OperationalStatus @(5))
            (Get-DiskHealth).Issues | Should -Be 'Disk 1 (Example Drive 1): health Warning, operational status Predictive Failure'
        }

        It 'sorts disks by number, 2 before 10' {
            $script:disks = @(New-FakeDisk -DeviceId '10'; New-FakeDisk -DeviceId '2')
            ((Get-DiskHealth).PhysicalDisks.DeviceId) -join ',' | Should -Be '2,10'
        }

        It 'keeps the worst status of all volumes and disks' {
            $script:volumes = @(New-FakeVolume -Drive 'C:' -SizeGB 100 -FreeGB 10)
            $script:disks = @(New-FakeDisk -DeviceId '0' -HealthStatus 2)
            $result = Get-DiskHealth
            $result.Status | Should -Be 'Critical'
            $result.Healthy | Should -BeFalse
            $result.Issues | Should -HaveCount 2
        }
    }

    Context 'Reliability counters' {
        BeforeEach {
            $script:counters['0'] = [pscustomobject]@{
                Temperature = 38; TemperatureMax = 70; Wear = 3; PowerOnHours = 1200
                ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 0
            }
        }

        It 'adds the counters when Windows gives them' {
            $disk = (Get-DiskHealth).PhysicalDisks[0]
            $disk.ReliabilityAvailable | Should -BeTrue
            $disk.Temperature | Should -Be 38
            $disk.Wear | Should -Be 3
            $disk.PowerOnHours | Should -Be 1200
            $disk.Status | Should -Be 'OK'
        }

        It 'raises a healthy disk to Warning for <Case>' -ForEach @(
            @{ Case = 'uncorrected read errors'; Name = 'ReadErrorsUncorrected'; Value = 4; Text = '4 uncorrected read errors' }
            @{ Case = 'uncorrected write errors'; Name = 'WriteErrorsUncorrected'; Value = 1; Text = '1 uncorrected write errors' }
            @{ Case = 'a wear of 100 %'; Name = 'Wear'; Value = 100; Text = 'wear 100 % (estimated limit reached)' }
            @{ Case = 'a temperature at its maximum'; Name = 'Temperature'; Value = 70; Text = 'temperature 70 C at or above its maximum of 70 C' }
        ) {
            $script:counters['0'].$Name = $Value
            $result = Get-DiskHealth
            $result.PhysicalDisks[0].Status | Should -Be 'Warning'
            $result.Status | Should -Be 'Warning'
            $result.Issues | Should -Be "Disk 0 (Example Drive 0): $Text"
        }

        It 'never lowers the status given by the drive' {
            $script:disks = @(New-FakeDisk -DeviceId '0' -HealthStatus 2)
            $script:counters['0'].ReadErrorsUncorrected = 4
            (Get-DiskHealth).PhysicalDisks[0].Status | Should -Be 'Critical'
        }
    }

    Context 'Missing data' {
        It 'still reports the volumes when the storage classes cannot be read' {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } -MockWith { throw 'Invalid namespace' }
            $result = Get-DiskHealth -WarningAction SilentlyContinue
            $result.Volumes | Should -HaveCount 2
            $result.PhysicalDisks | Should -HaveCount 0
            $result.Status | Should -Be 'Unknown'
            $result.Issues | Should -Be 'Physical disk health not available: Invalid namespace'
        }

        It 'reports Unknown when Windows lists no physical disk' {
            $script:disks = @()
            $result = Get-DiskHealth
            $result.Status | Should -Be 'Unknown'
            $result.Issues | Should -Be 'Physical disk health not available: Windows reported no physical disk'
        }

        It 'writes a non-terminating error and no result when the volumes cannot be read' {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } -MockWith { throw 'RPC server unavailable' }
            $result = Get-DiskHealth -ErrorAction SilentlyContinue -ErrorVariable diskErrors
            $result | Should -BeNullOrEmpty
            # The error variable also holds the caught CIM error: look for the message of the command
            @($diskErrors | Where-Object { $_.Exception.Message -like 'Cannot read the volumes*RPC server unavailable' }) |
                Should -HaveCount 1
        }
    }
}
