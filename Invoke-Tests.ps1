#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the checks of the continuous integration on a workstation.

.DESCRIPTION
    One script for both places: the GitHub Actions workflow calls it too, so a
    change that passes here passes in the pipeline.

    Analyze  PSScriptAnalyzer on the module, this script and the tests
    Test     Pester 5 on every *.Tests.ps1 file of the Tests folder
    All      both, analysis first

    Nothing is installed by this script. If a module is missing, the error
    message gives the command to install it for the current user only.

.PARAMETER Task
    Analyze, Test or All (default).

.PARAMETER Verbosity
    Pester output detail: None, Normal, Detailed (default) or Diagnostic.

.EXAMPLE
    .\Invoke-Tests.ps1
    Runs the analysis, then the tests.

.EXAMPLE
    .\Invoke-Tests.ps1 -Task Test -Verbosity Normal
    Runs only the Pester tests, with a short output.
#>
[CmdletBinding()]
param(
    [ValidateSet('Analyze', 'Test', 'All')]
    [string]$Task = 'All',

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Detailed'
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

function Invoke-Analysis {
    if (-not (Get-Module -ListAvailable -Name 'PSScriptAnalyzer')) {
        throw 'PSScriptAnalyzer is not installed. Install it with: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'
    }
    Import-Module -Name 'PSScriptAnalyzer'

    # The tests have their own settings file (one rule excluded, see the comment inside)
    $targets = @(
        @{ Path = Join-Path -Path $repoRoot -ChildPath 'HelpdeskToolkit'; Settings = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1' }
        @{ Path = Join-Path -Path $repoRoot -ChildPath 'Invoke-Tests.ps1'; Settings = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1' }
        @{ Path = Join-Path -Path $repoRoot -ChildPath 'Tests'; Settings = Join-Path -Path $repoRoot -ChildPath 'Tests\PSScriptAnalyzerSettings.psd1' }
    )

    $findings = @(
        foreach ($target in $targets) {
            Invoke-ScriptAnalyzer -Path $target.Path -Settings $target.Settings -Recurse
        }
    )

    if ($findings.Count -gt 0) {
        $findings |
            Format-Table -AutoSize -Property RuleName, Severity, ScriptName, Line, Message |
            Out-String -Width 200 |
            Write-Output
        throw "PSScriptAnalyzer: $($findings.Count) finding(s)."
    }
    Write-Output 'PSScriptAnalyzer: no finding.'
}

function Invoke-Test {
    $pester = Get-Module -ListAvailable -Name 'Pester' |
        Where-Object { $_.Version -ge [version]'5.2.0' } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if (-not $pester) {
        # Windows ships Pester 3.4, which cannot run Pester 5 tests
        throw 'Pester 5.2 or later is required. Install it with: Install-Module -Name Pester -MinimumVersion 5.2.0 -Scope CurrentUser -SkipPublisherCheck -Force'
    }
    Import-Module -Name $pester.Path -Force

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path -Path $repoRoot -ChildPath 'Tests'
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = $Verbosity
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = Join-Path -Path $repoRoot -ChildPath 'testResults.xml'

    $result = Invoke-Pester -Configuration $configuration
    Write-Output ("Pester {0} on PowerShell {1}: {2} passed, {3} failed, {4} skipped." -f
        $pester.Version, $PSVersionTable.PSVersion, $result.PassedCount, $result.FailedCount, $result.SkippedCount)

    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        throw "Pester: $($result.FailedCount) failed test(s)."
    }
}

if ($Task -in 'Analyze', 'All') { Invoke-Analysis }
if ($Task -in 'Test', 'All') { Invoke-Test }
