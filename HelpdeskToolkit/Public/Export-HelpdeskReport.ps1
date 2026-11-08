function Export-HelpdeskReport {
    <#
    .SYNOPSIS
        Runs the diagnostics of the module and saves them as one
        self-contained HTML file to attach to the ticket.

    .DESCRIPTION
        Export-HelpdeskReport runs the read-only commands of the module on
        the local computer and writes their results in one HTML page:

          System     Get-SystemReport       Windows, hardware, memory, disks, uptime
          Network    Test-NetworkHealth     the six steps, from the link to the TCP port
          Disk       Get-DiskHealth         free space, drive health, issues
          Software   Get-InstalledSoftware  programs as in Programs and Features

        The page has a summary card per section, coloured by status, then
        the details. It is self-contained: the style sheet is embedded, and
        there is no script, image or link to an outside resource, so it
        opens the same way offline, from an e-mail or from a ticket
        attachment. It follows the dark or light theme of the system, has a
        theme switch, and prints on white paper.

        One section that fails does not stop the report: the section is
        written as "Not collected" with the reason, and a warning names it.

        Every value is HTML-encoded, because program names and other values
        come from the computer and could contain HTML.

        The command collects nothing and writes nothing with -WhatIf. It
        writes a new file only: an existing file is replaced only with
        -Force. Collecting the network section takes a few seconds (pings
        and a TCP connection with a timeout of one second each).

        The report contains the serial number, the network addresses and the
        installed programs of the computer. Share it through the ticket only.

    .PARAMETER Path
        File to create, or an existing folder to create it in. The default
        file name is HelpdeskReport-<computer>-<yyyyMMdd-HHmmss>.html in the
        current folder.

    .PARAMETER Section
        Sections to include: System, Network, Disk and Software. All four by
        default. They always appear in that order.

    .PARAMETER TicketNumber
        Ticket number shown in the header and the page title, for example
        INC-0042. Letters, digits and . _ # - only, up to 40 characters.

    .PARAMETER Force
        Replaces the file if it already exists.

    .PARAMETER PassThru
        Returns the file that was written (a FileInfo object).

    .EXAMPLE
        Export-HelpdeskReport

        Writes a report with the four sections in the current folder.

    .EXAMPLE
        Export-HelpdeskReport -Path "$env:USERPROFILE\Desktop" -TicketNumber 'INC-0042' -PassThru | Invoke-Item

        Writes the report on the desktop with the ticket number, then opens
        it in the default browser.

    .EXAMPLE
        Export-HelpdeskReport -Section Network, Disk -Path .\network-and-disk.html

        Only the network and disk sections, for a "slow and disconnected"
        ticket.

    .EXAMPLE
        Export-HelpdeskReport -WhatIf

        Shows the file that would be written, without collecting or writing
        anything.

    .OUTPUTS
        None by default. System.IO.FileInfo with -PassThru.

    .LINK
        https://github.com/Bazeeza/helpdesk-toolkit/blob/main/docs/commands/Export-HelpdeskReport.md
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [ValidateSet('System', 'Network', 'Disk', 'Software')]
        [string[]]$Section = @('System', 'Network', 'Disk', 'Software'),

        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._#-]{0,39}$')]
        [string]$TicketNumber,

        [switch]$Force,

        [switch]$PassThru
    )

    $generatedAt = Get-Date
    $computerName = $env:COMPUTERNAME

    # --- Where to write -------------------------------------------------------------------
    # Characters Windows refuses in a file name are replaced, just in case
    $safeName = $computerName
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safeName = $safeName.Replace([string]$character, '_')
    }
    $defaultName = 'HelpdeskReport-{0}-{1}.html' -f $safeName, $generatedAt.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)

    if (-not $Path) {
        $Path = $defaultName
    }
    # Relative paths start at the current PowerShell location, not the process folder
    $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        $fullPath = Join-Path -Path $fullPath -ChildPath $defaultName
    }

    $folder = Split-Path -Path $fullPath -Parent
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        $errorParameters = @{
            Message      = "The folder of '$fullPath' does not exist. Create it first or choose another path."
            Category     = 'ObjectNotFound'
            TargetObject = $fullPath
        }
        Write-Error @errorParameters
        return
    }
    if ((Test-Path -LiteralPath $fullPath -PathType Leaf) -and -not $Force) {
        $errorParameters = @{
            Message      = "The file '$fullPath' already exists. Use -Force to replace it."
            Category     = 'ResourceExists'
            TargetObject = $fullPath
        }
        Write-Error @errorParameters
        return
    }

    # -WhatIf stops here: nothing is collected and nothing is written
    if (-not $PSCmdlet.ShouldProcess($fullPath, 'Write the helpdesk HTML report')) {
        return
    }

    # --- Collect each section; one failure does not stop the others -------------------------
    $order = @(@('System', 'Network', 'Disk', 'Software') | Where-Object { $_ -in $Section })
    $results = @{}
    $sectionErrors = @{}
    $done = 0
    foreach ($name in $order) {
        Write-Progress -Activity 'Helpdesk report' -Status "Collecting $name" -PercentComplete ([int](100 * $done / $order.Count))
        Write-Verbose -Message "Collecting the $name section"
        try {
            switch ($name) {
                'System' { $results.System = Get-SystemReport -ErrorAction Stop | Select-Object -First 1 }
                'Network' { $results.Network = Test-NetworkHealth -ErrorAction Stop }
                # Its warnings are already listed in the Issues of the result
                'Disk' { $results.Disk = Get-DiskHealth -ErrorAction Stop -WarningAction SilentlyContinue }
                'Software' { $results.Software = @(Get-InstalledSoftware -ErrorAction Stop) }
            }
        }
        catch {
            $sectionErrors[$name] = $_.Exception.Message
            Write-Warning -Message "The $name section could not be collected: $($_.Exception.Message)"
        }
        $done++
    }
    Write-Progress -Activity 'Helpdesk report' -Completed

    # --- Build and write the page ---------------------------------------------------------
    $moduleVersion = $null
    if ($MyInvocation.MyCommand.Module) {
        $moduleVersion = [string]$MyInvocation.MyCommand.Module.Version
    }

    $htmlParameters = @{
        ComputerName  = $computerName
        Section       = $order
        # Index access: under strict mode, $results.System fails when the key is absent
        SystemReport  = $results['System']
        NetworkHealth = $results['Network']
        DiskHealth    = $results['Disk']
        SectionError  = $sectionErrors
        GeneratedAt   = $generatedAt
        ModuleVersion = $moduleVersion
    }
    if ($results.ContainsKey('Software')) {
        $htmlParameters.InstalledSoftware = $results['Software']
    }
    if ($TicketNumber) {
        $htmlParameters.TicketNumber = $TicketNumber
    }
    $html = ConvertTo-ReportHtml @htmlParameters

    # UTF-8 without byte order mark, as the page declares; the same bytes in 5.1 and 7
    [System.IO.File]::WriteAllText($fullPath, $html, [System.Text.UTF8Encoding]::new($false))
    Write-Verbose -Message "Report written to $fullPath"

    if ($PassThru) {
        Get-Item -LiteralPath $fullPath
    }
}
