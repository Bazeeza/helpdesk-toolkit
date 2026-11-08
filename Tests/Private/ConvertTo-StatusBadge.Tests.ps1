#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    Get-ReportStatusLevel and ConvertTo-StatusBadge are tested together:
    the badge is the level as a CSS class plus the encoded word.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-ReportStatusLevel' {
    It 'maps <Status> to <Level>' -ForEach @(
        @{ Status = 'OK'; Level = 'ok' }
        @{ Status = 'Pass'; Level = 'ok' }
        @{ Status = 'Healthy'; Level = 'ok' }
        @{ Status = 'Warning'; Level = 'warn' }
        @{ Status = 'Critical'; Level = 'crit' }
        @{ Status = 'Fail'; Level = 'crit' }
        @{ Status = 'Unhealthy'; Level = 'crit' }
        @{ Status = 'Unknown'; Level = 'muted' }
        @{ Status = 'Skipped'; Level = 'muted' }
        @{ Status = 'Not collected'; Level = 'muted' }
        @{ Status = 'pass'; Level = 'ok' }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Status = $Status; Level = $Level } {
            param($Status, $Level)
            Get-ReportStatusLevel -Status $Status | Should -BeExactly $Level
        }
    }

    It 'never shows an unknown or empty word as healthy' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            Get-ReportStatusLevel -Status 'Degraded' | Should -Be 'muted'
            Get-ReportStatusLevel -Status 'OK but slow' | Should -Be 'muted'
            Get-ReportStatusLevel -Status '' | Should -Be 'muted'
            Get-ReportStatusLevel -Status $null | Should -Be 'muted'
        }
    }
}

Describe 'ConvertTo-StatusBadge' {
    It 'writes the level as a CSS class and the word as text' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-StatusBadge -Status 'Warning' | Should -BeExactly '<span class="badge badge-warn">Warning</span>'
            ConvertTo-StatusBadge -Status 'Pass' | Should -BeExactly '<span class="badge badge-ok">Pass</span>'
        }
    }

    It 'shows Unknown when there is no status' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-StatusBadge -Status $null | Should -BeExactly '<span class="badge badge-muted">Unknown</span>'
            ConvertTo-StatusBadge -Status '  ' | Should -BeExactly '<span class="badge badge-muted">Unknown</span>'
        }
    }

    It 'encodes an unexpected word instead of writing it as HTML' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-StatusBadge -Status '<b>Fail</b>' | Should -BeExactly '<span class="badge badge-muted">&lt;b&gt;Fail&lt;/b&gt;</span>'
        }
    }
}
