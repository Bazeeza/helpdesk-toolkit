#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

BeforeAll {
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

AfterAll {
    Remove-Module -Name 'HelpdeskToolkit' -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-ReportTable' {
    It 'writes one header cell per property and one row per object' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $rows = @(
                [pscustomobject]@{ Name = 'Example Editor'; Version = '1.2' }
                [pscustomobject]@{ Name = 'Example Viewer'; Version = '3.0' }
            )
            $html = ConvertTo-ReportTable -InputObject $rows -Property Name, Version
            $html | Should -BeLike '<div class="table-wrap"><table class="report">*</table></div>'
            ([regex]::Matches($html, '<th scope="col">')).Count | Should -Be 2
            ([regex]::Matches($html, '<tr>')).Count | Should -Be 3
            $html | Should -Match '<td>Example Viewer</td><td>3.0</td>'
        }
    }

    It 'uses the titles given in Header' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $html = ConvertTo-ReportTable -InputObject ([pscustomobject]@{ FreePercent = 40 }) -Property FreePercent -Header 'Free %'
            $html | Should -Match '<th scope="col">Free %</th>'
        }
    }

    It 'refuses a Header list that does not match the properties' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            { ConvertTo-ReportTable -InputObject ([pscustomobject]@{ A = 1 }) -Property A, B -Header 'Only one' } |
                Should -Throw -ExceptionType ([System.ArgumentException])
        }
    }

    It 'encodes every cell, so a program name cannot inject HTML' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $row = [pscustomobject]@{ Name = '<img src=x onerror=alert(1)>'; Publisher = 'A & B' }
            $html = ConvertTo-ReportTable -InputObject $row -Property Name, Publisher
            $html | Should -Not -Match '<img'
            $html | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
            $html | Should -Match '<td>A &amp; B</td>'
        }
    }

    It 'shows a status property as a badge' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $html = ConvertTo-ReportTable -InputObject ([pscustomobject]@{ Step = 3; Status = 'Fail' }) -Property Step, Status -StatusProperty Status
            $html | Should -Match '<td>3</td><td><span class="badge badge-crit">Fail</span></td>'
        }
    }

    It 'shows a percentage as a bar clamped between 0 and 100' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $rows = @(
                [pscustomobject]@{ FreePercent = 25.3 }
                [pscustomobject]@{ FreePercent = 140 }
                [pscustomobject]@{ FreePercent = $null }
            )
            $html = ConvertTo-ReportTable -InputObject $rows -Property FreePercent -MeterProperty FreePercent
            $html | Should -Match 'style="width:25.3%"></span></span> 25.3 %'
            $html | Should -Match 'style="width:100%"></span></span> 140 %'
            ([regex]::Matches($html, 'class="meter"')).Count | Should -Be 2
        }
    }

    It 'leaves the cell empty for a property the object does not have' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $html = ConvertTo-ReportTable -InputObject ([pscustomobject]@{ A = 'x' }) -Property A, Missing
            $html | Should -Match '<td>x</td><td></td>'
        }
    }

    It 'writes no header row with NoHeader and adds the extra class' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            $html = ConvertTo-ReportTable -InputObject ([pscustomobject]@{ Item = 'Model'; Value = 'Example 15' }) -Property Item, Value -NoHeader -Class 'facts'
            $html | Should -Not -Match '<thead>'
            $html | Should -Match '<table class="report facts">'
        }
    }

    It 'refuses a class name that could break the attribute' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            { ConvertTo-ReportTable -InputObject ([pscustomobject]@{ A = 1 }) -Property A -Class 'x" onclick="y' } | Should -Throw
        }
    }

    It 'writes the empty text instead of a table when there is no object' {
        InModuleScope -ModuleName 'HelpdeskToolkit' {
            ConvertTo-ReportTable -InputObject @() -Property A -EmptyText 'No program found.' | Should -BeExactly '<p class="empty">No program found.</p>'
            ConvertTo-ReportTable -InputObject @($null) -Property A | Should -BeExactly '<p class="empty">Nothing to show.</p>'
        }
    }
}
