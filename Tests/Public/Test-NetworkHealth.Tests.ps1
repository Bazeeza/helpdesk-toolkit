#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The network stack is mocked: the tests never send a packet and never
    read the adapters of the computer they run on. Addresses come from the
    ranges reserved for documentation (192.0.2.0/24, RFC 5737) and the MAC
    address from the documentation block 00-00-5E-00-53-xx (RFC 7042).
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    # A healthy workstation: Ethernet on the best default route, Wi-Fi connected
    # as a second route, DHCP address, two DNS servers, everything answers
    function New-FakeNetwork {
        @{
            Adapters   = @(
                [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceDescription = 'Example Wireless Adapter'; ifIndex = 12; Status = 'Up'; LinkSpeed = '866.7 Mbps'; MacAddress = '00-00-5E-00-53-02'; HardwareInterface = $true }
                [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Example Gigabit Network Connection'; ifIndex = 7; Status = 'Up'; LinkSpeed = '1 Gbps'; MacAddress = '00-00-5E-00-53-01'; HardwareInterface = $true }
            )
            # Returned in the wrong order on purpose: the command sorts by metric
            Routes     = @(
                [pscustomobject]@{ ifIndex = 12; NextHop = '192.0.2.129'; RouteMetric = 0; InterfaceMetric = 50 }
                [pscustomobject]@{ ifIndex = 7; NextHop = '192.0.2.1'; RouteMetric = 0; InterfaceMetric = 25 }
            )
            Addresses  = @{
                7  = @([pscustomobject]@{ IPAddress = '192.0.2.25'; PrefixLength = 24; PrefixOrigin = 'Dhcp' })
                12 = @([pscustomobject]@{ IPAddress = '192.0.2.140'; PrefixLength = 25; PrefixOrigin = 'Dhcp' })
            }
            DnsServers = @('192.0.2.53', '192.0.2.54')
            # Hosts that answer ping
            Ping       = @('192.0.2.1', '192.0.2.129', '1.1.1.1')
            DnsWorks   = $true
            TcpWorks   = $true
        }
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Test-NetworkHealth' {
    BeforeEach {
        $script:net = New-FakeNetwork

        Mock -CommandName 'Get-NetRoute' -ModuleName 'HelpdeskToolkit' -MockWith { $script:net.Routes }

        Mock -CommandName 'Get-NetAdapter' -ModuleName 'HelpdeskToolkit' -MockWith {
            $script:net.Adapters | Where-Object {
                (-not $Name -or $_.Name -in $Name) -and (-not $InterfaceIndex -or $_.ifIndex -in $InterfaceIndex)
            }
        }

        Mock -CommandName 'Get-NetIPAddress' -ModuleName 'HelpdeskToolkit' -MockWith {
            $script:net.Addresses[[int]$InterfaceIndex[0]]
        }

        Mock -CommandName 'Get-DnsClientServerAddress' -ModuleName 'HelpdeskToolkit' -MockWith {
            [pscustomobject]@{ InterfaceIndex = $InterfaceIndex[0]; ServerAddresses = $script:net.DnsServers }
        }

        Mock -CommandName 'Resolve-DnsName' -ModuleName 'HelpdeskToolkit' -MockWith {
            if (-not $script:net.DnsWorks) {
                throw "${Name} : DNS name does not exist"
            }
            # A CNAME record has no IPAddress: the command must skip it
            [pscustomobject]@{ Name = $Name; Type = 'CNAME'; NameHost = 'edge.example.net' }
            [pscustomobject]@{ Name = 'edge.example.net'; Type = 'A'; IPAddress = '192.0.2.80' }
        }

        Mock -CommandName 'Test-IcmpEcho' -ModuleName 'HelpdeskToolkit' -MockWith {
            if ($ComputerName -in $script:net.Ping) {
                [pscustomobject]@{ Succeeded = $true; Sent = 2; Received = 2; RoundtripMilliseconds = 3; Error = $null }
            }
            else {
                [pscustomobject]@{ Succeeded = $false; Sent = 2; Received = 0; RoundtripMilliseconds = $null; Error = 'TimedOut' }
            }
        }

        Mock -CommandName 'Test-TcpPort' -ModuleName 'HelpdeskToolkit' -MockWith {
            if ($script:net.TcpWorks) {
                [pscustomobject]@{ Succeeded = $true; ElapsedMilliseconds = 12; Error = $null }
            }
            else {
                [pscustomobject]@{ Succeeded = $false; ElapsedMilliseconds = 1000; Error = 'no answer within 1000 ms' }
            }
        }
    }

    Context 'Healthy network' {
        BeforeEach {
            $result = Test-NetworkHealth
        }

        It 'returns one HelpdeskToolkit.NetworkHealth object' {
            @($result) | Should -HaveCount 1
            $result.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.NetworkHealth'
        }

        It 'passes the six steps in the order of the runbook' {
            ($result.Checks | ForEach-Object { $_.Name }) -join ',' | Should -Be 'Link,IP address,Gateway,Internet,DNS,Port'
            ($result.Checks | ForEach-Object { $_.Step }) -join ',' | Should -Be '1,2,3,4,5,6'
            $result.Checks | ForEach-Object { $_.Status | Should -Be 'Pass' }
        }

        It 'is healthy and points to the application' {
            $result.Healthy | Should -BeTrue
            $result.FailedStep | Should -BeNullOrEmpty
            $result.Diagnosis | Should -BeLike '*application*'
        }

        It 'tests the adapter of the default route with the lowest metric' {
            $result.InterfaceAlias | Should -Be 'Ethernet'
            $result.InterfaceDescription | Should -Be 'Example Gigabit Network Connection'
            $result.LinkSpeed | Should -Be '1 Gbps'
            $result.MacAddress | Should -Be '00-00-5E-00-53-01'
        }

        It 'reports the IPv4 configuration of that adapter' {
            $result.IPv4Address | Should -Be '192.0.2.25'
            $result.PrefixLength | Should -Be 24
            $result.AddressSource | Should -Be 'Dhcp'
            $result.DefaultGateway | Should -Be '192.0.2.1'
            ($result.DnsServers -join ',') | Should -Be '192.0.2.53,192.0.2.54'
        }

        It 'keeps only the address records of the DNS answer' {
            $result.Checks[4].Detail | Should -Be 'www.microsoft.com resolved to 192.0.2.80.'
        }

        It 'shows each check as one readable line' {
            $result.Checks[2].ToString() | Should -Be '3 Gateway: Pass - 192.0.2.1 answered in 3 ms.'
        }

        It 'shows a short default view in the console but keeps every property' {
            $default = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $default | Should -Contain 'Healthy'
            $default | Should -Contain 'Diagnosis'
            $default | Should -Not -Contain 'MacAddress'
            $result.PSObject.Properties.Name | Should -Contain 'MacAddress'
        }
    }

    Context 'Parameters' {
        It 'tests the adapter named by -InterfaceAlias' {
            $result = Test-NetworkHealth -InterfaceAlias 'Wi-Fi'
            $result.InterfaceAlias | Should -Be 'Wi-Fi'
            $result.IPv4Address | Should -Be '192.0.2.140'
            $result.DefaultGateway | Should -Be '192.0.2.129'
        }

        It 'writes an ObjectNotFound error for an unknown adapter and returns nothing' {
            $errors = $null
            $result = Test-NetworkHealth -InterfaceAlias 'Missing' -ErrorAction SilentlyContinue -ErrorVariable errors
            $result | Should -BeNullOrEmpty
            $reported = @($errors | Where-Object { $_.TargetObject -eq 'Missing' })
            $reported | Should -HaveCount 1
            $reported[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        }

        It 'uses the public address, the name, the target and the port given' {
            $parameters = @{
                PublicAddress       = '192.0.2.200'
                DnsName             = 'intranet.corp.example.com'
                TargetHost          = 'print01.corp.example.com'
                Port                = 9100
                TimeoutMilliseconds = 300
            }
            $null = Test-NetworkHealth @parameters
            Should -Invoke -CommandName 'Test-IcmpEcho' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq '192.0.2.200' -and $TimeoutMilliseconds -eq 300
            }
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'intranet.corp.example.com' -and $DnsOnly
            }
            Should -Invoke -CommandName 'Test-TcpPort' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'print01.corp.example.com' -and $Port -eq 9100 -and $TimeoutMilliseconds -eq 300
            }
        }

        It 'tests the port of the resolved name when no target is given' {
            $null = Test-NetworkHealth -DnsName 'www.example.com'
            Should -Invoke -CommandName 'Test-TcpPort' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'www.example.com' -and $Port -eq 443
            }
        }

        It 'rejects <Text>' -ForEach @(
            @{ Text = 'a public address that is not an IP address'; Parameters = @{ PublicAddress = 'not-an-address' } }
            @{ Text = 'port 0'; Parameters = @{ Port = 0 } }
            @{ Text = 'a timeout under 100 ms'; Parameters = @{ TimeoutMilliseconds = 50 } }
        ) {
            { Test-NetworkHealth @Parameters } | Should -Throw
        }
    }

    Context 'Physical layer' {
        It 'fails at the link and skips the other steps when the cable is unplugged' {
            $script:net.Adapters[1].Status = 'Disconnected'
            $result = Test-NetworkHealth

            $result.FailedStep | Should -Be 'Link'
            $result.Healthy | Should -BeFalse
            $result.Checks[0].Detail | Should -Be 'Ethernet is Disconnected.'
            $result.Diagnosis | Should -BeLike 'Physical layer*'
            ($result.Checks | Select-Object -Skip 1 | ForEach-Object { $_.Status }) -join ',' | Should -Be 'Skipped,Skipped,Skipped,Skipped,Skipped'
            Should -Invoke -CommandName 'Test-IcmpEcho' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
        }

        It 'tells how to enable a disabled adapter' {
            $script:net.Adapters[1].Status = 'Disabled'
            (Test-NetworkHealth).Diagnosis | Should -BeLike "*Enable-NetAdapter -Name 'Ethernet'*"
        }

        It 'fails at the link when Windows sees no adapter' {
            $script:net.Adapters = @()
            $script:net.Routes = @()
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'Link'
            $result.InterfaceAlias | Should -BeNullOrEmpty
            $result.Checks[0].Detail | Should -Be 'No network adapter found.'
        }

        It 'falls back to the first connected adapter when there is no default route' {
            # Ethernet has the lowest index but no link: Wi-Fi is chosen
            $script:net.Routes = @()
            $script:net.Adapters[1].Status = 'Disconnected'
            $result = Test-NetworkHealth
            $result.InterfaceAlias | Should -Be 'Wi-Fi'
            $result.FailedStep | Should -Be 'Gateway'
            $result.Checks[2].Detail | Should -Be 'No default gateway.'
        }
    }

    Context 'IP address' {
        It 'recognizes an APIPA address as a DHCP problem and skips the next steps' {
            $script:net.Addresses[7] = @([pscustomobject]@{ IPAddress = '169.254.10.20'; PrefixLength = 16; PrefixOrigin = 'WellKnown' })
            $result = Test-NetworkHealth

            $result.FailedStep | Should -Be 'IP address'
            $result.IPv4Address | Should -Be '169.254.10.20'
            $result.Checks[1].Detail | Should -BeLike 'APIPA address 169.254.10.20*'
            $result.Diagnosis | Should -BeLike 'DHCP problem*'
            ($result.Checks | Select-Object -Skip 2 | ForEach-Object { $_.Status }) -join ',' | Should -Be 'Skipped,Skipped,Skipped,Skipped'
        }

        It 'prefers a valid address when an APIPA address is also present' {
            $script:net.Addresses[7] = @(
                [pscustomobject]@{ IPAddress = '169.254.10.20'; PrefixLength = 16; PrefixOrigin = 'WellKnown' }
                [pscustomobject]@{ IPAddress = '192.0.2.30'; PrefixLength = 24; PrefixOrigin = 'Manual' }
            )
            $result = Test-NetworkHealth
            $result.IPv4Address | Should -Be '192.0.2.30'
            $result.AddressSource | Should -Be 'Manual'
            $result.Checks[1].Status | Should -Be 'Pass'
        }

        It 'fails when the adapter has no IPv4 address' {
            $script:net.Addresses[7] = @()
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'IP address'
            $result.Checks[1].Detail | Should -Be 'No IPv4 address on the adapter.'
        }
    }

    Context 'Gateway and Internet' {
        It 'reports a Warning, not a Fail, when only the gateway ignores ping' {
            $script:net.Ping = @('1.1.1.1')
            $result = Test-NetworkHealth
            $result.Checks[2].Status | Should -Be 'Warning'
            $result.Checks[2].Detail | Should -BeLike '*probably blocks ping*'
            $result.Healthy | Should -BeTrue
        }

        It 'fails at the gateway when nothing answers beyond it' {
            $script:net.Ping = @()
            $script:net.TcpWorks = $false
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'Gateway'
            $result.Diagnosis | Should -BeLike 'Local network*'
        }

        It 'reports a Warning when ping to the Internet is filtered but the TCP test succeeds' {
            $script:net.Ping = @('192.0.2.1')
            $result = Test-NetworkHealth
            $result.Checks[3].Status | Should -Be 'Warning'
            $result.Checks[3].Detail | Should -BeLike '*ping is probably filtered*'
            $result.Healthy | Should -BeTrue
        }

        It 'fails at the Internet step and suggests tracert when the service does not answer either' {
            $script:net.Ping = @('192.0.2.1')
            $script:net.TcpWorks = $false
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'Internet'
            $result.Diagnosis | Should -BeLike '*tracert 1.1.1.1*'
        }
    }

    Context 'DNS and service port' {
        It 'fails at DNS and skips the port test of a name' {
            $script:net.DnsWorks = $false
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'DNS'
            $result.Diagnosis | Should -BeLike 'DNS problem*'
            $result.Checks[5].Status | Should -Be 'Skipped'
            Should -Invoke -CommandName 'Test-TcpPort' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
        }

        It 'still tests the port of an IP address when DNS fails' {
            $script:net.DnsWorks = $false
            $result = Test-NetworkHealth -TargetHost '192.0.2.80'
            $result.Checks[5].Status | Should -Be 'Pass'
            $result.FailedStep | Should -Be 'DNS'
        }

        It 'fails at DNS when the adapter has no DNS server' {
            $script:net.DnsServers = @()
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'DNS'
            $result.Checks[4].Detail | Should -Be 'No DNS server configured on the adapter.'
            Should -Invoke -CommandName 'Resolve-DnsName' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
        }

        It 'fails at the port when every lower layer works' {
            $script:net.TcpWorks = $false
            $result = Test-NetworkHealth
            $result.FailedStep | Should -Be 'Port'
            $result.Checks[5].Detail | Should -BeLike 'www.microsoft.com:443 did not answer*'
            $result.Diagnosis | Should -BeLike 'Service:*'
        }
    }
}
