#Requires -Version 5.1

<#
.SYNOPSIS
    Writes a sample help desk report built from fictitious results, to show
    the report without exposing a real computer.

.DESCRIPTION
    Export-HelpdeskReport always reads the computer it runs on: its report
    contains a real serial number, MAC address and program list. To show
    what the report looks like (in a README, a presentation or a training
    session), this script gives the same page builder of the module a set
    of invented results instead:

      computer   PC-EXAMPLE01, serial number EX-0000-0000
      network    documentation addresses 192.0.2.0/24 (RFC 5737) and the
                 documentation MAC block 00-00-5E-00-53-xx (RFC 7042)
      disk       a system volume under the warning threshold
      software   six programs with example names

    The gateway does not answer ping while the rest of the network works,
    and the system volume is low on space, so the page shows the Pass,
    Warning and OK colours side by side.

    The page builder (ConvertTo-ReportHtml) is a private function of the
    module. The script calls it inside the scope of the module, which is
    possible in PowerShell but not meant for production scripts: use
    Export-HelpdeskReport for a real ticket.

.PARAMETER Path
    HTML file to create. The default is sample-report.html in the current
    folder.

.PARAMETER Force
    Replaces the file if it already exists.

.EXAMPLE
    .\examples\New-SampleReport.ps1

    Writes sample-report.html in the current folder.

.EXAMPLE
    .\examples\New-SampleReport.ps1 -Path "$env:TEMP\sample.html" -Force | Invoke-Item

    Replaces the sample in the temporary folder and opens it in the browser.

.OUTPUTS
    System.IO.FileInfo

.LINK
    https://github.com/Bazeeza/helpdesk-toolkit/blob/main/docs/commands/Export-HelpdeskReport.md
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([System.IO.FileInfo])]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Path = 'sample-report.html',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$manifest = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
$module = Import-Module -Name $manifest -Force -PassThru

$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
if ((Test-Path -LiteralPath $target) -and -not $Force) {
    throw "The file '$target' already exists. Use -Force to replace it."
}

# --- Fictitious results, shaped like the objects of the public commands ------------------
$system = [pscustomobject]@{
    ComputerName      = 'PC-EXAMPLE01'
    Manufacturer      = 'Example Corp'
    Model             = 'Example Book 14'
    SerialNumber      = 'EX-0000-0000'
    BiosVersion       = '1.12.0'
    OperatingSystem   = 'Microsoft Windows 11 Pro'
    Version           = '10.0.26100'
    Build             = '26100'
    Architecture      = '64-bit'
    InstallDate       = [datetime]::new(2025, 3, 14, 9, 30, 0)
    Processor         = 'Example CPU 3.0 GHz'
    Cores             = 8
    LogicalProcessors = 16
    Memory            = '16 GB'
    MemoryUsedPercent = 61.4
    Disks             = @(
        [pscustomobject]@{ Drive = 'C:'; Label = 'OS'; FileSystem = 'NTFS'; Size = '476.33 GB'; Free = '56.2 GB'; FreePercent = 11.8 }
        [pscustomobject]@{ Drive = 'D:'; Label = 'Data'; FileSystem = 'NTFS'; Size = '931.51 GB'; Free = '612.4 GB'; FreePercent = 65.7 }
    )
    LastBootTime      = [datetime]::new(2026, 11, 2, 8, 4, 0)
    UptimeText        = '6d 6h 1m'
}

$network = [pscustomobject]@{
    InterfaceAlias       = 'Ethernet'
    InterfaceDescription = 'Example Gigabit Network Adapter'
    LinkSpeed            = '1 Gbps'
    MacAddress           = '00-00-5E-00-53-01'
    IPv4Address          = '192.0.2.10'
    PrefixLength         = 24
    AddressSource        = 'Dhcp'
    DefaultGateway       = '192.0.2.1'
    DnsServers           = @('192.0.2.53', '192.0.2.54')
    Healthy              = $true
    FailedStep           = $null
    Diagnosis            = 'Every layer answered: the remaining problem is the application (browser, proxy setting, certificate or account).'
    Checks               = @(
        [pscustomobject]@{ Step = 1; Name = 'Link'; Status = 'Pass'; Detail = 'Ethernet is Up at 1 Gbps.' }
        [pscustomobject]@{ Step = 2; Name = 'IP address'; Status = 'Pass'; Detail = '192.0.2.10/24 from DHCP.' }
        [pscustomobject]@{ Step = 3; Name = 'Gateway'; Status = 'Warning'; Detail = '192.0.2.1 did not answer ping, but traffic goes through it (the Internet test passed).' }
        [pscustomobject]@{ Step = 4; Name = 'Internet'; Status = 'Pass'; Detail = '1.1.1.1 answered in 12 ms.' }
        [pscustomobject]@{ Step = 5; Name = 'DNS'; Status = 'Pass'; Detail = 'www.example.com resolved to 192.0.2.80.' }
        [pscustomobject]@{ Step = 6; Name = 'Port'; Status = 'Pass'; Detail = 'TCP 443 on www.example.com is open.' }
    )
}

