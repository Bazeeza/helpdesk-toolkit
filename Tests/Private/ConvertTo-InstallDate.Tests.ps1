#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-InstallDate' {
    It 'reads "<Value>" as <Expected>' -ForEach @(
        @{ Value = '20260115'; Expected = '2026-01-15' }
        @{ Value = ' 20260115 '; Expected = '2026-01-15' }
        @{ Value = '2026-01-15'; Expected = '2026-01-15' }
        @{ Value = '2026/01/15'; Expected = '2026-01-15' }
        @{ Value = '1/15/2026'; Expected = '2026-01-15' }
        @{ Value = '01/15/2026'; Expected = '2026-01-15' }
    ) {
        $parameters = @{ Value = $Value; Expected = $Expected }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            ConvertTo-InstallDate -Value $Value | Should -Be ([datetime]$Expected)
        }
    }

    It 'returns nothing for "<Value>"' -ForEach @(
        @{ Value = '' }
        @{ Value = '   ' }
        @{ Value = 'unknown' }
        @{ Value = '20261340' }
        @{ Value = '16010101' }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Value = $Value } {
            ConvertTo-InstallDate -Value $Value | Should -BeNullOrEmpty
        }
    }

    It 'returns nothing for a missing value' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-InstallDate -Value $null | Should -BeNullOrEmpty
        }
    }

    It 'gives the same date whatever the culture of the session' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-CA')
                ConvertTo-InstallDate -Value '1/15/2026' | Should -Be ([datetime]'2026-01-15')
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
            }
        }
    }

    It 'accepts values from the pipeline' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $dates = @('20260115', 'bad', '20250301' | ConvertTo-InstallDate)
            $dates | Should -HaveCount 2
            $dates[1] | Should -Be ([datetime]'2025-03-01')
        }
    }
}
