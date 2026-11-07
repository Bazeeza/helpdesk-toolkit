function Get-TempLocation {
    <#
    .SYNOPSIS
        Returns the temporary folders that Clear-TempFiles may clean.

    .DESCRIPTION
        Private helper of Clear-TempFiles. The list is fixed on purpose: the
        command never accepts a free path, so a typing mistake cannot point
        it at a folder full of documents.

          User     the temporary folder of the current user (usually
                   %LOCALAPPDATA%\Temp), from [System.IO.Path]::GetTempPath()
          Windows  the Temp folder of the Windows directory (C:\Windows\Temp),
                   used by services and installers; needs administrator rights

        Being a separate function, it is also what the tests replace to work
        on a folder of Pester's TestDrive.

    .PARAMETER Name
        User, Windows, or both.

    .EXAMPLE
        Get-TempLocation -Name User, Windows
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'Windows')]
        [string[]]$Name
    )

    foreach ($locationName in ($Name | Select-Object -Unique)) {
        $path = switch ($locationName) {
            'User' { [System.IO.Path]::GetTempPath() }
            'Windows' { Join-Path -Path $env:windir -ChildPath 'Temp' }
        }
        [pscustomobject]@{
            Name = $locationName
            Path = $path.TrimEnd('\')
        }
    }
}
