# MotorFuelTaxFormats

> Private release candidate. Do not publish this repository or module until the credential-rotation and liability-review gates in issue #1 are closed.

`MotorFuelTaxFormats` converts a flat set of validated motor-fuel records into a state filing file. It deliberately starts after data extraction and stops before filing or submission, so the formatter has no database, network, mail, credential, or premises dependency.

The first pilot supports Florida through the approved `ConvertTo-MotorFuelTaxFile` command. Other states are not implemented yet.

## Install the candidate

```powershell
Import-Module ./MotorFuelTaxFormats/MotorFuelTaxFormats.psd1
```

## Convert Florida records

```powershell
Import-Csv ./fl-records.csv |
    ConvertTo-MotorFuelTaxFile `
        -State FL `
        -FilerId '012345678' `
        -OutputPath ./202607.txt
```

The command writes UTF-8 without a byte-order mark and uses LF line endings on every platform. The filing period is the year and month of the latest `shipped` value, matching the existing Florida formatter.

The Florida record contract is a flat object with these properties:

| Property | Meaning |
| --- | --- |
| `schedule` | Florida schedule code |
| `cmd_code` | Three-character product code, including leading zeroes |
| `consignor.name` | Consignor name |
| `consignor.tax_id` | Consignor tax identifier |
| `supplier.name` | Supplier name |
| `supplier.tax_id` | Supplier tax identifier |
| `shipper.tcn` | Origin terminal control number |
| `consignee.dep` | Florida destination facility number |
| `consignee.name` | Consignee name |
| `consignee.tax_id` | Consignee tax identifier |
| `shipped` | Shipment timestamp |
| `delivered` | Delivery timestamp |
| `bol` | Bill-of-lading number |
| `net` | Net quantity before the Florida tenfold conversion |

Input is expected to have passed the carrier's private validation and exception workflow. This module formats records only. It does not determine taxability, validate a return, submit a filing, or provide tax or legal advice.

## Test

```powershell
Invoke-Pester -Path ./tests -CI
```

All public fixtures are synthetic. Real customer rowsets and filing output are reserved for a separate private byte-comparison check and must never be copied into this repository or CI logs.
