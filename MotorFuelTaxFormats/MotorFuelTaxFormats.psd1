@{
    RootModule = 'MotorFuelTaxFormats.psm1'
    ModuleVersion = '0.1.0'
    GUID = '6a1e2fff-325b-454a-ad42-d0676d2ad1c7'
    Author = 'Roy Ashbrook'
    # License intentionally not asserted yet: it is selected before public release (issue #1).
    # 'All rights reserved' was removed because it contradicts the intended open-source release.
    Copyright = '(c) 2026 Roy Ashbrook'
    Description = 'Pure formatters that turn motor-fuel tax records into state filing files.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @('ConvertTo-MotorFuelTaxFile')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('MotorFuel', 'Tax', 'Alabama', 'Florida', 'Kentucky', 'NorthCarolina', 'SouthCarolina', 'Formatter')
            ProjectUri = 'https://github.com/royashbrook/motor-fuel-tax-formats'
        }
    }
}
