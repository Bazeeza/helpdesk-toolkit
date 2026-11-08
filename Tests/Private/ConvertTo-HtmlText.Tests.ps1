#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-HtmlText' {
    It 'encodes the characters that HTML would interpret' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-HtmlText -Value 'Tools <x64> & "more"' | Should -Be 'Tools &lt;x64&gt; &amp; &quot;more&quot;'
        }
    }

    It 'never lets a script tag through' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $text = ConvertTo-HtmlText -Value "<script>alert('x')</script>"
            $text | Should -Not -Match '<'
            $text | Should -Not -Match '>'
            $text | Should -Not -Match "'"
            [System.Net.WebUtility]::HtmlDecode($text) | Should -Be "<script>alert('x')</script>"
        }
    }

    It 'returns empty text for <Name>' -ForEach @(
        @{ Name = 'null'; Value = $null }
        @{ Name = 'an empty string'; Value = '' }
        @{ Name = 'an empty array'; Value = @() }
    ) {
        InModuleScope -ModuleName 'HelpdeskToolkit' -Parameters @{ Value = $Value } {
            param($Value)
            ConvertTo-HtmlText -Value $Value | Should -Be ''
        }
    }

    It 'writes dates the same way on every workstation' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-HtmlText -Value ([datetime]::new(2026, 11, 8, 14, 5, 59)) | Should -Be '2026-11-08 14:05'
        }
    }

    It 'writes Yes or No for a Boolean' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-HtmlText -Value $true | Should -Be 'Yes'
            ConvertTo-HtmlText -Value $false | Should -Be 'No'
        }
    }

    It 'keeps a dot as decimal separator under a French culture' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $saved = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new('fr-CA')
                ConvertTo-HtmlText -Value 25.3 | Should -Be '25.3'
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $saved
            }
        }
    }

    It 'joins the items of a collection, skips empty items and encodes once' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-HtmlText -Value @('192.0.2.53', $null, '', 'A&B') | Should -Be '192.0.2.53, A&amp;B'
        }
    }

    It 'uses the ToString script method of the objects of the module' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $item = [pscustomobject]@{ Drive = 'C:' }
            $item | Add-Member -MemberType ScriptMethod -Name 'ToString' -Force -Value { 'Drive ' + $this.Drive }
            ConvertTo-HtmlText -Value $item | Should -Be 'Drive C:'
        }
    }

    It 'removes control characters such as the NUL that some installers leave in the registry' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-HtmlText -Value ("Example Player" + [char]0 + [char]7) | Should -BeExactly 'Example Player'
            ConvertTo-HtmlText -Value ("line 1`r`nline`t2") | Should -BeExactly "line 1`r`nline`t2"
        }
    }

    It 'converts every value received from the pipeline' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $texts = @('<a>', 'b') | ConvertTo-HtmlText
            $texts | Should -HaveCount 2
            $texts[0] | Should -Be '&lt;a&gt;'
        }
    }
}
