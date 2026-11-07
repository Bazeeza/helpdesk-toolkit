#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-StorageCode' {
    It 'translates <Property> <Code> into "<Expected>"' -ForEach @(
        @{ Property = 'HealthStatus'; Code = 0; Expected = 'Healthy' }
        @{ Property = 'HealthStatus'; Code = 1; Expected = 'Warning' }
        @{ Property = 'HealthStatus'; Code = 2; Expected = 'Unhealthy' }
        @{ Property = 'HealthStatus'; Code = 5; Expected = 'Unknown' }
        @{ Property = 'MediaType'; Code = 3; Expected = 'HDD' }
        @{ Property = 'MediaType'; Code = 4; Expected = 'SSD' }
        @{ Property = 'MediaType'; Code = 0; Expected = 'Unspecified' }
        @{ Property = 'BusType'; Code = 7; Expected = 'USB' }
        @{ Property = 'BusType'; Code = 11; Expected = 'SATA' }
        @{ Property = 'BusType'; Code = 17; Expected = 'NVMe' }
        @{ Property = 'OperationalStatus'; Code = 2; Expected = 'OK' }
        @{ Property = 'OperationalStatus'; Code = 5; Expected = 'Predictive Failure' }
    ) {
        $parameters = @{ Property = $Property; Code = $Code; Expected = $Expected }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            ConvertFrom-StorageCode -Property $Property -Code $Code | Should -BeExactly $Expected
        }
    }

    It 'accepts the unsigned types returned by CIM' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertFrom-StorageCode -Property 'MediaType' -Code ([uint16]4) | Should -BeExactly 'SSD'
        }
    }

    It 'never guesses an undocumented code' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertFrom-StorageCode -Property 'BusType' -Code 99 | Should -BeExactly 'Unknown (99)'
        }
    }

    It 'returns Unknown for "<Code>"' -ForEach @(
        @{ Code = $null }
        @{ Code = '' }
        @{ Code = 'abc' }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Code = $Code } {
            ConvertFrom-StorageCode -Property 'HealthStatus' -Code $Code | Should -BeExactly 'Unknown'
        }
    }
}