$disk = [pscustomobject]@{
    Status          = 'Warning'
    Issues          = @('C: 56.2 GB free (11.8 %), warning below 15 %')
    Volumes         = @(
        [pscustomobject]@{ Drive = 'C:'; Label = 'OS'; FileSystem = 'NTFS'; Size = '476.33 GB'; Free = '56.2 GB'; FreePercent = 11.8; Status = 'Warning' }
        [pscustomobject]@{ Drive = 'D:'; Label = 'Data'; FileSystem = 'NTFS'; Size = '931.51 GB'; Free = '612.4 GB'; FreePercent = 65.7; Status = 'OK' }
    )
    PhysicalDisks   = @(
        [pscustomobject]@{ DeviceId = '0'; Name = 'Example NVMe SSD'; MediaType = 'SSD'; BusType = 'NVMe'; Size = '476.94 GB'; HealthStatus = 'Healthy'; ReliabilityAvailable = $true; Temperature = 38; Wear = 4; PowerOnHours = 2150; Status = 'OK' }
        [pscustomobject]@{ DeviceId = '1'; Name = 'Example SATA HDD'; MediaType = 'HDD'; BusType = 'SATA'; Size = '931.51 GB'; HealthStatus = 'Healthy'; ReliabilityAvailable = $true; Temperature = 34; Wear = $null; PowerOnHours = 9870; Status = 'OK' }
    )
    WarningPercent  = 15
    CriticalPercent = 5
}

function ConvertTo-SampleProgram {
    param([string]$Name, [string]$Version, [string]$Publisher, [datetime]$InstallDate, [string]$Scope = 'Machine', [string]$Architecture = '64-bit')
    [pscustomobject]@{ Name = $Name; Version = $Version; Publisher = $Publisher; InstallDate = $InstallDate; Scope = $Scope; Architecture = $Architecture }
}

$software = @(
    ConvertTo-SampleProgram -Name 'Example Browser' -Version '131.0.2' -Publisher 'Example Software Inc.' -InstallDate ([datetime]::new(2026, 10, 28))
    ConvertTo-SampleProgram -Name 'Example Chat' -Version '2.8.4' -Publisher 'Example Messaging' -InstallDate ([datetime]::new(2026, 11, 1)) -Scope 'User'
    ConvertTo-SampleProgram -Name 'Example Office Suite' -Version '16.0.1' -Publisher 'Example Software Inc.' -InstallDate ([datetime]::new(2026, 9, 10))
    ConvertTo-SampleProgram -Name 'Example PDF Reader' -Version '24.3.0' -Publisher 'Example Documents Ltd.' -InstallDate ([datetime]::new(2026, 6, 2)) -Architecture '32-bit'
    ConvertTo-SampleProgram -Name 'Example Remote Support' -Version '5.2.1' -Publisher 'Example Tools' -InstallDate ([datetime]::new(2026, 5, 19))
    ConvertTo-SampleProgram -Name 'Example VPN Client' -Version '4.10.0' -Publisher 'Example Networks' -InstallDate ([datetime]::new(2025, 12, 15))
)

$parameters = @{
    ComputerName      = $system.ComputerName
    Section           = @('System', 'Network', 'Disk', 'Software')
    SystemReport      = $system
    NetworkHealth     = $network
    DiskHealth        = $disk
    InstalledSoftware = $software
    TicketNumber      = 'INC-0042'
    GeneratedAt       = [datetime]::new(2026, 11, 8, 14, 5, 0)
    ModuleVersion     = $module.Version.ToString()
}

if ($PSCmdlet.ShouldProcess($target, 'Write sample help desk report')) {
    # Run the private page builder inside the scope of the module
    $html = & $module { param($Arguments) ConvertTo-ReportHtml @Arguments } $parameters
    [System.IO.File]::WriteAllText($target, $html, [System.Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $target
}
