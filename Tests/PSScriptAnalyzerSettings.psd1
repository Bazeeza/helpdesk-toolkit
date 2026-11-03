@{
    # Same rules as the module (see ..\PSScriptAnalyzerSettings.psd1), with one exception
    Severity     = @('Error', 'Warning')

    # PSUseDeclaredVarsMoreThanAssignments: Pester 5 sets variables in
    # BeforeAll and reads them in It blocks. The analyzer looks at one
    # script block at a time, so it reports these variables as unused.
    ExcludeRules = @('PSUseDeclaredVarsMoreThanAssignments')

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.2')
        }
    }
}
