function Test-TcpPort {
    <#
    .SYNOPSIS
        Tells if a TCP connection to a host and port opens within a timeout.

    .DESCRIPTION
        Private helper used by Test-NetworkHealth. It opens a TCP connection
        with System.Net.Sockets.TcpClient, waits at most TimeoutMilliseconds,
        then closes it. Nothing is sent to the remote service.

        Test-NetConnection -Port gives the same answer but also pings the
        host and can wait about 20 seconds before reporting a filtered port.
        A short timeout keeps the network check fast when a firewall drops
        the packets instead of refusing them.

        The result is an object with Succeeded (boolean), ElapsedMilliseconds
        and Error (the reason of a failure, empty when it succeeded).

    .PARAMETER ComputerName
        Host name or IP address to connect to.

    .PARAMETER Port
        TCP port, from 1 to 65535.

    .PARAMETER TimeoutMilliseconds
        Maximum wait for the connection, in milliseconds.

    .EXAMPLE
        Test-TcpPort -ComputerName 'www.example.com' -Port 443 -TimeoutMilliseconds 1000
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateRange(50, 60000)]
        [int]$TimeoutMilliseconds = 1000
    )

    $client = New-Object -TypeName 'System.Net.Sockets.TcpClient'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $succeeded = $false
    $reason = $null
    try {
        $connection = $client.ConnectAsync($ComputerName, $Port)
        if (-not $connection.Wait($TimeoutMilliseconds)) {
            $reason = "no answer within $TimeoutMilliseconds ms"
        }
        elseif ($client.Connected) {
            $succeeded = $true
        }
        else {
            $reason = 'connection not established'
        }
    }
    catch {
        # Wait() wraps the socket error (refused, unknown host) in an AggregateException
        $exception = $_.Exception
        while ($exception.InnerException) {
            $exception = $exception.InnerException
        }
        $reason = $exception.Message
    }
    finally {
        $stopwatch.Stop()
        $client.Close()
    }

    [pscustomobject]@{
        Succeeded           = $succeeded
        ElapsedMilliseconds = [int]$stopwatch.ElapsedMilliseconds
        Error               = $reason
    }
}
