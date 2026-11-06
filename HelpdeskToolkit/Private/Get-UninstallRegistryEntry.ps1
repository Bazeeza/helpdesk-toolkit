function Get-UninstallRegistryEntry {
    <#
    .SYNOPSIS
        Reads the subkeys of one uninstall registry key, in a chosen registry view.

    .DESCRIPTION
        Private helper used by Get-InstalledSoftware. Each installed program
        registers one subkey under ...\CurrentVersion\Uninstall, the list that
        "Installed apps" and "Programs and Features" display. The helper
        returns one object per subkey with the name of the subkey and the
        values the module uses. Missing values are empty.

        The registry is opened with Microsoft.Win32.RegistryKey.OpenBaseKey
        and an explicit view. On 64-bit Windows the 32-bit programs are
        registered under WOW6432Node: Registry64 reads the 64-bit list and
        Registry32 the 32-bit list, even from a 32-bit PowerShell, which the
        HKLM: drive would silently redirect to the 32-bit list.

        A subkey that cannot be opened (permissions) is skipped with a
        verbose message. A key that does not exist returns nothing.

    .PARAMETER Hive
        LocalMachine (programs installed for every user) or CurrentUser
        (programs installed for the current user only).

    .PARAMETER SubKey
        Path of the uninstall key inside the hive, for example
        SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall.

    .PARAMETER View
        Registry64, Registry32 or Default (the view of the current process).

    .EXAMPLE
        Get-UninstallRegistryEntry -Hive LocalMachine -SubKey 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -View Registry32
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Hive,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubKey,

        [ValidateSet('Registry64', 'Registry32', 'Default')]
        [string]$View = 'Default'
    )

    $valueNames = @(
        'DisplayName', 'DisplayVersion', 'Publisher', 'InstallDate', 'InstallLocation',
        'EstimatedSize', 'UninstallString', 'QuietUninstallString', 'WindowsInstaller',
        'SystemComponent', 'ParentKeyName', 'ReleaseType'
    )

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]$Hive,
        [Microsoft.Win32.RegistryView]$View
    )
    try {
        $uninstallKey = $baseKey.OpenSubKey($SubKey)
        if (-not $uninstallKey) {
            Write-Verbose -Message "$Hive\$SubKey ($View) does not exist"
            return
        }

        try {
            foreach ($keyName in $uninstallKey.GetSubKeyNames()) {
                try {
                    $entryKey = $uninstallKey.OpenSubKey($keyName)
                }
                catch {
                    Write-Verbose -Message "Skipped $keyName`: $($_.Exception.Message)"
                    continue
                }
                if (-not $entryKey) {
                    continue
                }

                try {
                    $entry = [ordered]@{ KeyName = $keyName }
                    foreach ($valueName in $valueNames) {
                        $entry[$valueName] = $entryKey.GetValue($valueName)
                    }
                    [pscustomobject]$entry
                }
                finally {
                    $entryKey.Close()
                }
            }
        }
        finally {
            $uninstallKey.Close()
        }
    }
    finally {
        $baseKey.Close()
    }
}
