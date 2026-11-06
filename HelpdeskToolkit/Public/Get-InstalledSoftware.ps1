function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Lists the programs installed on the local computer, read from the
        uninstall registry keys: name, version, publisher and install date.

    .DESCRIPTION
        Get-InstalledSoftware answers "is it installed, which version, since
        when?" with the same list as "Installed apps" in Settings and
        "Programs and Features" in the Control Panel. It reads the uninstall
        keys of the registry:

          HKLM  SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall               64-bit programs, every user
          HKLM  SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall   32-bit programs, every user
          HKCU  Software\Microsoft\Windows\CurrentVersion\Uninstall               programs of the current user only

        The command never uses the Win32_Product CIM class. Querying
        Win32_Product makes Windows Installer check every MSI package, which
        is slow and can start a repair of packages it finds inconsistent.
        Reading the registry is fast and changes nothing.

        Like Programs and Features, the list hides entries without a display
        name, system components (SystemComponent = 1) and updates of other
        programs (ParentKeyName or a ReleaseType such as Hotfix). Use
        IncludeHidden to see them.

        Each program is one flat object, so the result can be exported with
        Export-Csv without losing information. The command only reads and
        needs no administrator rights. Programs installed by other users in
        their own profile (HKCU of another account) are not listed.

    .PARAMETER Name
        Display names to look for. Wildcards are accepted, for example
        '*Chrome*'. The default lists every program. A name that matches
        nothing returns nothing, without error.

    .PARAMETER Scope
        Machine (programs installed for every user), User (programs of the
        current user) or All (default).

    .PARAMETER IncludeHidden
        Also returns system components, updates and other entries that
        Programs and Features does not show.

    .EXAMPLE
        Get-InstalledSoftware -Name '*Chrome*', '*Firefox*'

        Is a browser installed, which version and since when?

    .EXAMPLE
        Get-InstalledSoftware | Sort-Object -Property InstallDate -Descending | Select-Object -First 10

        The ten most recently installed programs, a quick lead when a
        problem started after an installation.

    .EXAMPLE
        Get-InstalledSoftware |
            Select-Object ComputerName, Name, Version, Publisher, InstallDate, Scope, Architecture |
            Export-Csv -Path .\software.csv -NoTypeInformation -Encoding UTF8

        Software inventory of the computer saved as a CSV file, ready to
        attach to the ticket or to open in Excel.

    .EXAMPLE
        Invoke-Command -ComputerName 'PC-EXAMPLE01' -ScriptBlock {
            Import-Module -Name 'C:\Tools\HelpdeskToolkit\HelpdeskToolkit.psd1'
            Get-InstalledSoftware -Name '*VPN*'
        }

        Runs the command on a remote computer through PowerShell remoting,
        when the module is copied on it (here in C:\Tools).

    .OUTPUTS
        HelpdeskToolkit.InstalledSoftware

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key

    .LINK
        https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-software-installations
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.InstalledSoftware')]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string[]]$Name,

        [ValidateSet('All', 'Machine', 'User')]
        [string]$Scope = 'All',

        [switch]$IncludeHidden
    )

    $uninstallPath = 'Microsoft\Windows\CurrentVersion\Uninstall'

    # One entry per list read. On 64-bit Windows, the 32-bit view of
    # HKLM\SOFTWARE is the WOW6432Node key; on 32-bit Windows there is one view.
    $sources = @()
    if ($Scope -in 'All', 'Machine') {
        if ([System.Environment]::Is64BitOperatingSystem) {
            $sources += @{ Hive = 'LocalMachine'; View = 'Registry64'; Scope = 'Machine'; Architecture = '64-bit'; Drive = "HKLM:\SOFTWARE\$uninstallPath" }
            $sources += @{ Hive = 'LocalMachine'; View = 'Registry32'; Scope = 'Machine'; Architecture = '32-bit'; Drive = "HKLM:\SOFTWARE\WOW6432Node\$uninstallPath" }
        }
        else {
            $sources += @{ Hive = 'LocalMachine'; View = 'Default'; Scope = 'Machine'; Architecture = '32-bit'; Drive = "HKLM:\SOFTWARE\$uninstallPath" }
        }
    }
    if ($Scope -in 'All', 'User') {
        # HKCU\Software is shared by the 32-bit and 64-bit views: the
        # architecture of a per-user program cannot be told from its key
        $sources += @{ Hive = 'CurrentUser'; View = 'Default'; Scope = 'User'; Architecture = $null; Drive = "HKCU:\Software\$uninstallPath" }
    }

    # Release types written by updates of another program
    $updateTypes = @('Update', 'Hotfix', 'Security Update', 'Update Rollup', 'Service Pack')

    $programs = foreach ($source in $sources) {
        Write-Verbose -Message "Reading $($source.Drive)"
        $entries = Get-UninstallRegistryEntry -Hive $source.Hive -SubKey "SOFTWARE\$uninstallPath" -View $source.View

        foreach ($entry in $entries) {
            $displayName = [string]$entry.DisplayName
            $displayName = $displayName.Trim()
            if (-not $displayName) {
                # No display name: never shown by Windows, often a leftover
                continue
            }

            $isSystemComponent = ([string]$entry.SystemComponent -eq '1')
            $isUpdate = [bool]([string]$entry.ParentKeyName) -or ([string]$entry.ReleaseType -in $updateTypes)
            if (-not $IncludeHidden -and ($isSystemComponent -or $isUpdate)) {
                continue
            }

            if ($Name) {
                $matched = $false
                foreach ($pattern in $Name) {
                    if ($displayName -like $pattern) {
                        $matched = $true
                        break
                    }
                }
                if (-not $matched) {
                    continue
                }
            }

            # EstimatedSize is a DWORD in kilobytes, often missing or zero
            $sizeBytes = $null
            $sizeText = $null
            $estimatedKilobytes = 0L
            if ([long]::TryParse([string]$entry.EstimatedSize, [ref]$estimatedKilobytes) -and $estimatedKilobytes -gt 0) {
                $sizeBytes = $estimatedKilobytes * 1KB
                $sizeText = Format-ByteSize -Bytes $sizeBytes
            }

            # For an MSI package the name of the key is its product code
            $isWindowsInstaller = ([string]$entry.WindowsInstaller -eq '1')
            $productCode = $null
            if ($isWindowsInstaller -and $entry.KeyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $productCode = $entry.KeyName
            }

            [pscustomobject]@{
                PSTypeName           = 'HelpdeskToolkit.InstalledSoftware'
                ComputerName         = $env:COMPUTERNAME
                Name                 = $displayName
                Version              = ([string]$entry.DisplayVersion).Trim()
                Publisher            = ([string]$entry.Publisher).Trim()
                InstallDate          = ConvertTo-InstallDate -Value $entry.InstallDate
                Scope                = $source.Scope
                Architecture         = $source.Architecture
                EstimatedSize        = $sizeText
                EstimatedSizeBytes   = $sizeBytes
                InstallLocation      = [string]$entry.InstallLocation
                WindowsInstaller     = $isWindowsInstaller
                ProductCode          = $productCode
                SystemComponent      = $isSystemComponent
                IsUpdate             = $isUpdate
                UninstallString      = [string]$entry.UninstallString
                QuietUninstallString = [string]$entry.QuietUninstallString
                RegistryPath         = "$($source.Drive)\$($entry.KeyName)"
            }
        }
    }

    $programs | Sort-Object -Property Name, Version
}
