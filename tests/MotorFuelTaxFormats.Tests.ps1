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

    It 'contains no data-access, network, mail, or submission commands' {
        Get-Content $modulePath -Raw | Should -Not -Match '(?i)Invoke-Sqlcmd|Invoke-RestMethod|Invoke-WebRequest|New-WebServiceProxy|Send-Mail|Send-Mg|Publish-'
    }
}
