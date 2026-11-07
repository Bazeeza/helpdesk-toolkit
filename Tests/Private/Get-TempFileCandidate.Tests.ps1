#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Real files in Pester's TestDrive (a temporary folder removed after the
    tests). Ages are set with CreationTime and LastWriteTime.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    function New-AgedFile {
        param([string]$Path, [int]$CreatedDaysAgo, [int]$WrittenDaysAgo)
        $null = New-Item -Path $Path -ItemType File -Force -Value 'example'
        $item = Get-Item -LiteralPath $Path
        $item.CreationTime = (Get-Date).AddDays(-$CreatedDaysAgo)
        $item.LastWriteTime = (Get-Date).AddDays(-$WrittenDaysAgo)
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-TempFileCandidate' {
    BeforeEach {
        $root = Join-Path -Path $TestDrive -ChildPath ('Temp-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path (Join-Path -Path $root -ChildPath 'Setup\Cache') -ItemType Directory -Force
        New-AgedFile -Path (Join-Path -Path $root -ChildPath 'old.tmp') -CreatedDaysAgo 30 -WrittenDaysAgo 30
        New-AgedFile -Path (Join-Path -Path $root -ChildPath 'Setup\Cache\old.log') -CreatedDaysAgo 20 -WrittenDaysAgo 20
        New-AgedFile -Path (Join-Path -Path $root -ChildPath 'new.tmp') -CreatedDaysAgo 0 -WrittenDaysAgo 0
        # Copied today from an old file: old write time, new creation time
        New-AgedFile -Path (Join-Path -Path $root -ChildPath 'copied.tmp') -CreatedDaysAgo 0 -WrittenDaysAgo 40
        $before = (Get-Date).AddDays(-7)
    }

    It 'returns only the files created and written before the date, in every subfolder' {
        $parameters = @{ Root = $root; Before = $before }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $result = Get-TempFileCandidate -Path $Root -Before $Before
            (@($result.Files.Name) | Sort-Object) -join ',' | Should -Be 'old.log,old.tmp'
            $result.RootReadable | Should -BeTrue
            $result.UnreadableFolders | Should -Be 0
        }
    }

    It 'returns the subfolders parents first, never the folder itself' {
        $parameters = @{ Root = $root; Before = $before }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $result = Get-TempFileCandidate -Path $Root -Before $Before
            ($result.Directories.Name) -join ',' | Should -Be 'Setup,Cache'
        }
    }

    It 'never enters or returns a junction' {
        $outside = Join-Path -Path $TestDrive -ChildPath ('Documents-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $outside -ItemType Directory
        New-AgedFile -Path (Join-Path -Path $outside -ChildPath 'report.docx') -CreatedDaysAgo 60 -WrittenDaysAgo 60
        $null = New-Item -Path (Join-Path -Path $root -ChildPath 'Link') -ItemType Junction -Value $outside

        $parameters = @{ Root = $root; Before = $before }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $result = Get-TempFileCandidate -Path $Root -Before $Before
            $result.Files.Name | Should -Not -Contain 'report.docx'
            $result.Directories.Name | Should -Not -Contain 'Link'
        }
        Join-Path -Path $outside -ChildPath 'report.docx' | Should -Exist
    }

    It 'reports a folder that cannot be listed instead of failing' {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Root = (Join-Path -Path $TestDrive -ChildPath 'Missing') } {
            $result = Get-TempFileCandidate -Path $Root -Before (Get-Date)
            $result.RootReadable | Should -BeFalse
            $result.UnreadableFolders | Should -Be 1
            $result.Files | Should -HaveCount 0
        }
    }

    It 'deletes nothing' {
        $parameters = @{ Root = $root; Before = $before }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $null = Get-TempFileCandidate -Path $Root -Before $Before
        }
        @(Get-ChildItem -LiteralPath $root -Recurse -File) | Should -HaveCount 4
    }
}
