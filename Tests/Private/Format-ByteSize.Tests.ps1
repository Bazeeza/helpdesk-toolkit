#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Format-ByteSize' {
    It 'formats <Bytes> bytes as "<Expected>"' -ForEach @(
        @{ Bytes = 0;              Expected = '0 B' }
        @{ Bytes = 512;            Expected = '512 B' }
        @{ Bytes = 1023;           Expected = '1023 B' }
        @{ Bytes = 1024;           Expected = '1 KB' }
        @{ Bytes = 1536;           Expected = '1.5 KB' }
        @{ Bytes = 1048576;        Expected = '1 MB' }
        @{ Bytes = 8589934592;     Expected = '8 GB' }
        @{ Bytes = 500107862016;   Expected = '465.76 GB' }
        @{ Bytes = 1099511627776;  Expected = '1 TB' }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Bytes = $Bytes; Expected = $Expected } {
            Format-ByteSize -Bytes $Bytes | Should -Be $Expected
        }
    }

    It 'rounds half away from zero' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            Format-ByteSize -Bytes 2560 -Decimals 0 | Should -Be '3 KB'
        }
    }

    It 'never shows decimals for a size in bytes' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            Format-ByteSize -Bytes 900 -Decimals 3 | Should -Be '900 B'
        }
    }

    It 'uses a dot as decimal separator on a French workstation' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $thread = [System.Threading.Thread]::CurrentThread
            $previous = $thread.CurrentCulture
            try {
                $thread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-CA')
                Format-ByteSize -Bytes 1536 | Should -Be '1.5 KB'
            }
            finally {
                $thread.CurrentCulture = $previous
            }
        }
    }

    It 'accepts values from the pipeline' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $result = @(1024, 2048 | Format-ByteSize)
            $result | Should -HaveCount 2
            $result[1] | Should -Be '2 KB'
        }
    }

    It 'rejects a negative size' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            { Format-ByteSize -Bytes -1 } | Should -Throw
        }
    }

    It 'rejects more than 4 decimals' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            { Format-ByteSize -Bytes 1024 -Decimals 5 } | Should -Throw
        }
    }
}
