@{
    # Errors and warnings fail the build; information-level hints are only shown
    Severity = @('Error', 'Warning')

    Rules    = @{
        # The module must keep working in Windows PowerShell 5.1, the shell
        # installed on every workstation, and in PowerShell 7
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.2')
        }
    }
}
