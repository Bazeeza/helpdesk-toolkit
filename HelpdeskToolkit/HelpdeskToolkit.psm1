#Requires -Version 5.1
<#
    Root module of HelpdeskToolkit.

    Every function lives in its own file:
      Public\   one exported command per file, file name = command name
      Private\  helpers used by the public commands, never exported

    Private files are loaded first so that public commands can call them.
#>

Set-StrictMode -Version Latest

$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$publicFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in @($privateFiles + $publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "HelpdeskToolkit: failed to load '$($file.Name)': $($_.Exception.Message)"
    }
}

# Only the commands of the Public folder are exported. The manifest lists
# the same names in FunctionsToExport; a test keeps both lists in sync.
$publicNames = @($publicFiles | ForEach-Object { $_.BaseName })
Export-ModuleMember -Function $publicNames
