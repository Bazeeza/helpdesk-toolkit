#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The tests only use the loopback address (127.0.0.1): a listener opened
    by the test answers on a free port, and no packet leaves the computer.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Test-TcpPort' {
    Context 'Port with a listener' {
        BeforeAll {
            # Port 0: the system chooses a free port
            $listener = New-Object -TypeName 'System.Net.Sockets.TcpListener' -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            $listener.Start()
            $openPort = $listener.LocalEndpoint.Port
        }

        AfterAll {
            $listener.Stop()
        }

        It 'succeeds and reports no error' {
            InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Port = $openPort } {
                $result = Test-TcpPort -ComputerName '127.0.0.1' -Port $Port -TimeoutMilliseconds 2000
                $result.Succeeded | Should -BeTrue
                $result.Error | Should -BeNullOrEmpty
                $result.ElapsedMilliseconds | Should -BeGreaterOrEqual 0
            }
        }
    }

    Context 'Port without a listener' {
        BeforeAll {
            # Take a free port, then close it: nothing listens on it anymore
            $listener = New-Object -TypeName 'System.Net.Sockets.TcpListener' -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            $listener.Start()
            $closedPort = $listener.LocalEndpoint.Port
            $listener.Stop()
        }

        It 'fails and gives the reason' {
            InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Port = $closedPort } {
                $result = Test-TcpPort -ComputerName '127.0.0.1' -Port $Port -TimeoutMilliseconds 2000
                $result.Succeeded | Should -BeFalse
                $result.Error | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'rejects port <Port>' -ForEach @(
        @{ Port = 0 }
        @{ Port = 65536 }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Port = $Port } {
            { Test-TcpPort -ComputerName '127.0.0.1' -Port $Port } | Should -Throw
        }
    }
}
