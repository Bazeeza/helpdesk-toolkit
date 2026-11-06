#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The private helper Get-UninstallRegistryEntry is mocked: the tests never
    read the registry of the computer they run on. Each registry list
    (64-bit, 32-bit, current user) returns fictitious entries chosen to
    cover what real computers contain: MSI packages, programs without size
    or date, leftovers without name, system components and updates.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    # One raw entry, as returned by the helper; missing values are $null
    function New-FakeEntry {
        param(
            [string]$KeyName,
            [hashtable]$Values = @{}
        )
        $entry = [ordered]@{ KeyName = $KeyName }
        foreach ($valueName in @(
                'DisplayName', 'DisplayVersion', 'Publisher', 'InstallDate', 'InstallLocation',
                'EstimatedSize', 'UninstallString', 'QuietUninstallString', 'WindowsInstaller',
                'SystemComponent', 'ParentKeyName', 'ReleaseType')) {
            $entry[$valueName] = $Values[$valueName]
        }
        [pscustomobject]$entry
    }

    $script:registry = @{
        Registry64 = @(
            New-FakeEntry -KeyName '{00000000-0000-0000-0000-000000000001}' -Values @{
                DisplayName = 'Example Editor '; DisplayVersion = '2.4.1'; Publisher = 'Contoso'
                InstallDate = '20260115'; EstimatedSize = 2048; WindowsInstaller = 1
                InstallLocation = 'C:\Program Files\Example Editor\'
                UninstallString = 'MsiExec.exe /X{00000000-0000-0000-0000-000000000001}'
            }
            New-FakeEntry -KeyName 'ExampleBrowser' -Values @{
                DisplayName = 'Example Browser'; DisplayVersion = '130.0'; Publisher = 'Fabrikam'
                InstallDate = 'not a date'; EstimatedSize = 0
                UninstallString = '"C:\Program Files\Example Browser\uninstall.exe"'
                QuietUninstallString = '"C:\Program Files\Example Browser\uninstall.exe" /S'
            }
            New-FakeEntry -KeyName 'Leftover'
            New-FakeEntry -KeyName 'ExampleRuntime' -Values @{ DisplayName = 'Example Runtime'; SystemComponent = 1 }
            New-FakeEntry -KeyName 'KB0000001' -Values @{ DisplayName = 'Hotfix for Example Editor'; ParentKeyName = 'ExampleEditor' }
            New-FakeEntry -KeyName 'ExamplePatch' -Values @{ DisplayName = 'Security Update for Example Browser'; ReleaseType = 'Security Update' }
        )
        Registry32 = @(
            New-FakeEntry -KeyName 'ExampleAgent' -Values @{
                DisplayName = 'Example VPN Agent'; DisplayVersion = '5.0'; Publisher = 'Contoso'; InstallDate = '20250301'
            }
            # Not an MSI package: the GUID-like key name is not a product code
            New-FakeEntry -KeyName '{00000000-0000-0000-0000-000000000002}' -Values @{ DisplayName = 'Another Tool'; WindowsInstaller = 0 }
        )
        User       = @(
            New-FakeEntry -KeyName 'ExampleChat' -Values @{ DisplayName = 'Example Chat'; DisplayVersion = '1.2'; Publisher = 'Fabrikam' }
        )
    }
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-InstalledSoftware' {
    BeforeEach {
        Mock -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -MockWith {
            if ($Hive -eq 'CurrentUser') {
                $script:registry.User
            }
            elseif ($View -eq 'Registry32') {
                $script:registry.Registry32
            }
            else {
                $script:registry.Registry64
            }
        }
        Mock -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -MockWith { }
    }

    Context 'Default list' -Skip:(-not [System.Environment]::Is64BitOperatingSystem) {
        BeforeEach {
            $programs = @(Get-InstalledSoftware)
        }

        It 'returns the visible programs of the three lists, sorted by name' {
            ($programs.Name) -join ',' | Should -Be 'Another Tool,Example Browser,Example Chat,Example Editor,Example VPN Agent'
            $programs[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.InstalledSoftware'
        }

        It 'hides entries without name, system components and updates' {
            $programs.Name | Should -Not -Contain 'Example Runtime'
            $programs.Name | Should -Not -Contain 'Hotfix for Example Editor'
            $programs.Name | Should -Not -Contain 'Security Update for Example Browser'
        }

        It 'trims the name and keeps version and publisher' {
            $editor = $programs | Where-Object { $_.Name -eq 'Example Editor' }
            $editor.Version | Should -Be '2.4.1'
            $editor.Publisher | Should -Be 'Contoso'
        }

        It 'tells the scope and the architecture of each program' {
            ($programs | Where-Object { $_.Name -eq 'Example Editor' }).Architecture | Should -Be '64-bit'
            ($programs | Where-Object { $_.Name -eq 'Example VPN Agent' }).Architecture | Should -Be '32-bit'
            $chat = $programs | Where-Object { $_.Name -eq 'Example Chat' }
            $chat.Scope | Should -Be 'User'
            $chat.Architecture | Should -BeNullOrEmpty
        }

        It 'converts the install date and leaves an unreadable date empty' {
            ($programs | Where-Object { $_.Name -eq 'Example Editor' }).InstallDate | Should -Be ([datetime]'2026-01-15')
            ($programs | Where-Object { $_.Name -eq 'Example Browser' }).InstallDate | Should -BeNullOrEmpty
        }

        It 'converts the estimated size from kilobytes and leaves a zero size empty' {
            $editor = $programs | Where-Object { $_.Name -eq 'Example Editor' }
            $editor.EstimatedSizeBytes | Should -Be 2097152
            $editor.EstimatedSize | Should -Be '2 MB'
            ($programs | Where-Object { $_.Name -eq 'Example Browser' }).EstimatedSize | Should -BeNullOrEmpty
        }

        It 'gives the product code of MSI packages only' {
            $editor = $programs | Where-Object { $_.Name -eq 'Example Editor' }
            $editor.WindowsInstaller | Should -BeTrue
            $editor.ProductCode | Should -Be '{00000000-0000-0000-0000-000000000001}'
            ($programs | Where-Object { $_.Name -eq 'Another Tool' }).ProductCode | Should -BeNullOrEmpty
        }

        It 'keeps the uninstall commands and the registry path of the key' {
            $browser = $programs | Where-Object { $_.Name -eq 'Example Browser' }
            $browser.QuietUninstallString | Should -BeLike '* /S'
            ($programs | Where-Object { $_.Name -eq 'Example VPN Agent' }).RegistryPath |
                Should -Be 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ExampleAgent'
            ($programs | Where-Object { $_.Name -eq 'Example Chat' }).RegistryPath |
                Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ExampleChat'
        }

        It 'returns flat objects, so Export-Csv keeps every value' {
            foreach ($property in $programs[0].PSObject.Properties) {
                if ($null -ne $property.Value) {
                    $property.Value.GetType().IsArray | Should -BeFalse -Because "$($property.Name) must be one value"
                    $property.Value | Should -Not -BeOfType [System.Management.Automation.PSCustomObject]
                }
            }
            $csv = @($programs | ConvertTo-Csv -NoTypeInformation)
            $csv | Should -HaveCount 6
            $csv[0] | Should -BeLike '"ComputerName","Name","Version","Publisher","InstallDate",*'
        }

        It 'shows a short default view in the console but keeps every property' {
            $default = $programs[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            ($default -join ',') | Should -Be 'Name,Version,Publisher,InstallDate,Scope,Architecture'
            $programs[0].PSObject.Properties.Name | Should -Contain 'UninstallString'
        }

        It 'reads the 64-bit, 32-bit and current user lists, never Win32_Product' {
            Should -Invoke -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter { $Hive -eq 'LocalMachine' -and $View -eq 'Registry64' }
            Should -Invoke -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter { $Hive -eq 'LocalMachine' -and $View -eq 'Registry32' }
            Should -Invoke -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -Times 1 -Exactly -ParameterFilter { $Hive -eq 'CurrentUser' }
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly
        }
    }

    Context 'Filters' {
        It 'keeps the programs that match one of the wildcard names' {
            $names = @(Get-InstalledSoftware -Name '*Editor*', 'example vpn*').Name
            ($names -join ',') | Should -Be 'Example Editor,Example VPN Agent'
        }

        It 'returns nothing, without error, when no program matches' {
            @(Get-InstalledSoftware -Name 'No Such Program*' -ErrorAction Stop) | Should -HaveCount 0
        }

        It 'reads only the computer-wide lists with -Scope Machine' {
            $programs = @(Get-InstalledSoftware -Scope Machine)
            $programs.Scope | Should -Not -Contain 'User'
            Should -Invoke -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly -ParameterFilter { $Hive -eq 'CurrentUser' }
        }

        It 'reads only the current user list with -Scope User' {
            ($(Get-InstalledSoftware -Scope User).Name) | Should -Be 'Example Chat'
            Should -Invoke -CommandName 'Get-UninstallRegistryEntry' -ModuleName 'HelpdeskToolkit' -Times 0 -Exactly -ParameterFilter { $Hive -eq 'LocalMachine' }
        }

        It 'accepts the name as the first positional parameter' {
            @(Get-InstalledSoftware '*Chat').Name | Should -Be 'Example Chat'
        }
    }

    Context 'Hidden entries' {
        BeforeEach {
            $programs = @(Get-InstalledSoftware -IncludeHidden)
        }

        It 'adds system components and updates with -IncludeHidden' {
            $programs.Name | Should -Contain 'Example Runtime'
            $programs.Name | Should -Contain 'Hotfix for Example Editor'
            $programs.Name | Should -Contain 'Security Update for Example Browser'
        }

        It 'flags why an entry is normally hidden' {
            ($programs | Where-Object { $_.Name -eq 'Example Runtime' }).SystemComponent | Should -BeTrue
            ($programs | Where-Object { $_.Name -eq 'Hotfix for Example Editor' }).IsUpdate | Should -BeTrue
            ($programs | Where-Object { $_.Name -eq 'Security Update for Example Browser' }).IsUpdate | Should -BeTrue
            ($programs | Where-Object { $_.Name -eq 'Example Editor' }).IsUpdate | Should -BeFalse
        }

        It 'still skips keys without a display name' {
            $programs | Should -HaveCount 8
        }
    }
}
