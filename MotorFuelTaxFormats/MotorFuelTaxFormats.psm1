Set-StrictMode -Version Latest

function Get-RequiredRecordValue {
    param(
        [Parameter(Mandatory)]
        [object] $Record,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "Record is missing required property '$Name'."
    }

    $property.Value
}

function ConvertTo-FloridaField {
    param(
        [AllowEmptyString()]
        [object] $Value
    )

    $text = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    (($text -replace '[^A-Za-z0-9]', ' ') -replace '\s+', ' ').Trim()
}

function ConvertTo-MotorFuelTaxFile {
    <#
    .SYNOPSIS
    Writes motor-fuel tax records in a state's filing-file format.

    .DESCRIPTION
    Accepts the flat, good-data record contract and writes a deterministic UTF-8 file.
    The command performs no data access, network calls, submission, or configuration lookup.

    .EXAMPLE
    Import-Csv ./fl-records.csv | ConvertTo-MotorFuelTaxFile -State FL -FilerId 012345678 -OutputPath ./202607.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FL')]
        [string] $State,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $Record,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{9}$')]
        [string] $FilerId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath
    )

    begin {
        $records = [Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $Record) {
            $records.Add($item)
        }
    }

    end {
        if ($records.Count -eq 0) {
            throw 'At least one record is required.'
        }

        $lastRecord = $records |
            Sort-Object { [datetime](Get-RequiredRecordValue -Record $_ -Name 'shipped') } |
            Select-Object -Last 1
        $period = ([datetime](Get-RequiredRecordValue -Record $lastRecord -Name 'shipped')).ToString(
            'yyyyMM',
            [Globalization.CultureInfo]::InvariantCulture
        )

        [string[]] $lines = foreach ($item in $records) {
            $product = [string](Get-RequiredRecordValue -Record $item -Name 'cmd_code')
            if ($product -notmatch '^[A-Za-z0-9]{3}$') {
                throw "Record product code '$product' must be exactly three alphanumeric characters."
            }

            $deliveryDate = [datetime](Get-RequiredRecordValue -Record $item -Name 'delivered')
            $gallons = [int64](Get-RequiredRecordValue -Record $item -Name 'net') * 10
            $values = @(
                $FilerId
                $period
                (Get-RequiredRecordValue -Record $item -Name 'schedule')
                $product
                '0'
                (Get-RequiredRecordValue -Record $item -Name 'consignor.name')
                (Get-RequiredRecordValue -Record $item -Name 'consignor.tax_id')
                (Get-RequiredRecordValue -Record $item -Name 'supplier.name')
                (Get-RequiredRecordValue -Record $item -Name 'supplier.tax_id')
                'J'
                (Get-RequiredRecordValue -Record $item -Name 'shipper.tcn')
                (Get-RequiredRecordValue -Record $item -Name 'consignee.dep')
                (Get-RequiredRecordValue -Record $item -Name 'consignee.name')
                (Get-RequiredRecordValue -Record $item -Name 'consignee.tax_id')
                $deliveryDate.ToString('yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
                (Get-RequiredRecordValue -Record $item -Name 'bol')
                $gallons
            )

            (($values | ForEach-Object { ConvertTo-FloridaField -Value $_ }) -join ',')
        }

        $contents = ($lines -join "`n") + "`n"
        [IO.File]::WriteAllText(
            [IO.Path]::GetFullPath($OutputPath),
            $contents,
            [Text.UTF8Encoding]::new($false)
        )
    }
}

Export-ModuleMember -Function ConvertTo-MotorFuelTaxFile
