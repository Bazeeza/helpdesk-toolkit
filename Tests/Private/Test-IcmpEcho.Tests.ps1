#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Only the loopback address and a reserved name are used: the tests do not
    depend on the network of the computer or the CI runner.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Test-IcmpEcho' {
    It 'gets replies from the loopback address' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $result = Test-IcmpEcho -ComputerName '127.0.0.1' -Count 2 -TimeoutMilliseconds 2000
            $result.Succeeded | Should -BeTrue
            $result.Sent | Should -Be 2
            $result.Received | Should -Be 2
            $result.RoundtripMilliseconds | Should -BeGreaterOrEqual 0
            $result.Error | Should -BeNullOrEmpty
        }
    }

    It 'fails without throwing for a name that cannot exist' {
        # .invalid is reserved by RFC 2606 and never resolves
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $result = Test-IcmpEcho -ComputerName 'host.invalid' -Count 1 -TimeoutMilliseconds 500
            $result.Succeeded | Should -BeFalse
            $result.Received | Should -Be 0
            $result.RoundtripMilliseconds | Should -BeNullOrEmpty
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    It 'rejects a count of <Count>' -ForEach @(
        @{ Count = 0 }
        @{ Count = 11 }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Count = $Count } {
            { Test-IcmpEcho -ComputerName '127.0.0.1' -Count $Count } | Should -Throw
        }
    }
}
