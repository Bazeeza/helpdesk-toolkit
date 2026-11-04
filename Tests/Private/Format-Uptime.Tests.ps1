#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Format-Uptime' {
    It 'formats <Text> as "<Expected>"' -ForEach @(
        @{ Text = '0 seconds';             Days = 0;   Hours = 0;  Minutes = 0;  Seconds = 0;  Expected = '0m' }
        @{ Text = '59 seconds';            Days = 0;   Hours = 0;  Minutes = 0;  Seconds = 59; Expected = '0m' }
        @{ Text = '45 minutes';            Days = 0;   Hours = 0;  Minutes = 45; Seconds = 10; Expected = '45m' }
        @{ Text = '3 hours';               Days = 0;   Hours = 3;  Minutes = 0;  Seconds = 0;  Expected = '3h 0m' }
        @{ Text = '1 day';                 Days = 1;   Hours = 0;  Minutes = 0;  Seconds = 0;  Expected = '1d 0h 0m' }
        @{ Text = '12 days 4 hours 7 min'; Days = 12;  Hours = 4;  Minutes = 7;  Seconds = 30; Expected = '12d 4h 7m' }
        @{ Text = '400 days';              Days = 400; Hours = 23; Minutes = 59; Seconds = 0;  Expected = '400d 23h 59m' }
    ) {
        $parameters = @{ Days = $Days; Hours = $Hours; Minutes = $Minutes; Seconds = $Seconds; Expected = $Expected }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $duration = New-TimeSpan -Days $Days -Hours $Hours -Minutes $Minutes -Seconds $Seconds
            Format-Uptime -Duration $duration | Should -Be $Expected
        }
    }

    It 'accepts values from the pipeline' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $result = @((New-TimeSpan -Minutes 5), (New-TimeSpan -Hours 2) | Format-Uptime)
            $result | Should -HaveCount 2
            $result[1] | Should -Be '2h 0m'
        }
    }

    It 'rejects a negative duration' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            { Format-Uptime -Duration (New-TimeSpan -Minutes -1) } | Should -Throw
        }
    }
}
