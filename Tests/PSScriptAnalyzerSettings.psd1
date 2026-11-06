@{
    # Same rules as the module (see ..\PSScriptAnalyzerSettings.psd1), with
    # three exceptions that only make sense for test files
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Pester 5 sets variables in BeforeAll and reads them in It blocks.
        # The analyzer looks at one script block at a time, so it reports
        # these variables as unused.
        'PSUseDeclaredVarsMoreThanAssignments'

        # The tests pass fictitious computer names (PC-EXAMPLE02, PC-OFFLINE)
        # and the loopback address on purpose: they are test data, not the
        # name of a real computer that could leak.
        'PSAvoidUsingComputerNameHardcoded'

        # New-FakeComputer, New-FakeNetwork and the other fixtures only build
        # objects in memory. They change nothing on the computer, so
        # -WhatIf and -Confirm would have nothing to protect.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.2')
        }
    }
}
