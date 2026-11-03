@{
    # Module loaded when the manifest is imported
    RootModule           = 'HelpdeskToolkit.psm1'

    # Semantic versioning: MAJOR.MINOR.PATCH (see CHANGELOG.md)
    ModuleVersion        = '0.1.0'

    GUID                 = '5b72467c-151e-46b5-83b9-469abcf3586b'
    Author               = 'bazeeza'
    Copyright            = '(c) 2026 bazeeza. Released under the MIT License.'
    Description          = 'Read-only help desk diagnostics for Windows workstations: system report, network health, installed software and disk health, with a self-contained HTML report.'

    # Windows PowerShell 5.1 is the shell available on every supported
    # Windows 10 and Windows 11 workstation, so it is the minimum version
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Exports are listed explicitly: PowerShell can then discover the
    # commands without loading the module, and nothing private leaks out.
    # Tests/Module.Tests.ps1 checks that this list matches the Public folder.
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('HelpDesk', 'Diagnostics', 'Troubleshooting', 'Windows', 'SysAdmin')
            LicenseUri = 'https://github.com/Bazeeza/helpdesk-toolkit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Bazeeza/helpdesk-toolkit'
        }
    }
}
