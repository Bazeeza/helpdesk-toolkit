function Clear-TempFiles {
    <#
    .SYNOPSIS
        Removes old files from the temporary folders to free disk space,
        with -WhatIf to preview and a confirmation before each folder.

    .DESCRIPTION
        Clear-TempFiles is the only command of the module that changes the
        computer, so it is built to be safe first:

        - It cleans fixed locations only: the temporary folder of the
          current user (User, the default) and C:\Windows\Temp (Windows,
          needs administrator rights). It never accepts a free path.
        - It removes only files created and written more than OlderThanDays
          days ago (7 by default), so the files of a running installer or of
          an open application are kept.
        - It never enters junctions or symbolic links.
        - A file that is in use, read-only or denied is skipped and counted;
          the cleanup goes on with the other files.
        - Empty subfolders older than OlderThanDays are removed after their
          files. The temporary folder itself is always kept.

        The command supports -WhatIf and -Confirm. Its impact is High, so
        PowerShell asks for a confirmation before each location unless
        -Confirm:$false is given. With -WhatIf nothing is removed, and the
        result still shows how many files and bytes would be freed.

        One result object per location tells what was found, removed,
        skipped and freed.

    .PARAMETER Location
        User (default), Windows, or both.

    .PARAMETER OlderThanDays
        Minimum age, in days, of the files to remove. Default 7. Use 0 to
        remove every file that is not in use.

    .EXAMPLE
        Clear-TempFiles -WhatIf

        Shows what would be removed from the temporary folder of the
        current user, and how much space it would free. Removes nothing.

    .EXAMPLE
        Clear-TempFiles

        Removes the files older than 7 days from the temporary folder of the
        current user, after a confirmation.

    .EXAMPLE
        Clear-TempFiles -Location User, Windows -OlderThanDays 30 -Confirm:$false

        In an elevated PowerShell, removes the files older than 30 days from
        both folders without asking, for example in a maintenance script.

    .EXAMPLE
        Get-DiskHealth | Select-Object -ExpandProperty Volumes
        Clear-TempFiles -WhatIf | Select-Object Location, FilesFound, SizeFound

        Checks free space first, then previews what a cleanup would free.

    .OUTPUTS
        HelpdeskToolkit.TempCleanup

    .LINK
        https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'The command empties temporary folders as a whole; the name is the one published in the roadmap.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('HelpdeskToolkit.TempCleanup')]
    param(
        [ValidateSet('User', 'Windows')]
        [string[]]$Location = 'User',

        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 7
    )

    $before = (Get-Date).AddDays(-$OlderThanDays)

    # Folders that must never be cleaned, even if a location resolved to them
    $protected = @(
        $env:windir, $env:SystemRoot, $env:USERPROFILE, $env:ProgramFiles,
        ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }

    foreach ($tempLocation in (Get-TempLocation -Name $Location)) {
        $path = [string]$tempLocation.Path

        # Safety checks before anything is listed or removed
        $refusal = $null
        if (-not $path -or -not [System.IO.Path]::IsPathRooted($path)) {
            $refusal = 'the path is empty or relative'
        }
        else {
            $fullPath = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
            $segments = @($fullPath.Split('\') | Where-Object { $_ })
            if ($fullPath.Length -le 3 -or $segments.Count -le 1) {
                $refusal = 'it is the root of a drive'
            }
            elseif ($protected -contains $fullPath) {
                $refusal = 'it is a system or profile folder'
            }
            elseif (-not ($segments | Where-Object { $_ -eq 'Temp' -or $_ -eq 'Tmp' })) {
                $refusal = 'it is not inside a folder named Temp'
            }
            elseif (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                $refusal = 'the folder does not exist'
            }
        }
        if ($refusal) {
            Write-Error -Message "$($tempLocation.Name) location '$path' was not cleaned: $refusal." -Category 'InvalidArgument' -TargetObject $path
            continue
        }

        $scan = Get-TempFileCandidate -Path $fullPath -Before $before
        if (-not $scan.RootReadable) {
            Write-Warning -Message "Cannot list '$fullPath'. Run PowerShell as administrator to clean the $($tempLocation.Name) location."
        }

        $files = @($scan.Files)
        $bytesFound = [long]0
        foreach ($file in $files) {
            $bytesFound += $file.Length
        }

        $filesRemoved = 0
        $filesSkipped = 0
        $foldersRemoved = 0
        $bytesFreed = [long]0
        $cleaned = $false

        $action = 'Remove {0} files ({1}) older than {2} days' -f $files.Count, (Format-ByteSize -Bytes $bytesFound), $OlderThanDays
        if ($files.Count -gt 0 -and $PSCmdlet.ShouldProcess($fullPath, $action)) {
            $cleaned = $true
            foreach ($file in $files) {
                try {
                    $length = $file.Length
                    $file.Delete()
                    $filesRemoved++
                    $bytesFreed += $length
                }
                catch {
                    # In use, read-only or access denied: keep it and go on
                    $filesSkipped++
                    Write-Verbose -Message "Skipped $($file.FullName): $($_.Exception.Message)"
                }
            }

            # Children first; Delete() without recursion fails on a folder that is not empty
            $directories = @($scan.Directories)
            [array]::Reverse($directories)
            foreach ($directory in $directories) {
                if ($directory.CreationTime -ge $before) {
                    continue
                }
                try {
                    $directory.Delete()
                    $foldersRemoved++
                }
                catch {
                    Write-Verbose -Message "Folder kept $($directory.FullName): $($_.Exception.Message)"
                }
            }
        }

        [pscustomobject]@{
            PSTypeName        = 'HelpdeskToolkit.TempCleanup'
            ComputerName      = $env:COMPUTERNAME
            Location          = $tempLocation.Name
            Path              = $fullPath
            OlderThanDays     = $OlderThanDays
            FilesFound        = $files.Count
            SizeFound         = Format-ByteSize -Bytes $bytesFound
            BytesFound        = $bytesFound
            Cleaned           = $cleaned
            FilesRemoved      = $filesRemoved
            FilesSkipped      = $filesSkipped
            FoldersRemoved    = $foldersRemoved
            Freed             = Format-ByteSize -Bytes $bytesFreed
            BytesFreed        = $bytesFreed
            UnreadableFolders = $scan.UnreadableFolders
        }
    }
}
