function Test-NetworkHealth {
    <#
    .SYNOPSIS
        Tests the network of the local computer layer by layer and tells
        where it stops: link, IP address, gateway, Internet, DNS or port.

    .DESCRIPTION
        Test-NetworkHealth automates the bottom-up method of the "I have no
        Internet" runbook. Each step tests one layer, in the same order as
        a technician would:

          1 Link        the adapter is Up (cable, Wi-Fi, driver)
          2 IP address  the adapter has an IPv4 address that is not APIPA (169.254.x.x)
          3 Gateway     the default gateway answers ping
          4 Internet    a public IP address answers ping, without using DNS
          5 DNS         a name is resolved by the configured DNS servers
          6 Port        a TCP connection opens to a service (HTTPS by default)

        The result is one object with the adapter configuration, the status
        of every step (Pass, Warning, Fail or Skipped), the first step that
        failed and a short diagnosis to copy in the ticket.

        A step is Skipped when a lower layer makes it meaningless: without a
        link or without a valid address, the next tests cannot pass. A ping
        that fails is reported as a Warning instead of a Fail when a higher
        test succeeds through the same path, because many gateways and
        firewalls drop ping on purpose.

        The command only reads and tests: it does not renew the DHCP lease,
        flush the DNS cache or change any setting. It needs no administrator
        rights. The adapter is the one used by the default route, unless
        InterfaceAlias is given.

    .PARAMETER InterfaceAlias
        Name of the adapter to test, as shown by Get-NetAdapter (for example
        "Ethernet" or "Wi-Fi"). By default the adapter of the best default
        route is tested; without a default route, the first connected
        adapter.

    .PARAMETER PublicAddress
        Public IP address pinged in step 4 to test routing without DNS.
        The default is 1.1.1.1.

    .PARAMETER DnsName
        Name resolved in step 5. The default is www.microsoft.com.

    .PARAMETER TargetHost
        Host name or IP address of the service tested in step 6. The default
        is the value of DnsName.

    .PARAMETER Port
        TCP port tested in step 6, from 1 to 65535. The default is 443
        (HTTPS).

    .PARAMETER TimeoutMilliseconds
        Maximum wait of each ping and of the TCP connection, from 100 to
        10000 milliseconds. The default is 1000.

    .EXAMPLE
        Test-NetworkHealth

        Tests the adapter of the default route, up to an HTTPS connection to
        www.microsoft.com, and shows the status of each step.

    .EXAMPLE
        Test-NetworkHealth | Select-Object -ExpandProperty Checks

        Shows the six steps as a table: number, name, status and detail.

    .EXAMPLE
        Test-NetworkHealth -InterfaceAlias 'Wi-Fi' -TargetHost 'intranet.corp.example.com' -DnsName 'intranet.corp.example.com'

        Tests the Wi-Fi adapter and an internal web site, for example to
        check that the VPN or the internal DNS works.

    .EXAMPLE
        Test-NetworkHealth -TargetHost 'print01.corp.example.com' -Port 9100

        Checks that a network printer can be reached on its raw printing
        port.

    .EXAMPLE
        $health = Test-NetworkHealth
        if (-not $health.Healthy) { "$($health.FailedStep): $($health.Diagnosis)" }

        Writes the failing layer and the diagnosis, ready for the ticket.

    .OUTPUTS
        HelpdeskToolkit.NetworkHealth

    .LINK
        https://github.com/Bazeeza/Technical-Runbooks/blob/main/04-Network-Troubleshooting/README.md

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netipconfiguration
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.NetworkHealth')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$InterfaceAlias,

        [ValidateScript({
                $parsed = $null
                [System.Net.IPAddress]::TryParse($_, [ref]$parsed)
            })]
        [string]$PublicAddress = '1.1.1.1',

        [ValidateNotNullOrEmpty()]
        [string]$DnsName = 'www.microsoft.com',

        [ValidateNotNullOrEmpty()]
        [string]$TargetHost,

        [ValidateRange(1, 65535)]
        [int]$Port = 443,

        [ValidateRange(100, 10000)]
        [int]$TimeoutMilliseconds = 1000
    )

    if (-not $TargetHost) {
        $TargetHost = $DnsName
    }

    # Every step starts as Skipped; a step only runs when the layers below allow it
    $stepNames = [ordered]@{
        Link      = 'Link'
        IPAddress = 'IP address'
        Gateway   = 'Gateway'
        Internet  = 'Internet'
        DNS       = 'DNS'
        Port      = 'Port'
    }
    $steps = [ordered]@{}
    foreach ($key in $stepNames.Keys) {
        $steps[$key] = @{ Status = 'Skipped'; Detail = $null; Diagnosis = $null; ByPing = $false }
    }

    # --- Adapter: the one of the best default route, unless one is named ---------------------
    $defaultRoutes = @(
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object -Property { [int]$_.RouteMetric + [int]$_.InterfaceMetric }
    )

    $adapter = $null
    if ($InterfaceAlias) {
        $adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $adapter) {
            $errorParameters = @{
                Message      = "No network adapter named '$InterfaceAlias'. List the adapters with Get-NetAdapter."
                Category     = 'ObjectNotFound'
                TargetObject = $InterfaceAlias
            }
            Write-Error @errorParameters
            return
        }
    }
    else {
        if ($defaultRoutes.Count -gt 0) {
            $adapter = Get-NetAdapter -InterfaceIndex $defaultRoutes[0].ifIndex -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $adapter) {
            # No default route: a connected adapter, else a physical one, else any
            $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object -Property ifIndex)
            $adapter = $allAdapters | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if (-not $adapter) {
                $adapter = $allAdapters | Where-Object { $_.HardwareInterface } | Select-Object -First 1
            }
            if (-not $adapter) {
                $adapter = $allAdapters | Select-Object -First 1
            }
        }
    }

    # --- Configuration of the adapter, read once --------------------------------------------
    $ipAddress = $null
    $prefixLength = $null
    $addressSource = $null
    $gateway = $null
    $dnsServers = @()
    $apipaAddress = $null
    if ($adapter) {
        $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        $validAddress = $addresses | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        $apipaAddress = $addresses | Where-Object { $_.IPAddress -like '169.254.*' } | Select-Object -First 1
        $shownAddress = $validAddress
        if (-not $shownAddress) {
            $shownAddress = $apipaAddress
        }
        if ($shownAddress) {
            $ipAddress = $shownAddress.IPAddress
            $prefixLength = [int]$shownAddress.PrefixLength
            $addressSource = [string]$shownAddress.PrefixOrigin
        }

        # A next hop of 0.0.0.0 is an on-link route, not a gateway
        $route = $defaultRoutes | Where-Object { $_.ifIndex -eq $adapter.ifIndex } | Select-Object -First 1
        if ($route -and $route.NextHop -and $route.NextHop -ne '0.0.0.0') {
            $gateway = $route.NextHop
        }

        $dnsServers = @(
            Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                ForEach-Object { $_.ServerAddresses } |
                Where-Object { $_ }
        )
    }

    # --- Step 1: link -----------------------------------------------------------------------
    Write-Verbose -Message 'Step 1: link of the adapter'
    if (-not $adapter) {
        $steps.Link.Status = 'Fail'
        $steps.Link.Detail = 'No network adapter found.'
        $steps.Link.Diagnosis = 'Physical layer: Windows sees no network adapter. Check Device Manager and the network driver.'
    }
    elseif ($adapter.Status -eq 'Up') {
        $steps.Link.Status = 'Pass'
        $steps.Link.Detail = "$($adapter.Name) is Up at $($adapter.LinkSpeed)."
    }
    elseif ($adapter.Status -eq 'Disabled') {
        $steps.Link.Status = 'Fail'
        $steps.Link.Detail = "$($adapter.Name) is Disabled."
        $steps.Link.Diagnosis = "The adapter is turned off: Enable-NetAdapter -Name '$($adapter.Name)' (administrator)."
    }
    else {
        $steps.Link.Status = 'Fail'
        $steps.Link.Detail = "$($adapter.Name) is $($adapter.Status)."
        $steps.Link.Diagnosis = 'Physical layer: check the cable, the wall and switch port, the Wi-Fi connection or the network driver.'
    }

    # --- Step 2: IPv4 address ---------------------------------------------------------------
    $addressReady = $false
    if ($steps.Link.Status -eq 'Pass') {
        Write-Verbose -Message 'Step 2: IPv4 address'
        if ($ipAddress -and $ipAddress -notlike '169.254.*') {
            $addressReady = $true
            $steps.IPAddress.Status = 'Pass'
            $steps.IPAddress.Detail = "$ipAddress/$prefixLength ($addressSource)."
        }
        elseif ($apipaAddress) {
            $steps.IPAddress.Status = 'Fail'
            $steps.IPAddress.Detail = "APIPA address $ipAddress`: no DHCP server answered."
            $steps.IPAddress.Diagnosis = 'DHCP problem: run ipconfig /release and ipconfig /renew. If the address stays 169.254.x.x, escalate with the switch port and VLAN (wrong VLAN, scope full, missing DHCP relay or server down).'
        }
        else {
            $steps.IPAddress.Status = 'Fail'
            $steps.IPAddress.Detail = 'No IPv4 address on the adapter.'
            $steps.IPAddress.Diagnosis = 'IP configuration: the adapter has no IPv4 address. Check that DHCP is enabled or that the static configuration is complete.'
        }
    }

    if ($addressReady) {
        # --- Step 3: gateway ----------------------------------------------------------------
        Write-Verbose -Message 'Step 3: default gateway'
        if (-not $gateway) {
            $steps.Gateway.Status = 'Fail'
            $steps.Gateway.Detail = 'No default gateway.'
            $steps.Gateway.Diagnosis = 'Local network: no route outside the subnet. Check the router option of the DHCP scope or the static gateway.'
        }
        else {
            $echo = Test-IcmpEcho -ComputerName $gateway -Count 2 -TimeoutMilliseconds $TimeoutMilliseconds
            if ($echo.Succeeded) {
                $steps.Gateway.Status = 'Pass'
                $steps.Gateway.Detail = "$gateway answered in $($echo.RoundtripMilliseconds) ms."
            }
            else {
                $steps.Gateway.Status = 'Fail'
                $steps.Gateway.ByPing = $true
                $steps.Gateway.Detail = "$gateway did not answer ping ($($echo.Error))."
                $steps.Gateway.Diagnosis = 'Local network: VLAN, switch port or gateway. Some gateways block ping: confirm from a second computer on the same network.'
            }
        }

        # --- Step 4: Internet by IP address, without DNS ------------------------------------
        Write-Verbose -Message "Step 4: ping $PublicAddress"
        $echo = Test-IcmpEcho -ComputerName $PublicAddress -Count 2 -TimeoutMilliseconds $TimeoutMilliseconds
        if ($echo.Succeeded) {
            $steps.Internet.Status = 'Pass'
            $steps.Internet.Detail = "$PublicAddress answered in $($echo.RoundtripMilliseconds) ms."
        }
        else {
            $steps.Internet.Status = 'Fail'
            $steps.Internet.ByPing = $true
            $steps.Internet.Detail = "$PublicAddress did not answer ping ($($echo.Error))."
            $steps.Internet.Diagnosis = "Routing or Internet access: router, firewall or Internet provider. Run tracert $PublicAddress to find the last hop that answers."
        }

        # --- Step 5: DNS --------------------------------------------------------------------
        Write-Verbose -Message "Step 5: resolve $DnsName"
        if ($dnsServers.Count -eq 0) {
            $steps.DNS.Status = 'Fail'
            $steps.DNS.Detail = 'No DNS server configured on the adapter.'
            $steps.DNS.Diagnosis = 'DNS problem: the adapter has no DNS server. Check the DNS option of the DHCP scope or the static configuration.'
        }
        else {
            try {
                $records = @(
                    Resolve-DnsName -Name $DnsName -DnsOnly -QuickTimeout -ErrorAction Stop |
                        Where-Object { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress }
                )
                if ($records.Count -eq 0) {
                    throw 'the answer contains no address'
                }
                $resolved = @($records | ForEach-Object { $_.IPAddress } | Select-Object -First 3)
                $steps.DNS.Status = 'Pass'
                $steps.DNS.Detail = "$DnsName resolved to $($resolved -join ', ')."
            }
            catch {
                $steps.DNS.Status = 'Fail'
                $steps.DNS.Detail = "$DnsName not resolved by $($dnsServers -join ', ') ($($_.Exception.Message))."
                $steps.DNS.Diagnosis = "DNS problem: compare with nslookup $DnsName 1.1.1.1. If a public DNS server answers, escalate the configured DNS server."
            }
        }

        # --- Step 6: TCP port of the service ------------------------------------------------
        $parsedTarget = $null
        $targetIsAddress = [System.Net.IPAddress]::TryParse($TargetHost, [ref]$parsedTarget)
        if ($steps.DNS.Status -eq 'Fail' -and -not $targetIsAddress) {
            $steps.Port.Detail = "$TargetHost cannot be reached by name while DNS fails."
        }
        else {
            Write-Verbose -Message "Step 6: TCP connection to ${TargetHost}:$Port"
            $connection = Test-TcpPort -ComputerName $TargetHost -Port $Port -TimeoutMilliseconds $TimeoutMilliseconds
            if ($connection.Succeeded) {
                $steps.Port.Status = 'Pass'
                $steps.Port.Detail = "${TargetHost}:$Port answered in $($connection.ElapsedMilliseconds) ms."
            }
            else {
                $steps.Port.Status = 'Fail'
                $steps.Port.Detail = "${TargetHost}:$Port did not answer ($($connection.Error))."
                $steps.Port.Diagnosis = 'Service: a firewall or a proxy blocks the port, or the server is down. Test the same port from a second computer.'
            }
        }

        # --- Ping blocked on purpose: a higher test proves the path works -------------------
        if ($steps.Gateway.ByPing -and ($steps.Internet.Status -eq 'Pass' -or $steps.Port.Status -eq 'Pass')) {
            $steps.Gateway.Status = 'Warning'
            $steps.Gateway.Detail += ' Traffic still goes through it: the gateway probably blocks ping.'
            $steps.Gateway.Diagnosis = $null
        }
        if ($steps.Internet.ByPing -and $steps.Port.Status -eq 'Pass') {
            $steps.Internet.Status = 'Warning'
            $steps.Internet.Detail += ' The TCP test succeeded: ping is probably filtered on the way out.'
            $steps.Internet.Diagnosis = $null
        }
    }

    # --- Result -----------------------------------------------------------------------------
    $number = 0
    $checks = @(
        foreach ($key in $stepNames.Keys) {
            $number++
            $check = [pscustomobject]@{
                PSTypeName = 'HelpdeskToolkit.NetworkHealth.Check'
                Step       = $number
                Name       = $stepNames[$key]
                Status     = $steps[$key].Status
                Detail     = $steps[$key].Detail
                Diagnosis  = $steps[$key].Diagnosis
            }
            # Readable in the list view: "3 Gateway: Pass - 192.0.2.1 answered in 1 ms."
            $check | Add-Member -MemberType ScriptMethod -Name 'ToString' -Force -Value {
                if ($this.Detail) {
                    '{0} {1}: {2} - {3}' -f $this.Step, $this.Name, $this.Status, $this.Detail
                }
                else {
                    '{0} {1}: {2}' -f $this.Step, $this.Name, $this.Status
                }
            }
            $check
        }
    )

    $firstFailure = $checks | Where-Object { $_.Status -eq 'Fail' } | Select-Object -First 1
    $diagnosis = 'Every layer answered: the remaining problem is the application (browser, proxy setting, certificate or account).'
    $failedStep = $null
    if ($firstFailure) {
        $failedStep = $firstFailure.Name
        $diagnosis = $firstFailure.Diagnosis
    }

    $interfaceName = $null
    $interfaceDescription = $null
    $linkSpeed = $null
    $macAddress = $null
    if ($adapter) {
        $interfaceName = $adapter.Name
        $interfaceDescription = $adapter.InterfaceDescription
        $linkSpeed = $adapter.LinkSpeed
        $macAddress = $adapter.MacAddress
    }

    [pscustomobject]@{
        PSTypeName           = 'HelpdeskToolkit.NetworkHealth'
        ComputerName         = $env:COMPUTERNAME
        InterfaceAlias       = $interfaceName
        InterfaceDescription = $interfaceDescription
        LinkSpeed            = $linkSpeed
        MacAddress           = $macAddress
        IPv4Address          = $ipAddress
        PrefixLength         = $prefixLength
        AddressSource        = $addressSource
        DefaultGateway       = $gateway
        DnsServers           = $dnsServers
        Healthy              = (-not $firstFailure)
        FailedStep           = $failedStep
        Diagnosis            = $diagnosis
        Checks               = $checks
        CollectedAt          = Get-Date
    }
}
