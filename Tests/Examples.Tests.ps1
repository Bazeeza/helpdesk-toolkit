#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The scripts of the examples folder are documentation that runs: they
    must keep their help, and the ones that write files must respect -WhatIf
    and never replace a file without -Force. Only New-SampleReport is run
    completely, because it uses fictitious data; the others read the real
    computer and are checked for help and -WhatIf only.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $exampleScripts = @(
        Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'examples') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    )
}

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $examples = Join-Path -Path $repoRoot -ChildPath 'examples'
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Example script <Name>' -ForEach $exampleScripts {
    BeforeAll {
        $help = Get-Help -Name $Path -Full
    }

    It 'has a synopsis and a description' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match 'CommonParameters'
        $help.Description | Should -Not -BeNullOrEmpty
    }

    It 'has at least two examples' {
        @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
    }

    It 'is listed in examples/README.md' {
        Get-Content -Path (Join-Path -Path $examples -ChildPath 'README.md') -Raw | Should -Match ([regex]::Escape($Name))
    }
}

Describe 'New-SampleReport.ps1' {
    BeforeAll {
        $script = Join-Path -Path $examples -ChildPath 'New-SampleReport.ps1'
        $target = Join-Path -Path $TestDrive -ChildPath 'sample.html'
        $file = & $script -Path $target
        $html = Get-Content -Path $target -Raw
    }

    It 'writes the report and returns the file' {
        $file.FullName | Should -Be $target
        $html | Should -BeLike '<!DOCTYPE html>*'
    }

    It 'contains the four sections' {
        foreach ($id in 'system', 'network', 'disk', 'software') {
            $html | Should -Match ('<section id="{0}"' -f $id)
        }
    }

    It 'uses fictitious values only' {
        $html | Should -Match 'PC-EXAMPLE01'
        $html | Should -Match '00-00-5E-00-53-01'
        $html | Should -Not -Match ([regex]::Escape($env:COMPUTERNAME))
    }

    It 'shows a Warning next to Pass and OK' {
        $html | Should -Match '>Warning<'
        $html | Should -Match '>Pass<'
        $html | Should -Match '>OK<'
    }

    It 'contains no script' {
        $html | Should -Not -Match '<script'
    }

    It 'does not replace an existing file without -Force' {
        { & $script -Path $target } | Should -Throw '*already exists*'
    }

    It 'replaces it with -Force' {
        { & $script -Path $target -Force } | Should -Not -Throw
    }

    It 'writes nothing with -WhatIf' {
        $other = Join-Path -Path $TestDrive -ChildPath 'whatif.html'
        & $script -Path $other -WhatIf
        $other | Should -Not -Exist
    }
}

Describe 'Export-SoftwareInventory.ps1' {
    It 'writes nothing with -WhatIf' {
        $target = Join-Path -Path $TestDrive -ChildPath 'software.csv'
        & (Join-Path -Path $examples -ChildPath 'Export-SoftwareInventory.ps1') -Path $target -WhatIf
        $target | Should -Not -Exist
    }

    It 'does not replace an existing file without -Force' {
        $target = Join-Path -Path $TestDrive -ChildPath 'existing.csv'
        Set-Content -Path $target -Value 'keep'
        { & (Join-Path -Path $examples -ChildPath 'Export-SoftwareInventory.ps1') -Path $target } | Should -Throw '*already exists*'
        Get-Content -Path $target | Should -Be 'keep'
    }
}
