#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The disk is a client-only CIM instance created in memory: no storage
    class of the computer running the tests is queried.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-StorageReliability' {
    BeforeEach {
        $disk = [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_PhysicalDisk', 'root/Microsoft/Windows/Storage')
    }

    It 'returns the first counter instance associated with the disk' {
        Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -MockWith {
            [pscustomobject]@{ Temperature = 35 }
            [pscustomobject]@{ Temperature = 99 }
        }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Disk = $disk } {
            $counter = @(Get-StorageReliability -PhysicalDisk $Disk)
            $counter | Should -HaveCount 1
            $counter[0].Temperature | Should -Be 35
        }
        Should -Invoke -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
            $ResultClassName -eq 'MSFT_StorageReliabilityCounter'
        }
    }

    It 'returns nothing, without error, when Windows refuses the query' {
        Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -MockWith { throw 'Access denied' }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Disk = $disk } {
            { Get-StorageReliability -PhysicalDisk $Disk -ErrorAction Stop } | Should -Not -Throw
            Get-StorageReliability -PhysicalDisk $Disk | Should -BeNullOrEmpty
        }
    }

    It 'returns nothing when the association is empty (session not elevated)' {
        Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -MockWith { }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Disk = $disk } {
            Get-StorageReliability -PhysicalDisk $Disk | Should -BeNullOrEmpty
        }
    }

    It 'does not query CIM for an object that is not a CIM instance' {
        Mock -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -MockWith { [pscustomobject]@{ Temperature = 35 } }
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            Get-StorageReliability -PhysicalDisk ([pscustomobject]@{ DeviceId = '0' }) | Should -BeNullOrEmpty
        }
        Should -Invoke -CommandName 'Get-CimAssociatedInstance' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
    }
}
