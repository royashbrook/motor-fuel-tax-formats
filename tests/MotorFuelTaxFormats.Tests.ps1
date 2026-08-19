BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $manifestPath = Join-Path $repoRoot 'MotorFuelTaxFormats/MotorFuelTaxFormats.psd1'
    $modulePath = Join-Path $repoRoot 'MotorFuelTaxFormats/MotorFuelTaxFormats.psm1'
    $recordsPath = Join-Path $PSScriptRoot 'fixtures/fl-records.csv'
    $expectedPath = Join-Path $PSScriptRoot 'fixtures/fl-expected.txt'
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

    It 'contains no data-access, network, mail, or submission commands' {
        Get-Content $modulePath -Raw | Should -Not -Match '(?i)Invoke-Sqlcmd|Invoke-RestMethod|Invoke-WebRequest|Send-Mail|Send-Mg|Publish-'
    }
}
