#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    ConvertTo-ReportHtml only turns objects into text, so it is tested with
    fictitious results shaped like the ones of the public commands:
    documentation addresses (192.0.2.0/24, RFC 5737), the documentation MAC
    block (00-00-5E-00-53-xx, RFC 7042) and example names only.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    function New-FakeSystemReport {
        [pscustomobject]@{
            ComputerName      = 'PC-EXAMPLE01'
            Manufacturer      = 'Example Corp'
            Model             = 'Example 15'
            SerialNumber      = $null
            BiosVersion       = '1.2.3'
            OperatingSystem   = 'Microsoft Windows 11 Pro'
            Version           = '10.0.26100'
            Build             = '26100'
            Architecture      = '64-bit'
            InstallDate       = [datetime]::new(2025, 3, 14, 9, 30, 0)
            Processor         = 'Example CPU 3.0 GHz'
            Cores             = 4
            LogicalProcessors = 8
            Memory            = '16 GB'
            MemoryUsedPercent = 42.5
            Disks             = @([pscustomobject]@{ Drive = 'C:'; Label = 'OS'; FileSystem = 'NTFS'; Size = '476.94 GB'; Free = '120.5 GB'; FreePercent = 25.3 })
            LastBootTime      = [datetime]::new(2026, 11, 1, 8, 0, 0)
            UptimeText        = '7d 2h 15m'
        }
    }

    function New-FakeNetworkHealth {
        param([bool]$Healthy = $true, [string]$GatewayStatus = 'Pass')
        $checks = @(
            [pscustomobject]@{ Step = 1; Name = 'Link'; Status = 'Pass'; Detail = 'Ethernet is Up at 1 Gbps.' }
            [pscustomobject]@{ Step = 2; Name = 'IP address'; Status = 'Pass'; Detail = '192.0.2.10/24 (Dhcp).' }
            [pscustomobject]@{ Step = 3; Name = 'Gateway'; Status = $GatewayStatus; Detail = '192.0.2.1 answered in 1 ms.' }
        )
        $failedStep = $null
        $diagnosis = 'Every layer answered: the remaining problem is the application.'
        if (-not $Healthy) {
            $checks[1].Status = 'Fail'
            $checks[1].Detail = 'APIPA address 169.254.10.20: no DHCP server answered.'
            $failedStep = 'IP address'
            $diagnosis = 'DHCP problem: run ipconfig /release and ipconfig /renew.'
        }
        [pscustomobject]@{
            InterfaceAlias       = 'Ethernet'
            InterfaceDescription = 'Example Gigabit Adapter'
            LinkSpeed            = '1 Gbps'
            MacAddress           = '00-00-5E-00-53-01'
            IPv4Address          = '192.0.2.10'
            PrefixLength         = 24
            AddressSource        = 'Dhcp'
            DefaultGateway       = '192.0.2.1'
            DnsServers           = @('192.0.2.53', '192.0.2.54')
            Healthy              = $Healthy
            FailedStep           = $failedStep
            Diagnosis            = $diagnosis
            Checks               = $checks
        }
    }

    function New-FakeDiskHealth {
        param([string]$Status = 'OK', [string[]]$Issues = @(), [bool]$ReliabilityAvailable = $false)
        [pscustomobject]@{
            Status          = $Status
            Issues          = $Issues
            Volumes         = @([pscustomobject]@{ Drive = 'C:'; Label = 'OS'; FileSystem = 'NTFS'; Size = '476.94 GB'; Free = '41.2 GB'; FreePercent = 8.6; Status = $Status })
            PhysicalDisks   = @([pscustomobject]@{
                    DeviceId = '0'; Name = 'Example Drive 0'; MediaType = 'SSD'; BusType = 'NVMe'; Size = '476.94 GB'
                    HealthStatus = 'Healthy'; ReliabilityAvailable = $ReliabilityAvailable; Temperature = $null; Wear = $null; PowerOnHours = $null; Status = 'OK'
                })
            WarningPercent  = 15
            CriticalPercent = 5
        }
    }

    function New-FakeSoftware {
        param([string]$Name)
        [pscustomobject]@{ Name = $Name; Version = '1.0'; Publisher = 'Example Publisher'; InstallDate = [datetime]::new(2026, 1, 15); Scope = 'Machine'; Architecture = '64-bit' }
    }

    $all = @('System', 'Network', 'Disk', 'Software')
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-ReportHtml' {
    Context 'Complete report of a healthy computer' {
        BeforeAll {
            $parameters = @{
                ComputerName      = 'PC-EXAMPLE01'
                Section           = $all
                SystemReport      = New-FakeSystemReport
                NetworkHealth     = New-FakeNetworkHealth
                DiskHealth        = New-FakeDiskHealth
                InstalledSoftware = @((New-FakeSoftware -Name 'Example Editor'), (New-FakeSoftware -Name 'Example Viewer'))
                TicketNumber      = 'INC-0042'
                GeneratedAt       = [datetime]::new(2026, 11, 8, 14, 5, 9)
                ModuleVersion     = '0.6.0'
            }
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
                param($ComputerName, $Section, $SystemReport, $NetworkHealth, $DiskHealth, $InstalledSoftware, $TicketNumber, $GeneratedAt, $ModuleVersion)
                ConvertTo-ReportHtml @PSBoundParameters
            }
        }

        It 'is one complete HTML document' {
            $html | Should -BeLike '<!DOCTYPE html>*</html>'
            $html | Should -Match '<meta charset="utf-8">'
            ([regex]::Matches($html, '<style>')).Count | Should -Be 1
        }

        It 'allows the embedded style only, no script or external resource' {
            $html | Should -Match "<meta http-equiv=""Content-Security-Policy"" content=""default-src 'none'; style-src 'unsafe-inline'"">"
            $html | Should -Not -Match '<script'
            $html | Should -Not -Match '<link'
            $html | Should -Not -Match 'src='
        }

        It 'names the computer, the ticket and the time in the title and header' {
            $html | Should -Match '<title>Helpdesk report - PC-EXAMPLE01 - ticket INC-0042</title>'
            $html | Should -Match '<dt>Ticket</dt><dd>INC-0042</dd>'
            $html | Should -Match '<dt>Generated</dt><dd>2026-11-08 14:05:09 \(UTC[+-]\d\d:\d\d\)</dd>'
            $html | Should -Match 'Generated by HelpdeskToolkit 0.6.0'
        }

        It 'writes the four sections in a fixed order, each linked from the contents' {
            $positions = foreach ($id in 'system', 'network', 'disk', 'software') {
                $html | Should -Match ('<a href="#{0}">' -f $id)
                $html.IndexOf(('<section id="{0}"' -f $id))
            }
            $positions | Should -Not -Contain -1
            ($positions -join ',') | Should -Be (($positions | Sort-Object) -join ',')
        }

        It 'writes one summary card per section' {
            ([regex]::Matches($html, '<div class="card[ "]')).Count | Should -Be 4
            $html | Should -Match '<div class="card-value">2 programs</div>'
            $html | Should -Match '<div class="card-value">Every step answered</div>'
        }

        It 'shows the system facts and says when a value is not reported' {
            $html | Should -Match '<td>Model</td><td>Example 15</td>'
            $html | Should -Match '<td>Serial number</td><td>Not reported</td>'
            $html | Should -Match '<td>Processor</td><td>Example CPU 3.0 GHz \(4 cores, 8 logical processors\)</td>'
            $html | Should -Match '<td>Memory</td><td>16 GB \(42.5 % in use\)</td>'
            $html | Should -Match '<td>Windows installed</td><td>2025-03-14</td>'
        }

        It 'shows the network steps with their status and the diagnosis' {
            $html | Should -Match '<h2 id="network-title">Network <span class="badge badge-ok">Pass</span></h2>'
            $html | Should -Match '<td>3</td><td>Gateway</td><td><span class="badge badge-ok">Pass</span></td>'
            $html | Should -Match '<td>DNS servers</td><td>192.0.2.53, 192.0.2.54</td>'
            $html | Should -Match '<td>IPv4 address</td><td>192.0.2.10/24</td>'
        }

        It 'shows the volumes with a free space bar and the thresholds used' {
            $html | Should -Match 'style="width:8.6%"'
            $html | Should -Match 'Warning below 15 % of free space, Critical below 5 %'
            $html | Should -Match '<p class="callout callout-ok">No issue found.</p>'
        }

        It 'explains why the drive counters are missing' {
            $html | Should -Match 'Windows usually gives them only to PowerShell run as administrator'
        }

        It 'lists the programs with their install date' {
            $html | Should -Match '<td>Example Viewer</td><td>1.0</td><td>Example Publisher</td><td>2026-01-15</td>'
        }
    }

    Context 'Problems found' {
        It 'shows a failed network as Fail with the step where it stops' {
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Network = (New-FakeNetworkHealth -Healthy $false) } {
                param($Network)
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Network' -NetworkHealth $Network
            }
            $html | Should -Match '<div class="card card-crit">'
            $html | Should -Match 'Stops at: IP address'
            $html | Should -Match '<p class="callout callout-crit"><strong>Diagnosis:</strong> DHCP problem'
        }

        It 'shows a healthy network with a Warning step as Warning' {
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Network = (New-FakeNetworkHealth -GatewayStatus 'Warning') } {
                param($Network)
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Network' -NetworkHealth $Network
            }
            $html | Should -Match '<h2 id="network-title">Network <span class="badge badge-warn">Warning</span></h2>'
        }

        It 'lists every disk issue, encoded' {
            $disk = New-FakeDiskHealth -Status 'Warning' -Issues @('C: 41.2 GB free (8.6 %), warning below 15 %', 'Disk 1 (<Example>): health Warning')
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Disk = $disk } {
                param($Disk)
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Disk' -DiskHealth $Disk
            }
            $html | Should -Match '<div class="callout callout-warn"><strong>Issues</strong><ul class="issues"><li>C: 41.2 GB free'
            $html | Should -Match '<li>Disk 1 \(&lt;Example&gt;\): health Warning</li>'
            $html | Should -Match '<div class="card-value">2 issues</div>'
        }
    }

    Context 'Missing data' {
        It 'writes a section that could not be collected, with the reason' {
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' {
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'System', 'Disk' -SectionError @{ System = 'Access <denied>' } -DiskHealth $null
            }
            $html | Should -Match '<section id="system"'
            $html | Should -Match '<p class="missing">Not collected: Access &lt;denied&gt;</p>'
            $html | Should -Match '<p class="missing">Not collected: The command returned no result.</p>'
            ([regex]::Matches($html, '<span class="badge badge-muted">Not collected</span>')).Count | Should -Be 4
        }

        It 'tells an empty software list apart from a list that was not collected' {
            $empty = InModuleScope -ModuleName 'HelpdeskToolkit' {
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Software' -InstalledSoftware @()
            }
            $empty | Should -Match '<p class="empty">No program found.</p>'
            $empty | Should -Match '<div class="card-value">No program</div>'

            $missing = InModuleScope -ModuleName 'HelpdeskToolkit' {
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Software'
            }
            $missing | Should -Match 'Not collected'
        }

        It 'writes only the sections asked for, without contents for a single section' {
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Disk = (New-FakeDiskHealth) } {
                param($Disk)
                ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Disk' -DiskHealth $Disk
            }
            $html | Should -Not -Match '<section id="system"'
            $html | Should -Not -Match '<nav class="toc"'
            $html | Should -Not -Match '<dt>Ticket</dt>'
        }
    }

    Context 'Untrusted text' {
        It 'encodes values that come from the computer everywhere they appear' {
            $parameters = @{
                Software = @(New-FakeSoftware -Name '<script>alert(1)</script>')
                Ticket   = 'INC-1'
            }
            $html = InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
                param($Software, $Ticket)
                ConvertTo-ReportHtml -ComputerName 'PC-<b>X</b>' -Section 'Software' -InstalledSoftware $Software -TicketNumber $Ticket
            }
            $html | Should -Not -Match '<script'
            $html | Should -Not -Match '<b>X'
            $html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
            $html | Should -Match '<title>Helpdesk report - PC-&lt;b&gt;X&lt;/b&gt; - ticket INC-1</title>'
        }
    }
}
