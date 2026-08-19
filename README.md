# MotorFuelTaxFormats

> Private release candidate. Do not publish this repository or module until the remaining gates in issue #1 are closed.

Turn a flat set of motor-fuel records into a state tax filing file. That is the whole job. This module starts after your data is extracted and stops before anything is filed, so it has no database, no network, no mail, no credentials, and no assumptions about where it runs.

## Why it is shaped this way

Most carrier tax pipelines do three things in one place: pull the data, convert it to the state's format, and file it. Those three steps almost always run on-prem, next to the database, because that is where the pull has to happen.

Only the pull actually needs to be there. The conversion is pure: records in, filing file out. So this module draws the line at that seam. You pull your data wherever it lives, on whatever system you already have, and hand this module the flat record set. From there the conversion (and later, filing) can run anywhere: a GitHub Action, a small server, a scheduled job off-prem. The part that does not need your database no longer has to live next to it.

That split is the point. The state formats are the useful cargo; the decoupling is the pattern worth copying.

## What it does not do

This is a formatter, and only a formatter. It does not:

- decide whether a shipment is taxable,
- validate that a return is correct or complete,
- submit or transmit anything to any state,
- or give tax or legal advice.

It writes the file in the state's shape. Confirming that the file is right for your filing, against the current published state specification, is on you. See [License and warranty](#license-and-warranty).

## Install the candidate

```powershell
Import-Module ./MotorFuelTaxFormats/MotorFuelTaxFormats.psd1
```

## Convert Florida records

Florida and Alabama are supported through the `ConvertTo-MotorFuelTaxFile` command.

```powershell
Import-Csv ./fl-records.csv |
    ConvertTo-MotorFuelTaxFile `
        -State FL `
        -Period '202607' `
        -FilerId '012345678' `
        -OutputPath ./202607.txt
```

The command writes UTF-8 with no byte-order mark and LF line endings on every platform. `-Period` is the filing period in `yyyyMM` form. It is explicit because the filing period belongs to the return, not to any one shipment timestamp.

Everything that identifies you (your filer id, and anything customer-specific in the records) is passed in. Nothing about any particular company is baked into this module.

## The Florida record contract

A flat object with these properties. This is the boundary: whatever system you pull from, produce this shape and the formatter takes it from there.

| Property | Meaning |
| --- | --- |
| `schedule` | Florida schedule code |
| `cmd_code` | Three-character product code, leading zeroes kept |
| `consignor.name` | Consignor name |
| `consignor.tax_id` | Consignor tax identifier |
| `supplier.name` | Supplier name |
| `supplier.tax_id` | Supplier tax identifier |
| `shipper.tcn` | Origin terminal control number |
| `consignee.dep` | Florida destination facility number |
| `consignee.name` | Consignee name |
| `consignee.tax_id` | Consignee tax identifier |
| `shipped` | Shipment timestamp; never used to infer the filing period |
| `delivered` | Delivery timestamp |
| `bol` | Bill-of-lading number |
| `net` | Net quantity, before Florida's tenfold conversion |

Records are expected to have already passed your own validation and exception handling. This module formats what you give it.

## Alabama

Alabama writes XML and requires an explicit generation timestamp plus the non-secret transmitter values that used to live beside the private submission code:

```powershell
Import-Csv ./al-records.csv |
    ConvertTo-MotorFuelTaxFile `
        -State AL `
        -Period '202607' `
        -FilerId '012345678' `
        -GeneratedAt '2026-08-19T10:30:45-04:00' `
        -StateOptions @{
            ProcessType = 'T'
            Etin = '12345'
            AgentIdentifier = 'XMLTRN'
        } `
        -OutputPath ./202607.xml
```

Only the XML formatter is present. SOAP submission, acknowledgements, filing-window controls, credentials, and email remain outside this module.

## Kentucky

Kentucky writes EDI. Supply the envelope, taxpayer, contact, and license values through `StateOptions`; none are built into the module.

```powershell
$options = Get-Content ./ky-filing.json -Raw | ConvertFrom-Json -AsHashtable
Import-Csv ./ky-records.csv |
    ConvertTo-MotorFuelTaxFile `
        -State KY -Period '202607' -FilerId '012345678' `
        -GeneratedAt '2026-08-19T10:30:45-04:00' `
        -StateOptions $options -OutputPath ./202607.edi
```

Required option keys: `IsaSenderId`, `IsaReceiverId`, `GsSenderId`, `GsReceiverId`, `FilerCode`, `TaxpayerName`, `TaxpayerName2`, `Address`, `City`, `Region`, `PostalCode`, `Country`, `ContactName`, `Telephone`, `Fax`, `Email`, and `StateLicenseNumber`.

## Test

```powershell
Invoke-Pester -Path ./tests -CI
```

Every fixture in this repository is synthetic. Real customer records and real filing output are never copied here or into CI logs; equivalence against a live filing is checked separately, on the private side, and stays there.

## License and warranty

This is a reference implementation of the file formats, published so other carriers do not have to reverse-engineer them. It is provided as-is, with no warranty, and it is not tax or legal advice. Always verify the output against the current published specification for the state you are filing in before you rely on it.

License: to be selected before public release (see issue #1).
