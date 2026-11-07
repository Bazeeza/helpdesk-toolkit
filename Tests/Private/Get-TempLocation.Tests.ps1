#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-TempLocation' {
    It 'returns the temporary folder of the current user without a trailing backslash' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $location = Get-TempLocation -Name 'User'
            $location.Name | Should -Be 'User'
            $location.Path | Should -Be ([System.IO.Path]::GetTempPath().TrimEnd('\'))
        }
    }

    It 'returns the Temp folder of the Windows directory' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            (Get-TempLocation -Name 'Windows').Path | Should -Be (Join-Path -Path $env:windir -ChildPath 'Temp')
        }
    }

    It 'returns each location once, in the order asked' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $locations = @(Get-TempLocation -Name 'Windows', 'User', 'Windows')
            ($locations.Name) -join ',' | Should -Be 'Windows,User'
        }
    }
}
