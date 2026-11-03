#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Structure tests: they apply to the whole module and to every function
    added later, so a new command cannot be merged without help, without an
    approved verb or with a file Windows PowerShell 5.1 would misread.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit'

    $publicFunctions = @(
        Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            ForEach-Object { @{ Name = $_.BaseName } }
    )
    $privateFunctions = @(
        Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            ForEach-Object { @{ Name = $_.BaseName } }
    )
    $sourceFiles = @(
        Get-ChildItem -Path $repoRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            ForEach-Object { @{ Name = $_.FullName.Substring($repoRoot.Length + 1); Path = $_.FullName } }
    )
}

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit'
    $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psd1'
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    Import-Module -Name $manifestPath -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'requires Windows PowerShell 5.1 at minimum' {
        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
    }

    It 'loads the root module of the same name' {
        $manifest.RootModule | Should -Be 'HelpdeskToolkit.psm1'
    }

    It 'has an author, a description and a project link' {
        $manifest.Author | Should -Not -BeNullOrEmpty
        $manifest.Description | Should -Not -BeNullOrEmpty
        $manifest.ProjectUri | Should -Not -BeNullOrEmpty
    }

    It 'has the version of the latest release in CHANGELOG.md' {
        $changelog = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'CHANGELOG.md')
        $latest = $changelog |
            Where-Object { $_ -match '^## \[(\d+\.\d+\.\d+)\]' } |
            Select-Object -First 1 |
            ForEach-Object { [version]($_ -replace '^## \[(\d+\.\d+\.\d+)\].*$', '$1') }
        $latest | Should -Not -BeNullOrEmpty -Because 'CHANGELOG.md needs a released version section'
        $manifest.Version | Should -Be $latest
    }

    It 'lists the exported functions explicitly, without wildcard' {
        $raw = Import-PowerShellDataFile -Path $manifestPath
        $raw.FunctionsToExport | Should -Not -Contain '*'
        $raw.CmdletsToExport | Should -Not -Contain '*'
        $raw.AliasesToExport | Should -Not -Contain '*'
    }
}

Describe 'Exported commands' {
    It 'exports exactly the functions of the Public folder' {
        $expected = @(
            Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                ForEach-Object { $_.BaseName } | Sort-Object
        )
        $exported = @(Get-Command -Module 'HelpdeskToolkit' | ForEach-Object { $_.Name } | Sort-Object)
        ($exported -join ', ') | Should -Be ($expected -join ', ')
    }

    It 'lists the same functions in the manifest and in the Public folder' {
        $expected = @(
            Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                ForEach-Object { $_.BaseName } | Sort-Object
        )
        $listed = @($manifest.ExportedFunctions.Keys | Sort-Object)
        ($listed -join ', ') | Should -Be ($expected -join ', ')
    }

    It 'keeps the private helper <Name> hidden' -ForEach $privateFunctions {
        Get-Command -Name $Name -Module 'HelpdeskToolkit' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Public command <Name>' -ForEach $publicFunctions {
    BeforeAll {
        $command = Get-Command -Name $Name -Module 'HelpdeskToolkit'
        $help = Get-Help -Name $Name -Full
    }

    It 'uses an approved verb' {
        (Get-Verb).Verb | Should -Contain $command.Verb
    }

    It 'is an advanced function' {
        $command.CmdletBinding | Should -BeTrue
    }

    It 'has a synopsis and a description' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        # Without comment-based help, Get-Help puts the syntax in the synopsis
        $help.Synopsis | Should -Not -Match 'CommonParameters'
        $help.Description | Should -Not -BeNullOrEmpty
    }

    It 'has at least one example' {
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
            @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        foreach ($parameter in $command.Parameters.Keys | Where-Object { $_ -notin $common }) {
            $parameterHelp = $help.Parameters.Parameter | Where-Object { $_.Name -eq $parameter }
            $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty -Because "parameter -$parameter needs a description"
        }
    }
}

Describe 'Source file <Name>' -ForEach $sourceFiles {
    It 'is ASCII or UTF-8 with BOM, so Windows PowerShell 5.1 reads it correctly' {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = @($bytes | Where-Object { $_ -gt 0x7F }).Count
        ($hasBom -or $nonAscii -eq 0) | Should -BeTrue -Because 'without a BOM, Windows PowerShell 5.1 decodes the file with the ANSI code page'
    }

    It 'parses without syntax errors' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
