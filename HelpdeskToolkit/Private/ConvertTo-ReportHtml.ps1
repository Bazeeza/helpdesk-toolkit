function ConvertTo-ReportHtml {
    <#
    .SYNOPSIS
        Assembles the complete HTML page of the help desk report from the
        results of the commands of the module.

    .DESCRIPTION
        Private helper of Export-HelpdeskReport. It only turns objects into
        text: it reads nothing on the computer and writes no file, so it can
        be tested with fictitious results.

        The page has, in this order:

          header     computer name, ticket number, date and time, module version
          contents   links to the sections
          cards      one summary card per section, coloured by status
          sections   System, Network, Disk health, Installed software
          footer     what the report is and what it contains

        A section that was asked for but could not be collected is still
        written, with the reason, so the reader knows the data is missing
        rather than healthy. Every value goes through ConvertTo-HtmlText.

        The page declares a Content-Security-Policy that allows only the
        embedded style sheet: no script, no image, font or frame from
        anywhere. Even if a value slipped through without encoding, the
        browser would refuse to run a script from it.

    .PARAMETER ComputerName
        Name of the computer, shown in the header and the page title.

    .PARAMETER Section
        Sections to write: System, Network, Disk, Software. They are always
        written in that order.

    .PARAMETER SystemReport
        Result of Get-SystemReport.

    .PARAMETER NetworkHealth
        Result of Test-NetworkHealth.

    .PARAMETER DiskHealth
        Result of Get-DiskHealth.

    .PARAMETER InstalledSoftware
        Results of Get-InstalledSoftware. An empty list means that the
        command ran and found no program.

    .PARAMETER SectionError
        Reason why a section could not be collected, by section name.

    .PARAMETER TicketNumber
        Optional ticket number shown in the header and the page title.

    .PARAMETER GeneratedAt
        Date and time of the report. The default is now.

    .PARAMETER ModuleVersion
        Version of the module, shown in the footer.

    .EXAMPLE
        ConvertTo-ReportHtml -ComputerName 'PC-EXAMPLE01' -Section 'Disk' -DiskHealth (Get-DiskHealth)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('System', 'Network', 'Disk', 'Software')]
        [string[]]$Section,

        [object]$SystemReport,

        [object]$NetworkHealth,

        [object]$DiskHealth,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InstalledSoftware,

        [hashtable]$SectionError = @{},

        [string]$TicketNumber,

        [datetime]$GeneratedAt = (Get-Date),

        [string]$ModuleVersion
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $softwareCollected = $PSBoundParameters.ContainsKey('InstalledSoftware') -and $null -ne $InstalledSoftware

    # --- Small local helpers ----------------------------------------------------------------
    # Property value or $null: tolerates objects that lack a property under strict mode
    function Get-Field {
        param([object]$InputObject, [string]$Name)
        if ($null -eq $InputObject) { return $null }
        $member = $InputObject.PSObject.Properties[$Name]
        if ($member) { return $member.Value }
        $null
    }

    # Two-column table of names and values; an empty value reads "Not reported"
    function ConvertTo-FactTable {
        param([System.Collections.IDictionary]$Fact)
        $rows = foreach ($key in $Fact.Keys) {
            $value = $Fact[$key]
            if ($null -eq $value -or "$value".Trim() -eq '') {
                $value = 'Not reported'
            }
            [pscustomobject]@{ Item = $key; Value = $value }
        }
        ConvertTo-ReportTable -InputObject @($rows) -Property 'Item', 'Value' -NoHeader -Class 'facts'
    }

    function Format-Date {
        param([object]$Value, [string]$Format = 'yyyy-MM-dd HH:mm')
        if ($Value -is [datetime]) { return $Value.ToString($Format, $culture) }
        $null
    }

    # --- What each section shows ------------------------------------------------------------
    $titles = [ordered]@{
        System   = 'System'
        Network  = 'Network'
        Disk     = 'Disk health'
        Software = 'Installed software'
    }
    $order = @($titles.Keys | Where-Object { $_ -in $Section })

    # Status, card and body of each section, or the reason it is missing
    $parts = @{}
    foreach ($name in $order) {
        $data = switch ($name) {
            'System' { $SystemReport }
            'Network' { $NetworkHealth }
            'Disk' { $DiskHealth }
            'Software' { if ($softwareCollected) { , $InstalledSoftware } }
        }

        if ($null -eq $data) {
            $reason = 'The command returned no result.'
            if ($SectionError.ContainsKey($name) -and $SectionError[$name]) {
                $reason = [string]$SectionError[$name]
            }
            $parts[$name] = @{
                Status = 'Not collected'
                Value  = 'Not collected'
                Detail = 'See the section below.'
                Body   = '<p class="missing">Not collected: {0}</p>' -f (ConvertTo-HtmlText -Value $reason)
            }
            continue
        }

        switch ($name) {
            'System' {
                $cores = Get-Field $data 'Cores'
                $logical = Get-Field $data 'LogicalProcessors'
                $processor = Get-Field $data 'Processor'
                if ($cores) {
                    $processor = '{0} ({1} cores, {2} logical processors)' -f $processor, $cores, $logical
                }
                $memory = Get-Field $data 'Memory'
                $memoryUsed = Get-Field $data 'MemoryUsedPercent'
                if ($null -ne $memoryUsed) {
                    $memory = '{0} ({1} % in use)' -f $memory, $memoryUsed.ToString($culture)
                }
                $facts = [ordered]@{
                    'Computer name'    = Get-Field $data 'ComputerName'
                    'Manufacturer'     = Get-Field $data 'Manufacturer'
                    'Model'            = Get-Field $data 'Model'
                    'Serial number'    = Get-Field $data 'SerialNumber'
                    'Firmware version' = Get-Field $data 'BiosVersion'
                    'Operating system' = Get-Field $data 'OperatingSystem'
                    'Version and build' = '{0} (build {1})' -f (Get-Field $data 'Version'), (Get-Field $data 'Build')
                    'Architecture'     = Get-Field $data 'Architecture'
                    'Windows installed' = Format-Date (Get-Field $data 'InstallDate') 'yyyy-MM-dd'
                    'Processor'        = $processor
                    'Memory'           = $memory
                    'Last boot'        = Format-Date (Get-Field $data 'LastBootTime')
                    'Uptime'           = Get-Field $data 'UptimeText'
                }
                $disks = ConvertTo-ReportTable -InputObject @(Get-Field $data 'Disks') `
                    -Property 'Drive', 'Label', 'FileSystem', 'Size', 'Free', 'FreePercent' `
                    -Header 'Drive', 'Label', 'File system', 'Size', 'Free', 'Free space' `
                    -MeterProperty 'FreePercent' -EmptyText 'No local fixed disk reported.'
                $parts[$name] = @{
                    Status = $null
                    Value  = Get-Field $data 'OperatingSystem'
                    Detail = 'Up {0} - build {1}' -f (Get-Field $data 'UptimeText'), (Get-Field $data 'Build')
                    Body   = (ConvertTo-FactTable $facts) + "`n<h3>Local disks</h3>`n" + $disks
                }
            }

            'Network' {
                $checks = @(Get-Field $data 'Checks')
                $status = 'Pass'
                if (-not (Get-Field $data 'Healthy')) {
                    $status = 'Fail'
                }
                elseif (@($checks | Where-Object { (Get-Field $_ 'Status') -eq 'Warning' }).Count -gt 0) {
                    $status = 'Warning'
                }

                $address = Get-Field $data 'IPv4Address'
                if ($address -and $null -ne (Get-Field $data 'PrefixLength')) {
                    $address = '{0}/{1}' -f $address, (Get-Field $data 'PrefixLength')
                }
                $facts = [ordered]@{
                    'Adapter'         = Get-Field $data 'InterfaceAlias'
                    'Description'     = Get-Field $data 'InterfaceDescription'
                    'Link speed'      = Get-Field $data 'LinkSpeed'
                    'MAC address'     = Get-Field $data 'MacAddress'
                    'IPv4 address'    = $address
                    'Address source'  = Get-Field $data 'AddressSource'
                    'Default gateway' = Get-Field $data 'DefaultGateway'
                    'DNS servers'     = Get-Field $data 'DnsServers'
                }

                $failedStep = Get-Field $data 'FailedStep'
                $value = 'Every step answered'
                if ($failedStep) {
                    $value = "Stops at: $failedStep"
                }
                $detail = Get-Field $data 'InterfaceAlias'
                if (Get-Field $data 'LinkSpeed') {
                    $detail = '{0} at {1}' -f $detail, (Get-Field $data 'LinkSpeed')
                }

                $body = @(
                    '<p class="callout callout-{0}"><strong>Diagnosis:</strong> {1}</p>' -f (Get-ReportStatusLevel -Status $status), (ConvertTo-HtmlText -Value (Get-Field $data 'Diagnosis'))
                    '<h3>Steps, from the cable to the service</h3>'
                    ConvertTo-ReportTable -InputObject $checks -Property 'Step', 'Name', 'Status', 'Detail' -Header 'Step', 'Layer', 'Status', 'Detail' -StatusProperty 'Status'
                    '<h3>Adapter</h3>'
                    ConvertTo-FactTable $facts
                ) -join "`n"
                $parts[$name] = @{ Status = $status; Value = $value; Detail = $detail; Body = $body }
            }

            'Disk' {
                $issues = @(Get-Field $data 'Issues' | Where-Object { $_ })
                $volumes = @(Get-Field $data 'Volumes')
                $physical = @(Get-Field $data 'PhysicalDisks')

                if ($issues.Count -eq 0) {
                    $issueHtml = '<p class="callout callout-ok">No issue found.</p>'
                }
                else {
                    $items = foreach ($issue in $issues) { '<li>{0}</li>' -f (ConvertTo-HtmlText -Value $issue) }
                    $issueHtml = '<div class="callout callout-{0}"><strong>Issues</strong><ul class="issues">{1}</ul></div>' -f (Get-ReportStatusLevel -Status (Get-Field $data 'Status')), ($items -join '')
                }

                # Units added here: the objects keep plain numbers for sorting
                $drives = foreach ($disk in $physical) {
                    $temperature = Get-Field $disk 'Temperature'
                    $wear = Get-Field $disk 'Wear'
                    [pscustomobject]@{
                        Disk         = Get-Field $disk 'DeviceId'
                        Name         = Get-Field $disk 'Name'
                        MediaType    = Get-Field $disk 'MediaType'
                        BusType      = Get-Field $disk 'BusType'
                        Size         = Get-Field $disk 'Size'
                        HealthStatus = Get-Field $disk 'HealthStatus'
                        Temperature  = if ($null -ne $temperature) { "$temperature C" } else { $null }
                        Wear         = if ($null -ne $wear) { "$wear %" } else { $null }
                        PowerOnHours = Get-Field $disk 'PowerOnHours'
                        Status       = Get-Field $disk 'Status'
                    }
                }

                $body = @(
                    $issueHtml
                    '<h3>Volumes</h3>'
                    ConvertTo-ReportTable -InputObject $volumes -Property 'Drive', 'Label', 'FileSystem', 'Size', 'Free', 'FreePercent', 'Status' `
                        -Header 'Drive', 'Label', 'File system', 'Size', 'Free', 'Free space', 'Status' `
                        -MeterProperty 'FreePercent' -StatusProperty 'Status' -EmptyText 'No local fixed volume reported.'
                    '<p class="note">Thresholds: Warning below {0} % of free space, Critical below {1} %.</p>' -f (Get-Field $data 'WarningPercent'), (Get-Field $data 'CriticalPercent')
                    '<h3>Physical disks</h3>'
                    ConvertTo-ReportTable -InputObject @($drives) -Property 'Disk', 'Name', 'MediaType', 'BusType', 'Size', 'HealthStatus', 'Temperature', 'Wear', 'PowerOnHours', 'Status' `
                        -Header 'Disk', 'Name', 'Media', 'Bus', 'Size', 'Health', 'Temperature', 'Wear', 'Power-on hours', 'Status' `
                        -StatusProperty 'Status' -EmptyText 'No physical disk reported.'
                ) -join "`n"
                if (@($physical | Where-Object { -not (Get-Field $_ 'ReliabilityAvailable') }).Count -gt 0) {
                    $body += "`n" + '<p class="note">Temperature, wear and error counters were not available: Windows usually gives them only to PowerShell run as administrator.</p>'
                }

                $value = 'No issue'
                if ($issues.Count -eq 1) { $value = '1 issue' }
                elseif ($issues.Count -gt 1) { $value = "$($issues.Count) issues" }
                $parts[$name] = @{
                    Status = Get-Field $data 'Status'
                    Value  = $value
                    Detail = '{0} volume(s), {1} physical disk(s)' -f $volumes.Count, $physical.Count
                    Body   = $body
                }
            }

            'Software' {
                $programs = @($data | Where-Object { $_ })
                $rows = foreach ($program in $programs) {
                    [pscustomobject]@{
                        Name         = Get-Field $program 'Name'
                        Version      = Get-Field $program 'Version'
                        Publisher    = Get-Field $program 'Publisher'
                        InstallDate  = Format-Date (Get-Field $program 'InstallDate') 'yyyy-MM-dd'
                        Scope        = Get-Field $program 'Scope'
                        Architecture = Get-Field $program 'Architecture'
                    }
                }
                $count = 'No program'
                if ($programs.Count -eq 1) { $count = '1 program' }
                elseif ($programs.Count -gt 1) { $count = "$($programs.Count) programs" }

                $parts[$name] = @{
                    Status = $null
                    Value  = $count
                    Detail = 'As listed in Programs and Features'
                    Body   = ConvertTo-ReportTable -InputObject @($rows) -Property 'Name', 'Version', 'Publisher', 'InstallDate', 'Scope', 'Architecture' `
                        -Header 'Name', 'Version', 'Publisher', 'Installed', 'Scope', 'Architecture' -EmptyText 'No program found.'
                }
            }
        }
    }

    # --- Page ---------------------------------------------------------------------------------
    $pageTitle = "Helpdesk report - $ComputerName"
    if ($TicketNumber) {
        $pageTitle += " - ticket $TicketNumber"
    }
    $generated = $GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss', $culture) + ' (UTC' + $GeneratedAt.ToString('zzz', $culture) + ')'
    $generator = 'HelpdeskToolkit'
    if ($ModuleVersion) {
        $generator = "HelpdeskToolkit $ModuleVersion"
    }

    $meta = [ordered]@{ Computer = $ComputerName }
    if ($TicketNumber) {
        $meta.Ticket = $TicketNumber
    }
    $meta.Generated = $generated

    $html = [System.Collections.Generic.List[string]]::new()
    $html.Add('<!DOCTYPE html>')
    $html.Add('<html lang="en">')
    $html.Add('<head>')
    $html.Add('<meta charset="utf-8">')
    $html.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $html.Add('<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''">')
    $html.Add('<meta name="color-scheme" content="dark light">')
    $html.Add('<meta name="generator" content="{0}">' -f (ConvertTo-HtmlText -Value $generator))
    $html.Add('<title>{0}</title>' -f (ConvertTo-HtmlText -Value $pageTitle))
    $html.Add('<style>')
    $html.Add((Get-ReportStyleSheet))
    $html.Add('</style>')
    $html.Add('</head>')
    $html.Add('<body>')
    $html.Add('<input type="checkbox" id="theme-switch" class="theme-input" aria-label="Switch between the dark and light theme">')
    $html.Add('<div class="page">')

    $html.Add('<header class="report-header">')
    $html.Add('<div class="brand">HelpdeskToolkit</div>')
    $html.Add('<h1>Helpdesk report</h1>')
    $html.Add('<label for="theme-switch" class="theme-switch">Switch theme</label>')
    $html.Add('<dl class="meta">')
    foreach ($key in $meta.Keys) {
        # Extra parentheses: inside a method call, a comma would start a second argument
        $html.Add(('<div><dt>{0}</dt><dd>{1}</dd></div>' -f $key, (ConvertTo-HtmlText -Value $meta[$key])))
    }
    $html.Add('</dl>')
    $html.Add('</header>')

    if ($order.Count -gt 1) {
        $links = foreach ($name in $order) { '<a href="#{0}">{1}</a>' -f $name.ToLowerInvariant(), $titles[$name] }
        $html.Add('<nav class="toc" aria-label="Sections">{0}</nav>' -f ($links -join ''))
    }

    $html.Add('<div class="cards">')
    foreach ($name in $order) {
        $part = $parts[$name]
        $level = 'info'
        $badge = ''
        if ($part.Status) {
            $level = Get-ReportStatusLevel -Status $part.Status
            $badge = ConvertTo-StatusBadge -Status $part.Status
        }
        $cardClass = 'card'
        if ($level -ne 'info') {
            $cardClass = "card card-$level"
        }
        $html.Add(('<div class="{0}"><div class="card-title"><span>{1}</span>{2}</div><div class="card-value">{3}</div><div class="card-detail">{4}</div></div>' -f
                $cardClass, $titles[$name], $badge, (ConvertTo-HtmlText -Value $part.Value), (ConvertTo-HtmlText -Value $part.Detail)))
    }
    $html.Add('</div>')

    foreach ($name in $order) {
        $part = $parts[$name]
        $badge = ''
        if ($part.Status) {
            $badge = ' ' + (ConvertTo-StatusBadge -Status $part.Status)
        }
        $html.Add('<section id="{0}" aria-labelledby="{0}-title">' -f $name.ToLowerInvariant())
        $html.Add(('<h2 id="{0}-title">{1}{2}</h2>' -f $name.ToLowerInvariant(), $titles[$name], $badge))
        $html.Add($part.Body)
        $html.Add('</section>')
    }

    $html.Add(('<footer>Generated by {0} on {1}. Read-only checks: the values are the ones Windows reported at that time. The report can contain the serial number and the network addresses of the computer: share it through the ticket only.</footer>' -f
            (ConvertTo-HtmlText -Value $generator), (ConvertTo-HtmlText -Value $generated)))
    $html.Add('</div>')
    $html.Add('</body>')
    $html.Add('</html>')

    $html -join "`n"
}
