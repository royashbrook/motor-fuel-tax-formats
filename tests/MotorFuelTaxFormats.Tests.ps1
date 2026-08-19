BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $manifestPath = Join-Path $repoRoot 'MotorFuelTaxFormats/MotorFuelTaxFormats.psd1'
    $modulePath = Join-Path $repoRoot 'MotorFuelTaxFormats/MotorFuelTaxFormats.psm1'
    $recordsPath = Join-Path $PSScriptRoot 'fixtures/fl-records.csv'
    $expectedPath = Join-Path $PSScriptRoot 'fixtures/fl-expected.txt'
    $alRecordsPath = Join-Path $PSScriptRoot 'fixtures/al-records.csv'
    $alExpectedPath = Join-Path $PSScriptRoot 'fixtures/al-expected.xml'
    $kyRecordsPath = Join-Path $PSScriptRoot 'fixtures/ky-records.csv'
    $kyExpectedPath = Join-Path $PSScriptRoot 'fixtures/ky-expected.edi'
    $ncRecordsPath = Join-Path $PSScriptRoot 'fixtures/nc-records.csv'
    $ncExpectedPath = Join-Path $PSScriptRoot 'fixtures/nc-expected.edi'
    $scRecordsPath = Join-Path $PSScriptRoot 'fixtures/sc-records.csv'
    $scExpectedPath = Join-Path $PSScriptRoot 'fixtures/sc-expected.xml'
    $vaRecordsPath = Join-Path $PSScriptRoot 'fixtures/va-records.csv'
    $vaExpectedPath = Join-Path $PSScriptRoot 'fixtures/va-expected.edi'
    $tnRecordsPath = Join-Path $PSScriptRoot 'fixtures/tn-records.csv'
    $tnExpectedPath = Join-Path $PSScriptRoot 'fixtures/tn-expected.csv'
    Import-Module $manifestPath -Force
}

