function Test-IcmpEcho {
    <#
    .SYNOPSIS
        Sends ICMP echo requests (ping) and tells if at least one reply came back.

    .DESCRIPTION
        Private helper used by Test-NetworkHealth. It uses the .NET class
        System.Net.NetworkInformation.Ping, which behaves the same way in
        Windows PowerShell 5.1 and PowerShell 7. Test-Connection does not:
        its parameters and its output object changed in PowerShell 7.

        The result is an object with Succeeded (at least one reply),
        Sent, Received, RoundtripMilliseconds (fastest reply, empty when
        there is none) and Error (the last status or error when nothing
        answered).

    .PARAMETER ComputerName
        Host name or IP address to ping.

    .PARAMETER Count
        Number of echo requests, from 1 to 10.

    .PARAMETER TimeoutMilliseconds
        Maximum wait for each reply, in milliseconds.

    .EXAMPLE
        Test-IcmpEcho -ComputerName '192.0.2.1' -Count 2 -TimeoutMilliseconds 1000
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [ValidateRange(1, 10)]
        [int]$Count = 2,

        [ValidateRange(50, 60000)]
        [int]$TimeoutMilliseconds = 1000
    )

    $ping = New-Object -TypeName 'System.Net.NetworkInformation.Ping'
    $received = 0
    $fastest = $null
    $reason = $null
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            try {
                $reply = $ping.Send($ComputerName, $TimeoutMilliseconds)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $received++
                    if ($null -eq $fastest -or $reply.RoundtripTime -lt $fastest) {
                        $fastest = [int]$reply.RoundtripTime
                    }
                }
                else {
                    # TimedOut, DestinationHostUnreachable...
                    $reason = [string]$reply.Status
                }
            }
            catch {
                # PingException: unknown host name or no network
                $exception = $_.Exception
                while ($exception.InnerException) {
                    $exception = $exception.InnerException
                }
                $reason = $exception.Message
            }
        }
    }
    finally {
        $ping.Dispose()
    }

    if ($received -gt 0) {
        $reason = $null
    }

    [pscustomobject]@{
        Succeeded             = ($received -gt 0)
        Sent                  = $Count
        Received              = $received
        RoundtripMilliseconds = $fastest
        Error                 = $reason
    }
}
