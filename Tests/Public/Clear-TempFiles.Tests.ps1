#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The private helper Get-TempLocation is mocked so that the command works
    on a folder named Temp inside Pester's TestDrive: the tests create and
    remove real files there, and never touch the temporary folders of the
    computer they run on. Tests that check the safety rules also use -WhatIf.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    function New-AgedItem {
        param([string]$Path, [int]$DaysAgo, [switch]$Directory)
        if ($Directory) {
            $null = New-Item -Path $Path -ItemType Directory -Force
        }
        else {
            $null = New-Item -Path $Path -ItemType File -Force -Value ('x' * 1024)
        }
        $item = Get-Item -LiteralPath $Path
        $item.CreationTime = (Get-Date).AddDays(-$DaysAgo)
        $item.LastWriteTime = (Get-Date).AddDays(-$DaysAgo)
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Clear-TempFiles' {
    BeforeEach {
        $script:root = Join-Path -Path $TestDrive -ChildPath ('Case-' + [guid]::NewGuid().ToString('N') + '\Temp')
        $null = New-Item -Path $script:root -ItemType Directory -Force
        New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'Setup') -DaysAgo 30 -Directory
        New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'Setup\Cache') -DaysAgo 30 -Directory
        New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'old.tmp') -DaysAgo 30
        New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'Setup\Cache\old.log') -DaysAgo 20
        New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'new.tmp') -DaysAgo 0

        Mock -CommandName 'Get-TempLocation' -ModuleName 'HelpdeskToolkit' -MockWith {
            [pscustomobject]@{ Name = 'User'; Path = $script:root }
        }
    }

    Context 'Command design' {
        It 'supports -WhatIf and -Confirm with a High impact, so it asks by default' {
            $command = Get-Command -Name 'Clear-TempFiles' -Module 'HelpdeskToolkit'
            $command.Parameters.Keys | Should -Contain 'WhatIf'
            $command.Parameters.Keys | Should -Contain 'Confirm'
            $binding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $binding.ConfirmImpact | Should -Be 'High'
        }

        It 'accepts only the fixed locations, never a free path' {
            $command = Get-Command -Name 'Clear-TempFiles' -Module 'HelpdeskToolkit'
            $command.Parameters.Keys | Should -Not -Contain 'Path'
            { Clear-TempFiles -Location 'C:\' -WhatIf } | Should -Throw
        }
    }

    Context 'Preview with -WhatIf' {
        It 'removes nothing and reports what would be freed' {
            $result = Clear-TempFiles -WhatIf
            $result.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.TempCleanup'
            $result.FilesFound | Should -Be 2
            $result.BytesFound | Should -Be 2048
            $result.SizeFound | Should -Be '2 KB'
            $result.Cleaned | Should -BeFalse
            $result.FilesRemoved | Should -Be 0
            $result.BytesFreed | Should -Be 0
            @(Get-ChildItem -LiteralPath $script:root -Recurse -File) | Should -HaveCount 3
        }
    }

    Context 'Cleanup' {
        It 'removes the old files and keeps the recent one' {
            $result = Clear-TempFiles -Confirm:$false
            $result.Cleaned | Should -BeTrue
            $result.FilesRemoved | Should -Be 2
            $result.BytesFreed | Should -Be 2048
            $result.Freed | Should -Be '2 KB'
            Join-Path -Path $script:root -ChildPath 'new.tmp' | Should -Exist
            Join-Path -Path $script:root -ChildPath 'old.tmp' | Should -Not -Exist
        }

        It 'removes the old subfolders left empty, but keeps the temporary folder itself' {
            $result = Clear-TempFiles -Confirm:$false
            $result.FoldersRemoved | Should -Be 2
            Join-Path -Path $script:root -ChildPath 'Setup' | Should -Not -Exist
            $script:root | Should -Exist
        }

        It 'keeps a recent subfolder even when it is empty' {
            New-AgedItem -Path (Join-Path -Path $script:root -ChildPath 'Running') -DaysAgo 0 -Directory
            $null = Clear-TempFiles -Confirm:$false
            Join-Path -Path $script:root -ChildPath 'Running' | Should -Exist
        }

        It 'respects -OlderThanDays' {
            $result = Clear-TempFiles -OlderThanDays 25 -Confirm:$false
            $result.FilesRemoved | Should -Be 1
            Join-Path -Path $script:root -ChildPath 'Setup\Cache\old.log' | Should -Exist
        }

        It 'skips a file in use and goes on with the others' {
            $lockedPath = Join-Path -Path $script:root -ChildPath 'old.tmp'
            $stream = [System.IO.File]::Open($lockedPath, 'Open', 'Read', 'None')
            try {
                $result = Clear-TempFiles -Confirm:$false
            }
            finally {
                $stream.Dispose()
            }
            $result.FilesSkipped | Should -Be 1
            $result.FilesRemoved | Should -Be 1
            $lockedPath | Should -Exist
        }

        It 'never follows a junction out of the temporary folder' {
            $outside = Join-Path -Path $TestDrive -ChildPath ('Documents-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $outside -ItemType Directory
            New-AgedItem -Path (Join-Path -Path $outside -ChildPath 'report.docx') -DaysAgo 60
            $null = New-Item -Path (Join-Path -Path $script:root -ChildPath 'Link') -ItemType Junction -Value $outside

            $null = Clear-TempFiles -Confirm:$false
            Join-Path -Path $outside -ChildPath 'report.docx' | Should -Exist
        }

        It 'reports zero and cleans nothing when no file is old enough' {
            Remove-Item -LiteralPath (Join-Path -Path $script:root -ChildPath 'old.tmp'), (Join-Path -Path $script:root -ChildPath 'Setup') -Recurse -Force
            $result = Clear-TempFiles -Confirm:$false
            $result.FilesFound | Should -Be 0
            $result.Cleaned | Should -BeFalse
        }
    }

    Context 'Safety rules' {
        It 'refuses <Case>' -ForEach @(
            @{ Case = 'the root of a drive'; Path = 'C:\'; Reason = '*root of a drive*' }
            @{ Case = 'the Windows folder'; Path = $env:windir; Reason = '*system or profile folder*' }
            @{ Case = 'a folder outside any Temp folder'; Path = (Join-Path -Path $env:windir -ChildPath 'System32'); Reason = '*not inside a folder named Temp*' }
            @{ Case = 'a relative path'; Path = 'Temp'; Reason = '*empty or relative*' }
            @{ Case = 'a folder that does not exist'; Path = 'C:\Missing-Example\Temp'; Reason = '*does not exist*' }
        ) {
            Mock -CommandName 'Get-TempLocation' -ModuleName 'HelpdeskToolkit' -MockWith {
                [pscustomobject]@{ Name = 'User'; Path = $Path }
            }
            Mock -CommandName 'Get-TempFileCandidate' -ModuleName 'HelpdeskToolkit' -MockWith { throw 'must not be called' }

            $result = Clear-TempFiles -WhatIf -ErrorAction SilentlyContinue -ErrorVariable cleanupErrors
            $result | Should -BeNullOrEmpty
            $cleanupErrors[-1].Exception.Message | Should -BeLike $Reason
            Should -Invoke -CommandName 'Get-TempFileCandidate' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
        }

        It 'warns when the folder cannot be listed' {
            Mock -CommandName 'Get-TempFileCandidate' -ModuleName 'HelpdeskToolkit' -MockWith {
                [pscustomobject]@{ Files = @(); Directories = @(); UnreadableFolders = 1; RootReadable = $false }
            }
            $result = Clear-TempFiles -Confirm:$false -WarningVariable cleanupWarnings -WarningAction SilentlyContinue
            $cleanupWarnings | Should -HaveCount 1
            $result.UnreadableFolders | Should -Be 1
        }
    }

    It 'shows a short default view' {
        $result = Clear-TempFiles -WhatIf
        $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ',' |
            Should -Be 'Location,FilesFound,SizeFound,Cleaned,FilesRemoved,FilesSkipped,Freed'
    }
}
