#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }
<#
    The style sheet is text, so the tests check what matters for the
    report: one palette per theme, the switch and print rules, nothing
    loaded from outside, and readable colours. The contrast ratio is the
    WCAG 2 formula, computed from the colours found in the CSS itself.
#>

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force

    $css = InModuleScope -ModuleName 'HelpdeskToolkit' { Get-ReportStyleSheet }

    # Variables of the first block that matches the selector exactly
    function Get-Palette {
        param([string]$Css, [string]$Selector, [int]$Index = 0)
        $blocks = [regex]::Matches($Css, '(?m)^' + [regex]::Escape($Selector) + ' \{\n(?<body>[^}]*)\}')
        $palette = @{}
        foreach ($line in ($blocks[$Index].Groups['body'].Value -split "`n")) {
            if ($line -match '^\s*(--[a-z]+):\s*(#[0-9a-f]{6});') {
                $palette[$Matches[1]] = $Matches[2]
            }
        }
        $palette
    }

    # WCAG 2 relative luminance and contrast ratio
    function Get-Luminance {
        param([string]$Hex)
        $channels = foreach ($offset in 1, 3, 5) {
            $value = [Convert]::ToInt32($Hex.Substring($offset, 2), 16) / 255
            if ($value -le 0.03928) { $value / 12.92 } else { [math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
    }

    function Get-ContrastRatio {
        param([string]$Foreground, [string]$Background)
        $a = Get-Luminance -Hex $Foreground
        $b = Get-Luminance -Hex $Background
        ([math]::Max($a, $b) + 0.05) / ([math]::Min($a, $b) + 0.05)
    }

    $dark = Get-Palette -Css $css -Selector ':root' -Index 0
    $light = Get-Palette -Css $css -Selector ':root' -Index 1
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'Get-ReportStyleSheet' {
    It 'uses the dark palette of the profile by default' {
        $dark['--bg'] | Should -Be '#070d1c'
        $dark['--ok'] | Should -Be '#3fe0a0'
        $dark['--accent'] | Should -Be '#2b9dff'
        $dark['--warn'] | Should -Be '#ffb454'
        $dark['--brand'] | Should -Be '#c792ea'
    }

    It 'defines the same variables in the dark and light palettes' {
        ($light.Keys | Sort-Object) -join ',' | Should -Be (($dark.Keys | Sort-Object) -join ',')
        $light['--bg'] | Should -Not -Be $dark['--bg']
    }

    It 'follows the theme of the system' {
        $css | Should -Match '@media \(prefers-color-scheme: light\)'
    }

    It 'swaps the themes with the checkbox, without JavaScript' {
        $css | Should -Match ':root:has\(#theme-switch:checked\)'
    }

    It 'prints with the light theme and hides the switch' {
        $css | Should -Match '@media print \{\n:root, :root:has\(#theme-switch:checked\) \{'
        $css | Should -Match '\.theme-switch, \.toc \{ display: none; \}'
    }

    It 'loads nothing from outside the file' {
        $css | Should -Not -Match '@import'
        $css | Should -Not -Match 'url\('
        $css | Should -Not -Match 'https?://'
    }

    It 'is plain ASCII, like the source files' {
        @([System.Text.Encoding]::UTF8.GetBytes($css) | Where-Object { $_ -gt 0x7F }).Count | Should -Be 0
    }

    It 'keeps <Variable> readable on the <Theme> background and surface (4.5:1 or more)' -ForEach @(
        foreach ($theme in 'dark', 'light') {
            foreach ($variable in '--text', '--muted', '--accent', '--ok', '--warn', '--crit') {
                @{ Theme = $theme; Variable = $variable }
            }
        }
    ) {
        $palette = if ($Theme -eq 'dark') { $dark } else { $light }
        foreach ($background in '--bg', '--surface') {
            Get-ContrastRatio -Foreground $palette[$Variable] -Background $palette[$background] |
                Should -BeGreaterOrEqual 4.5 -Because "$Variable on $background in the $Theme theme"
        }
    }
}