Describe 'MotorFuelTaxFormats module' {
    It 'has a valid manifest with one public command' {
        $manifest = Test-ModuleManifest $manifestPath

        $manifest.ExportedFunctions.Keys | Should -Be @('ConvertTo-MotorFuelTaxFile')
    }

    It 'uses the explicit period and writes the Florida golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'fl-output.txt'

        Import-Csv $recordsPath |
            ConvertTo-MotorFuelTaxFile -State FL -Period '202607' -FilerId '012345678' -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($expectedPath)))
    }

    It 'rejects a product code whose leading zero was lost' {
        $record = Import-Csv $recordsPath
        $record.cmd_code = '65'
        $outputPath = Join-Path $TestDrive 'invalid.txt'

        {
            $record | ConvertTo-MotorFuelTaxFile -State FL -Period '202607' -FilerId '012345678' -OutputPath $outputPath
        } | Should -Throw '*must be exactly three*'
    }

    It 'writes the synthetic Alabama golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'al-output.xml'

        Import-Csv $alRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State AL `
                -Period '202607' `
                -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions @{ ProcessType = 'T'; Etin = '12345'; AgentIdentifier = 'XMLTRN' } `
                -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($alExpectedPath)))
    }

    It 'writes the synthetic Kentucky golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'ky-output.edi'
        $options = @{
            IsaSenderId = '0123456780'; IsaReceiverId = '123456789T'
            GsSenderId = 'KY123456'; GsReceiverId = '123456789T'; FilerCode = 'TEST'
            TaxpayerName = 'Synthetic Carrier'; TaxpayerName2 = 'Synthetic Transport'
            Address = '100 Test St'; City = 'Frankfort'; Region = 'KY'; PostalCode = '40601'; Country = 'US'
            ContactName = 'Test Contact'; Telephone = '5025550100'; Fax = '5025550101'
            Email = 'test@example.invalid'; StateLicenseNumber = 'TR12345'
        }

        Import-Csv $kyRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State KY -Period '202607' -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions $options -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($kyExpectedPath)))
    }

    It 'writes the synthetic North Carolina golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'nc-output.edi'
        $options = @{
            AccountId = '01234567801'; FilerCode = 'TEST'; TaxpayerName = 'Synthetic Carrier'
            Address = '100 Test St'; City = 'Raleigh'; Region = 'NC'; PostalCode = '27601'; Country = 'US'
            ContactName = 'Test Contact'; Telephone = '9195550100'; Fax = '9195550101'
            Email = 'test@example.invalid'
        }

        Import-Csv $ncRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State NC -Period '202607' -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions $options -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($ncExpectedPath)))
    }

    It 'allows North Carolina carrier and taxpayer names to differ' {
        $outputPath = Join-Path $TestDrive 'nc-distinct-carrier.edi'
        $options = @{
            AccountId = '01234567801'; FilerCode = 'TEST'; TaxpayerName = 'Synthetic Carrier, Inc.'
            CarrierName = 'Synthetic Carrier, INC.'
            Address = '100 Test St'; City = 'Raleigh'; Region = 'NC'; PostalCode = '27601'; Country = 'US'
            ContactName = 'Test Contact'; Telephone = '9195550100'; Fax = '9195550101'
            Email = 'test@example.invalid'
        }

        Import-Csv $ncRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State NC -Period '202607' -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions $options -OutputPath $outputPath

        $lines = Get-Content $outputPath
        ($lines -ccontains 'N1~TP~Synthetic Carrier, Inc.\') | Should -BeTrue
        ($lines -ccontains 'N1~CA~Synthetic Carrier, INC.~24~012345678\') | Should -BeTrue
    }

    It 'resolves a relative output path against the PowerShell current location' {
        $originalLocation = Get-Location
        try {
            Set-Location $TestDrive
            Import-Csv $recordsPath |
                ConvertTo-MotorFuelTaxFile `
                    -State FL -Period '202607' -FilerId '012345678' `
                    -OutputPath ./relative-output.txt

            Test-Path (Join-Path $TestDrive 'relative-output.txt') | Should -BeTrue
        }
        finally {
            Set-Location $originalLocation
        }
    }

    It 'writes the synthetic South Carolina golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'sc-output.xml'
        $options = @{
            SoftwareId = 'TESTSOFT'; SoftwareVersion = '1.0'; TypeOfFiling = 'Original'
            StateLicenseNumber = 'SC12345'; FilerName = 'Synthetic Carrier'
        }

        Import-Csv $scRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State SC -Period '202607' -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions $options -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($scExpectedPath)))
    }

    It 'writes the synthetic Virginia golden file byte for byte' {
        $outputPath = Join-Path $TestDrive 'va-output.edi'
        $options = @{
            IsaReceiverId = 'ETRACS'; GsSenderId = 'VA062013'; GsReceiverId = 'ETRACS'
            FilerCode = 'TEST'; AccountId = '01234567801'; TaxpayerName = 'Synthetic Carrier'
            ContactName = 'Test Contact'; Telephone = '8045550100'; Fax = '8045550101'
            Email = 'test@example.invalid'
        }

        Import-Csv $vaRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State VA -Period '202607' -FilerId '012345678' `
                -GeneratedAt '2026-08-19T10:30:45-04:00' `
                -StateOptions $options -OutputPath $outputPath

        [Convert]::ToHexString([IO.File]::ReadAllBytes($outputPath)) |
            Should -BeExactly ([Convert]::ToHexString([IO.File]::ReadAllBytes($vaExpectedPath)))
    }

    It 'writes Tennessee rows into a caller-supplied synthetic template' {
        Import-Module ImportExcel -MinimumVersion 7.8.10
        $templatePath = Join-Path $TestDrive 'tn-template.xlsx'
        $outputPath = Join-Path $TestDrive 'tn-output.xlsx'
        $package = Open-ExcelPackage -Path $templatePath -Create
        $worksheet = Add-Worksheet -ExcelPackage $package -WorksheetName 'Synthetic Schedule'
        $worksheet.Cells[1, 1].Value = 'Synthetic template marker'
        Close-ExcelPackage -ExcelPackage $package

        Import-Csv $tnRecordsPath |
            ConvertTo-MotorFuelTaxFile `
                -State TN -Period '202607' `
                -TemplatePath $templatePath -OutputPath $outputPath

        $output = Open-ExcelPackage -Path $outputPath
        try {
            $output.Workbook.Worksheets[1].Cells[1, 1].Value | Should -BeExactly 'Synthetic template marker'
            $actual = 1..16 | ForEach-Object {
                [Convert]::ToString($output.Workbook.Worksheets[1].Cells[4, $_].Value, [Globalization.CultureInfo]::InvariantCulture)
            }
            ($actual -join ',') | Should -BeExactly (Get-Content $tnExpectedPath -Raw).TrimEnd()
        }
        finally {
            Close-ExcelPackage -ExcelPackage $output -NoSave
        }
    }

    It 'contains no data-access, network, mail, or submission commands' {
        Get-Content $modulePath -Raw | Should -Not -Match '(?i)Invoke-Sqlcmd|Invoke-RestMethod|Invoke-WebRequest|New-WebServiceProxy|Send-Mail|Send-Mg|Publish-'
    }
}
