function Get-TempFileCandidate {
    <#
    .SYNOPSIS
        Lists the files of a temporary folder that are old enough to be
        removed, and its subfolders, without following links.

    .DESCRIPTION
        Private helper of Clear-TempFiles. It walks the folder tree itself,
        one folder at a time, instead of using Get-ChildItem -Recurse:

        - Junctions and symbolic links (reparse points) are never entered
          and never returned. A link in a temporary folder can point to a
          folder that must not be cleaned, such as a user profile.
        - A folder that cannot be listed (access denied) is counted and
          skipped; the walk goes on with the other folders.

        A file is a candidate only when both its creation time and its last
        write time are older than Before. A file copied recently keeps its
        old write time but has a new creation time, so it is kept.

        Folders are returned parents first. Removing them in reverse order
        removes the children before their parent.

    .PARAMETER Path
        Folder to walk. The folder itself is never returned.

    .PARAMETER Before
        Files created or written after this date are kept.

    .EXAMPLE
        Get-TempFileCandidate -Path $env:TEMP -Before (Get-Date).AddDays(-7)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [datetime]$Before
    )

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $directories = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    $unreadableFolders = 0
    $rootReadable = $true

    $root = [System.IO.DirectoryInfo]::new($Path)
    $pending = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $pending.Push($root)

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try {
            # GetFileSystemInfos returns an array: an access error is thrown here, not halfway
            $children = $directory.GetFileSystemInfos()
        }
        catch {
            $unreadableFolders++
            if ($directory.FullName -eq $root.FullName) {
                $rootReadable = $false
            }
            Write-Verbose -Message "Cannot list $($directory.FullName): $($_.Exception.Message)"
            continue
        }

        foreach ($child in $children) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Verbose -Message "Link skipped: $($child.FullName)"
                continue
            }
            if ($child -is [System.IO.DirectoryInfo]) {
                $directories.Add($child)
                $pending.Push($child)
            }
            elseif ($child.CreationTime -lt $Before -and $child.LastWriteTime -lt $Before) {
                $files.Add($child)
            }
        }
    }

    [pscustomobject]@{
        Files             = $files.ToArray()
        Directories       = $directories.ToArray()
        UnreadableFolders = $unreadableFolders
        RootReadable      = $rootReadable
    }
}
