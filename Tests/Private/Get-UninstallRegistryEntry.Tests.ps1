#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The helper reads the real registry, so these tests build a fictitious
    uninstall key in TestRegistry:, a temporary key under HKEY_CURRENT_USER
    that Pester creates for the test and deletes afterwards. Nothing is
    written anywhere else.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-UninstallRegistryEntry' {
    BeforeAll {
        # Path of TestRegistry: inside HKEY_CURRENT_USER, as the helper expects it
        $uninstall = New-Item -Path 'TestRegistry:\' -Name 'Uninstall'
        $script:subKey = $uninstall.Name -replace '^HKEY_CURRENT_USER\\', ''

        $msi = New-Item -Path $uninstall.PSPath -Name '{00000000-0000-0000-0000-000000000001}'
        $null = New-ItemProperty -Path $msi.PSPath -Name 'DisplayName' -Value 'Example Editor'
        $null = New-ItemProperty -Path $msi.PSPath -Name 'DisplayVersion' -Value '2.4.1'
        $null = New-ItemProperty -Path $msi.PSPath -Name 'Publisher' -Value 'Contoso'
        $null = New-ItemProperty -Path $msi.PSPath -Name 'InstallDate' -Value '20260115'
        $null = New-ItemProperty -Path $msi.PSPath -Name 'EstimatedSize' -Value 2048 -PropertyType DWord
        $null = New-ItemProperty -Path $msi.PSPath -Name 'WindowsInstaller' -Value 1 -PropertyType DWord

        # A key without any value, as left behind by some uninstallers
        $null = New-Item -Path $uninstall.PSPath -Name 'EmptyLeftover'
    }

    It 'returns one entry per subkey' {
        $parameters = @{ SubKey = $script:subKey }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $entries = @(Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey)
            $entries | Should -HaveCount 2
            ($entries.KeyName | Sort-Object) -join ',' | Should -Be '{00000000-0000-0000-0000-000000000001},EmptyLeftover'
        }
    }

    It 'reads the text and number values of a subkey' {
        $parameters = @{ SubKey = $script:subKey }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $entry = Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey |
                Where-Object { $_.KeyName -like '{*' }
            $entry.DisplayName | Should -Be 'Example Editor'
            $entry.DisplayVersion | Should -Be '2.4.1'
            $entry.Publisher | Should -Be 'Contoso'
            $entry.InstallDate | Should -Be '20260115'
            $entry.EstimatedSize | Should -Be 2048
            $entry.WindowsInstaller | Should -Be 1
        }
    }

    It 'returns empty values for a subkey without values' {
        $parameters = @{ SubKey = $script:subKey }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            $entry = Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey |
                Where-Object { $_.KeyName -eq 'EmptyLeftover' }
            $entry.DisplayName | Should -BeNullOrEmpty
            $entry.SystemComponent | Should -BeNullOrEmpty
        }
    }

    It 'returns nothing, without error, when the key does not exist' {
        $parameters = @{ SubKey = $script:subKey + '\Missing' }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            @(Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey -ErrorAction Stop) | Should -HaveCount 0
        }
    }

    It 'opens the key in the requested registry view' {
        # HKEY_CURRENT_USER\Software is shared by both views, so the same entries come back
        $parameters = @{ SubKey = $script:subKey }
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters $parameters {
            @(Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey -View Registry32) | Should -HaveCount 2
            @(Get-UninstallRegistryEntry -Hive CurrentUser -SubKey $SubKey -View Registry64) | Should -HaveCount 2
        }
    }
}
