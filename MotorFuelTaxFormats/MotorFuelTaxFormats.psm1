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

function Get-RequiredOptionValue {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Options,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not $Options.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Options[$Name])) {
        throw "StateOptions is missing required value '$Name'."
    }

    [string]$Options[$Name]
}

function Get-FilingPeriodDates {
    param(
        [Parameter(Mandatory)]
        [string] $Period
    )

    $first = [datetime]::ParseExact(
        "${Period}01",
        'yyyyMMdd',
        [Globalization.CultureInfo]::InvariantCulture
    )
    [pscustomobject]@{
        Begin = $first
        End = $first.AddMonths(1).AddSeconds(-1)
    }
}

function ConvertTo-FloridaLines {
    param(
        [Parameter(Mandatory)]
        [object[]] $Records,

        [Parameter(Mandatory)]
        [string] $Period,

        [Parameter(Mandatory)]
        [string] $FilerId
    )

    foreach ($item in $Records) {
        $product = [string](Get-RequiredRecordValue -Record $item -Name 'cmd_code')
        if ($product -notmatch '^[A-Za-z0-9]{3}$') {
            throw "Record product code '$product' must be exactly three alphanumeric characters."
        }

        $deliveryDate = [datetime](Get-RequiredRecordValue -Record $item -Name 'delivered')
        $gallons = [int64](Get-RequiredRecordValue -Record $item -Name 'net') * 10
        $values = @(
            $FilerId
            $Period
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
}

function ConvertTo-AlabamaField {
    param(
        [Parameter(Mandatory)]
        [object] $Value,

        [Parameter(Mandatory)]
        [int] $MaximumLength
    )

    $text = (([string]$Value).Trim() -replace '[^A-Za-z0-9\s\-]', '') -replace '\s\s+', ' '
    if ($text.Length -gt $MaximumLength) {
        $text = $text.Substring(0, $MaximumLength)
    }
    $text
}

function ConvertTo-AlabamaLines {
    param(
        [Parameter(Mandatory)]
        [object[]] $Records,

        [Parameter(Mandatory)]
        [string] $Period,

        [Parameter(Mandatory)]
        [string] $FilerId,

        [Parameter(Mandatory)]
        [datetimeoffset] $GeneratedAt,

        [Parameter(Mandatory)]
        [hashtable] $StateOptions
    )

    $dates = Get-FilingPeriodDates -Period $Period
    $processType = Get-RequiredOptionValue -Options $StateOptions -Name 'ProcessType'
    $etin = Get-RequiredOptionValue -Options $StateOptions -Name 'Etin'
    $agentIdentifier = Get-RequiredOptionValue -Options $StateOptions -Name 'AgentIdentifier'
    $transmissionId = $GeneratedAt.ToString('ALyyyyMMddhhmmss')
    $timestamp = $GeneratedAt.ToString('yyyy-MM-ddTHH:mm:sszzz')
    $periodBegin = $dates.Begin.ToString('yyyy-MM-dd')
    $periodEnd = $dates.End.ToString('yyyy-MM-dd')

    "<Transmission xsi:schemaLocation=`"http://www.irs.gov/efile ./ExtendedCommon/Transmission.xsd`" xmlns=`"http://www.irs.gov/efile`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">
    <TransmissionHeader recordCount=`"1`">
        <Jurisdiction>ALABAMA</Jurisdiction>
        <TransmissionId>$transmissionId</TransmissionId>
        <Timestamp>$timestamp</Timestamp>
        <Transmitter>
            <ETIN>$etin</ETIN>
        </Transmitter>
        <ProcessType>$processType</ProcessType>
        <AgentIdentifier>$agentIdentifier</AgentIdentifier>
    </TransmissionHeader>
    <MotorFuelsFiling>
        <SubmissionId>ALMFET</SubmissionId>
        <MotorFuelsHeader>
            <Jurisdiction>AL</Jurisdiction>
            <Timestamp>$timestamp</Timestamp>
            <TaxPeriodBeginDate>$periodBegin</TaxPeriodBeginDate>
            <TaxPeriodEndDate>$periodEnd</TaxPeriodEndDate>
            <TypeOfFiling>Original</TypeOfFiling>
            <Filer>
                <FEIN>$FilerId</FEIN>
            </Filer>
        </MotorFuelsHeader>
        <CarrierReport reportUOM=`"Gallons`" reportCurrency=`"USD`">
            <ReportID>TRPR</ReportID>"

    foreach ($item in $Records) {
        $shipped = [datetime](Get-RequiredRecordValue -Record $item -Name 'shipped')
        "           <CarrierSchedule>
                <ScheduleCode>$(Get-RequiredRecordValue -Record $item -Name 'schedule')</ScheduleCode>
                <ProductCode>$(Get-RequiredRecordValue -Record $item -Name 'cmd_code')</ProductCode>
                <Mode>J</Mode>
                <DocumentNumber>$(Get-RequiredRecordValue -Record $item -Name 'bol')</DocumentNumber>
                <ReceivedShippedDate>$($shipped.ToString('yyyy-MM-dd'))</ReceivedShippedDate>
                <Origin>
                    <State>$(Get-RequiredRecordValue -Record $item -Name 'shipper.state')</State>
                </Origin>
                <Seller>
                    <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue -Record $item -Name 'supplier.name') 50)</Name>
                    <FEIN>$(Get-RequiredRecordValue -Record $item -Name 'supplier.tax_id')</FEIN>
                </Seller>
                <DeliveredTo>
                    <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue -Record $item -Name 'consignee.name') 50)</Name>
                    <Address>$(ConvertTo-AlabamaField (Get-RequiredRecordValue -Record $item -Name 'consignee.address') 35)</Address>
                </DeliveredTo>
                <Net>$(Get-RequiredRecordValue -Record $item -Name 'net')</Net>
                <DiversionNumber>TRPR1</DiversionNumber>
                <Consignor>
                    <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue -Record $item -Name 'consignor.name') 50)</Name>
                    <FEIN>$(Get-RequiredRecordValue -Record $item -Name 'consignor.tax_id')</FEIN>
                </Consignor>
            </CarrierSchedule>"
    }

    "       </CarrierReport>
    </MotorFuelsFiling>
</Transmission>"
}

function ConvertTo-KentuckyLines {
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [string] $Period,
        [Parameter(Mandatory)] [string] $FilerId,
        [Parameter(Mandatory)] [datetimeoffset] $GeneratedAt,
        [Parameter(Mandatory)] [hashtable] $StateOptions
    )

    $dates = Get-FilingPeriodDates -Period $Period
    $isaSenderId = Get-RequiredOptionValue $StateOptions 'IsaSenderId'
    $isaReceiverId = Get-RequiredOptionValue $StateOptions 'IsaReceiverId'
    $gsSenderId = Get-RequiredOptionValue $StateOptions 'GsSenderId'
    $gsReceiverId = Get-RequiredOptionValue $StateOptions 'GsReceiverId'
    $filerCode = Get-RequiredOptionValue $StateOptions 'FilerCode'
    $taxpayerName = Get-RequiredOptionValue $StateOptions 'TaxpayerName'
    $taxpayerName2 = Get-RequiredOptionValue $StateOptions 'TaxpayerName2'
    $address = Get-RequiredOptionValue $StateOptions 'Address'
    $city = Get-RequiredOptionValue $StateOptions 'City'
    $region = Get-RequiredOptionValue $StateOptions 'Region'
    $postalCode = Get-RequiredOptionValue $StateOptions 'PostalCode'
    $country = Get-RequiredOptionValue $StateOptions 'Country'
    $contactName = Get-RequiredOptionValue $StateOptions 'ContactName'
    $telephone = Get-RequiredOptionValue $StateOptions 'Telephone'
    $fax = Get-RequiredOptionValue $StateOptions 'Fax'
    $email = Get-RequiredOptionValue $StateOptions 'Email'
    $stateLicenseNumber = Get-RequiredOptionValue $StateOptions 'StateLicenseNumber'

    "ISA~03~$($isaSenderId.PadRight(10))~00~          ~32~$($FilerId.PadRight(15))~01~$($isaReceiverId.PadRight(15))~$($GeneratedAt.ToString('yyMMdd'))~$($GeneratedAt.ToString('HHmm'))~|~00403~0$($GeneratedAt.ToString('yyyyMMdd'))~0~P~^\"
    "GS~TF~$gsSenderId~$gsReceiverId~$($GeneratedAt.ToString('yyyyMMdd'))~$($GeneratedAt.ToString('HHmmss'))~$($GeneratedAt.ToString('yyyyMMdd'))~X~004030\"
    "ST~813~$($dates.Begin.ToString('yyyyMMdd'))~1.0\"
    "BTI~T6~050~47~KY~$($GeneratedAt.ToString('yyyyMMdd'))~$filerCode~24~$FilerId~~~~~00\"
    "DTM~194~$($dates.End.ToString('yyyyMMdd'))\"
    "N1~TP~$taxpayerName\"
    "N2~$taxpayerName2\"
    "N3~$address\"
    "N4~$city~$region~$postalCode~$country\"
    "PER~CN~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "PER~EA~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "TFS~T2~CCR~FW~$stateLicenseNumber\"
    [int]$segmentCount = 11
    $keys = [Collections.Generic.HashSet[string]]::new()

    foreach ($item in $Records) {
        $key = @(
            (Get-RequiredRecordValue $item 'shipper.tcn')
            (Get-RequiredRecordValue $item 'consignor.tax_id')
            (Get-RequiredRecordValue $item 'consignee.tax_id')
            (Get-RequiredRecordValue $item 'cmd_code')
        ) -join ','
        if ($keys.Add($key)) {
            "TFS~T3~14~PG~$(Get-RequiredRecordValue $item 'cmd_code')~94~J \"
            "N1~OT~~TC~$(Get-RequiredRecordValue $item 'shipper.tcn')\"
            "N1~SE~$(Get-RequiredRecordValue $item 'supplier.name')~24~$(Get-RequiredRecordValue $item 'supplier.tax_id')\"
            "N1~CI~$(Get-RequiredRecordValue $item 'consignor.name')~24~$(Get-RequiredRecordValue $item 'consignor.tax_id')\"
            "N1~CA~$taxpayerName~24~$FilerId\"
            "N1~BY~$(Get-RequiredRecordValue $item 'consignee.name')~24~$(Get-RequiredRecordValue $item 'consignee.tax_id')\"
            "N1~ST~$(Get-RequiredRecordValue $item 'consignee.state')\"
            "N4~$(Get-RequiredRecordValue $item 'consignee.city')~$(Get-RequiredRecordValue $item 'consignee.state')~$(Get-RequiredRecordValue $item 'consignee.zip')\"
            $segmentCount += 8
        }
        "FGS~D~BM~$(Get-RequiredRecordValue $item 'bol')\"
        "DTM~095~$(([datetime](Get-RequiredRecordValue $item 'shipped')).ToString('yyyyMMdd'))\"
        "TIA~5005~~~$(Get-RequiredRecordValue $item 'net')~GA\"
        $segmentCount += 3
    }

    "SE~$segmentCount~$($dates.Begin.ToString('yyyyMMdd'))\"
    "GE~1~$($GeneratedAt.ToString('yyyyMMdd'))\"
    "IEA~1~0$($GeneratedAt.ToString('yyyyMMdd'))\"
}

function ConvertTo-NorthCarolinaLines {
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [string] $Period,
        [Parameter(Mandatory)] [string] $FilerId,
        [Parameter(Mandatory)] [datetimeoffset] $GeneratedAt,
        [Parameter(Mandatory)] [hashtable] $StateOptions
    )

    $dates = Get-FilingPeriodDates -Period $Period
    $accountId = Get-RequiredOptionValue $StateOptions 'AccountId'
    $filerCode = Get-RequiredOptionValue $StateOptions 'FilerCode'
    $taxpayerName = Get-RequiredOptionValue $StateOptions 'TaxpayerName'
    $carrierName = if ($StateOptions.ContainsKey('CarrierName') -and -not [string]::IsNullOrWhiteSpace([string]$StateOptions['CarrierName'])) {
        [string]$StateOptions['CarrierName']
    }
    else {
        $taxpayerName
    }
    $address = Get-RequiredOptionValue $StateOptions 'Address'
    $city = Get-RequiredOptionValue $StateOptions 'City'
    $region = Get-RequiredOptionValue $StateOptions 'Region'
    $postalCode = Get-RequiredOptionValue $StateOptions 'PostalCode'
    $country = Get-RequiredOptionValue $StateOptions 'Country'
    $contactName = Get-RequiredOptionValue $StateOptions 'ContactName'
    $telephone = Get-RequiredOptionValue $StateOptions 'Telephone'
    $fax = Get-RequiredOptionValue $StateOptions 'Fax'
    $email = Get-RequiredOptionValue $StateOptions 'Email'
    $sum = ($Records | Measure-Object 'net' -Sum).Sum
    [int]$referenceNumber = 1

    "ISA~00~          ~00~          ~ZZ~$($FilerId.PadRight(15))~ZZ~$('NCMOTORFUELS'.PadRight(15))~$($GeneratedAt.ToString('yyMMdd'))~$($GeneratedAt.ToString('HHmm'))~|~00403~0$($GeneratedAt.ToString('yyyyMMdd'))~0~P~^\"
    "GS~TF~$FilerId~NCMOTORFUELS~$($GeneratedAt.ToString('yyyyMMdd'))~$($GeneratedAt.ToString('HHmmss'))~$($GeneratedAt.ToString('yyyyMMdd'))~X~004030\"
    "ST~813~$($dates.Begin.ToString('yyyyMMdd'))~1.0\"
    "BTI~T6~050~47~NCMOTORFUELS~$($GeneratedAt.ToString('yyyyMMdd'))~$filerCode~24~$FilerId~49~$accountId~SV~~00\"
    "DTM~194~$($dates.End.ToString('yyyyMMdd'))\"
    "TIA~5001~~~$sum~GA\"
    "N1~TP~$taxpayerName\"
    "N3~$address\"
    "N4~$city~$region~$postalCode~$country\"
    "PER~CN~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "PER~EA~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "TFS~T2~CCR\"
    "REF~55~$referenceNumber\"
    $referenceNumber++
    "TIA~5004~0~~$sum~GA\"
    [int]$segmentCount = 12
    $keys = [Collections.Generic.HashSet[string]]::new()

    foreach ($item in $Records) {
        $key = @(
            (Get-RequiredRecordValue $item 'shipper.tcn')
            (Get-RequiredRecordValue $item 'consignor.tax_id')
            (Get-RequiredRecordValue $item 'consignee.tax_id')
            (Get-RequiredRecordValue $item 'cmd_code')
        ) -join ','
        if ($keys.Add($key)) {
            "TFS~T3~$(Get-RequiredRecordValue $item 'schedule')~PG~$(Get-RequiredRecordValue $item 'cmd_code')~94~J \"
            "REF~55~$referenceNumber\"
            $referenceNumber++
            "N1~OT~~TC~$(Get-RequiredRecordValue $item 'shipper.tcn')\"
            "N1~SE~$(Get-RequiredRecordValue $item 'supplier.name')~24~$(Get-RequiredRecordValue $item 'supplier.tax_id')\"
            "N1~CI~$(Get-RequiredRecordValue $item 'consignor.name')~24~$(Get-RequiredRecordValue $item 'consignor.tax_id')\"
            "N1~CA~$carrierName~24~$FilerId\"
            "N1~BY~$(Get-RequiredRecordValue $item 'consignee.name')~24~$(Get-RequiredRecordValue $item 'consignee.tax_id')\"
            "N1~ST~$(Get-RequiredRecordValue $item 'consignee.state')\"
            "N4~$(Get-RequiredRecordValue $item 'consignee.city')~$(Get-RequiredRecordValue $item 'consignee.state')\"
            $segmentCount += 9
        }
        "FGS~D~BM~$(Get-RequiredRecordValue $item 'bol')\"
        "REF~55~$referenceNumber\"
        $referenceNumber++
        "DTM~095~$(([datetime](Get-RequiredRecordValue $item 'shipped')).ToString('yyyyMMdd'))\"
        "TIA~5005~~~$(Get-RequiredRecordValue $item 'net')~GA\"
        "TIA~5006~~~$(Get-RequiredRecordValue $item 'gross')~GA\"
        "TIA~5007~~~$(Get-RequiredRecordValue $item 'gross')~GA\"
        $segmentCount += 6
    }

    $segmentCount++
    "SE~$segmentCount~$($dates.Begin.ToString('yyyyMMdd'))\"
    "GE~1~$($GeneratedAt.ToString('yyyyMMdd'))\"
    "IEA~1~0$($GeneratedAt.ToString('yyyyMMdd'))\"
}

function ConvertTo-SouthCarolinaLines {
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [string] $Period,
        [Parameter(Mandatory)] [string] $FilerId,
        [Parameter(Mandatory)] [datetimeoffset] $GeneratedAt,
        [Parameter(Mandatory)] [hashtable] $StateOptions
    )

    $dates = Get-FilingPeriodDates -Period $Period
    $softwareId = Get-RequiredOptionValue $StateOptions 'SoftwareId'
    $softwareVersion = Get-RequiredOptionValue $StateOptions 'SoftwareVersion'
    $typeOfFiling = Get-RequiredOptionValue $StateOptions 'TypeOfFiling'
    $stateLicenseNumber = Get-RequiredOptionValue $StateOptions 'StateLicenseNumber'
    $filerName = Get-RequiredOptionValue $StateOptions 'FilerName'
    $timestamp = $GeneratedAt.ToString('yyyy-MM-ddTHH:mm:sszzz')
    $sum = ($Records | Measure-Object 'gross' -Sum).Sum

    '<?xml version="1.0" encoding="UTF-8"?>'
    '<MotorFuelsFiling xmlns="http://www.irs.gov/efile" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    "    <SubmissionId>$softwareId$Period</SubmissionId>"
    '    <MotorFuelsHeader>'
    '        <Jurisdiction>SC</Jurisdiction>'
    "        <Timestamp>$timestamp</Timestamp>"
    "        <TaxPeriodBeginDate>$($dates.Begin.ToString('yyyy-MM-dd'))</TaxPeriodBeginDate>"
    "        <TaxPeriodEndDate>$($dates.End.ToString('yyyy-MM-dd'))</TaxPeriodEndDate>"
    "        <SoftwareId>$softwareId</SoftwareId>"
    "        <SoftwareVersion>$softwareVersion</SoftwareVersion>"
    if ($typeOfFiling -eq 'Amended') {
        '        <AmendedReturnIndicator>X</AmendedReturnIndicator>'
    }
    '        <Filer>'
    "            <FEIN>$FilerId</FEIN>"
    "            <StateLicenseNumber>$stateLicenseNumber</StateLicenseNumber>"
    "            <Name>$(ConvertTo-AlabamaField $filerName 50)</Name>"
    '        </Filer>'
    '    </MotorFuelsHeader>'
    '    <CarrierReport reportUOM="Gallons" reportCurrency="USD">'

    foreach ($item in $Records) {
        '        <CarrierSchedule>'
        "            <ScheduleCode>$(Get-RequiredRecordValue $item 'schedule')</ScheduleCode>"
        "            <ProductCode>$(Get-RequiredRecordValue $item 'cmd_code')</ProductCode>"
        '            <Mode>J</Mode>'
        "            <DocumentNumber>$(Get-RequiredRecordValue $item 'bol')</DocumentNumber>"
        "            <ReceivedShippedDate>$(([datetime](Get-RequiredRecordValue $item 'shipped')).ToString('yyyy-MM-dd'))</ReceivedShippedDate>"
        $terminalCode = [string](Get-RequiredRecordValue $item 'shipper.tcn')
        if ($terminalCode -match '^T[0-9]{2}[A-Za-z]{2}[0-9]{4}$') {
            "            <Origin><TerminalCode>$($terminalCode.ToUpper())</TerminalCode></Origin>"
        }
        else {
            "            <Origin><State>$(Get-RequiredRecordValue $item 'shipper.state')</State></Origin>"
        }
        "            <Destination><State>$(Get-RequiredRecordValue $item 'consignee.state')</State></Destination>"
        '            <Seller>'
        "                <FEIN>$(Get-RequiredRecordValue $item 'supplier.tax_id')</FEIN>"
        "                <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue $item 'supplier.name') 50)</Name>"
        '            </Seller>'
        '            <DeliveredTo>'
        "                <FEIN>$(Get-RequiredRecordValue $item 'consignee.tax_id')</FEIN>"
        "                <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue $item 'consignee.name') 50)</Name>"
        '            </DeliveredTo>'
        "            <Net>$(Get-RequiredRecordValue $item 'net')</Net>"
        "            <Gross>$(Get-RequiredRecordValue $item 'gross')</Gross>"
        '            <Consignor>'
        "                <FEIN>$(Get-RequiredRecordValue $item 'consignor.tax_id')</FEIN>"
        "                <Name>$(ConvertTo-AlabamaField (Get-RequiredRecordValue $item 'consignor.name') 50)</Name>"
        '            </Consignor>'
        '        </CarrierSchedule>'
    }

    "        <TotalQuantityTransported>$sum</TotalQuantityTransported>"
    '    </CarrierReport>'
    '</MotorFuelsFiling>'
}

function ConvertTo-VirginiaLines {
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [string] $Period,
        [Parameter(Mandatory)] [string] $FilerId,
        [Parameter(Mandatory)] [datetimeoffset] $GeneratedAt,
        [Parameter(Mandatory)] [hashtable] $StateOptions
    )

    $dates = Get-FilingPeriodDates -Period $Period
    $isaReceiverId = Get-RequiredOptionValue $StateOptions 'IsaReceiverId'
    $gsSenderId = Get-RequiredOptionValue $StateOptions 'GsSenderId'
    $gsReceiverId = Get-RequiredOptionValue $StateOptions 'GsReceiverId'
    $filerCode = Get-RequiredOptionValue $StateOptions 'FilerCode'
    $accountId = Get-RequiredOptionValue $StateOptions 'AccountId'
    $taxpayerName = Get-RequiredOptionValue $StateOptions 'TaxpayerName'
    $contactName = Get-RequiredOptionValue $StateOptions 'ContactName'
    $telephone = Get-RequiredOptionValue $StateOptions 'Telephone'
    $fax = Get-RequiredOptionValue $StateOptions 'Fax'
    $email = Get-RequiredOptionValue $StateOptions 'Email'

    "ISA~00~          ~00~          ~ZZ~$($FilerId.PadRight(15))~ZZ~$($isaReceiverId.PadRight(15))~$($GeneratedAt.ToString('yyMMdd'))~$($GeneratedAt.ToString('HHmm'))~|~00403~0$($GeneratedAt.ToString('yyyyMMdd'))~0~P~^\"
    "GS~TF~$gsSenderId~$gsReceiverId~$($GeneratedAt.ToString('yyyyMMdd'))~$($GeneratedAt.ToString('HHmmss'))~$($GeneratedAt.ToString('yyyyMMdd'))~X~004030\"
    "ST~813~$($dates.Begin.ToString('yyyyMMdd'))~9.0\"
    "BTI~T6~TR~47~VA~$($GeneratedAt.ToString('yyyyMMdd'))~$filerCode~24~$FilerId~49~$accountId~~~00\"
    "DTM~194~$($dates.End.ToString('yyyyMMdd'))\"
    "N1~TP~$taxpayerName\"
    "PER~CN~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "PER~EA~$contactName~TE~$telephone~FX~$fax~EM~$email\"
    "TFS~T2~CCR\"
    [int]$segmentCount = 8
    $keys = [Collections.Generic.HashSet[string]]::new()

    foreach ($item in $Records) {
        $key = @(
            (Get-RequiredRecordValue $item 'shipper.tcn')
            (Get-RequiredRecordValue $item 'consignor.tax_id')
            (Get-RequiredRecordValue $item 'consignee.tax_id')
            (Get-RequiredRecordValue $item 'cmd_code')
        ) -join ','
        if ($keys.Add($key)) {
            "TFS~T3~$(Get-RequiredRecordValue $item 'schedule')~PG~$(Get-RequiredRecordValue $item 'cmd_code')~94~J \"
            "N1~OT~~TC~$(Get-RequiredRecordValue $item 'shipper.tcn')\"
            "N1~CI~$(Get-RequiredRecordValue $item 'consignor.name')~24~$(Get-RequiredRecordValue $item 'consignor.tax_id')\"
            "N1~BY~$(Get-RequiredRecordValue $item 'consignee.name')~24~$(Get-RequiredRecordValue $item 'consignee.tax_id')\"
            "N1~ST~$(Get-RequiredRecordValue $item 'consignee.state')\"
            "N4~$(Get-RequiredRecordValue $item 'consignee.city')~$(Get-RequiredRecordValue $item 'consignee.state')~$(Get-RequiredRecordValue $item 'consignee.zip')\"
            $segmentCount += 6
        }
        "FGS~D~BM~$(Get-RequiredRecordValue $item 'bol')\"
        "DTM~095~$(([datetime](Get-RequiredRecordValue $item 'shipped')).ToString('yyyyMMdd'))\"
        "TIA~5005~~~$(Get-RequiredRecordValue $item 'net')~GA\"
        "TIA~5006~~~$(Get-RequiredRecordValue $item 'gross')~GA\"
        $segmentCount += 4
    }

    "SE~$segmentCount~$($dates.Begin.ToString('yyyyMMdd'))\"
    "GE~1~$($GeneratedAt.ToString('yyyyMMdd'))\"
    "IEA~1~0$($GeneratedAt.ToString('yyyyMMdd'))\"
}

function ConvertTo-TennesseeWorkbook {
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [string] $TemplatePath,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    Import-Module ImportExcel -MinimumVersion 7.8.10 -ErrorAction Stop
    Copy-Item -LiteralPath $TemplatePath -Destination $OutputPath -Force
    $package = Open-ExcelPackage -Path $OutputPath
    try {
        $cells = $package.Workbook.Worksheets[1].Cells
        [int]$row = 4
        foreach ($item in $Records) {
            $values = @(
                (Get-RequiredRecordValue $item 'schedule')
                (Get-RequiredRecordValue $item 'cmd_code')
                (Get-RequiredRecordValue $item 'shipper.tcn')
                (Get-RequiredRecordValue $item 'consignor.name')
                (Get-RequiredRecordValue $item 'consignor.tax_id')
                (Get-RequiredRecordValue $item 'supplier.name')
                (Get-RequiredRecordValue $item 'supplier.tax_id')
                'J - Truck'
                (Get-RequiredRecordValue $item 'shipper.state')
                (Get-RequiredRecordValue $item 'consignee.name')
                (Get-RequiredRecordValue $item 'consignee.state')
                (Get-RequiredRecordValue $item 'consignee.tax_id')
                (Get-RequiredRecordValue $item 'delivered')
                (Get-RequiredRecordValue $item 'bol')
                (Get-RequiredRecordValue $item 'net')
                (Get-RequiredRecordValue $item 'gross')
            )
            for ($column = 1; $column -le $values.Count; $column++) {
                $cells[$row, $column].Value = $values[$column - 1]
            }
            $row++
        }
    }
    finally {
        Close-ExcelPackage -ExcelPackage $package
    }
}

function ConvertTo-MotorFuelTaxFile {
    <#
    .SYNOPSIS
    Writes motor-fuel tax records in a state's filing-file format.

    .DESCRIPTION
    Accepts the flat, good-data record contract and writes a deterministic UTF-8 file.
    The command performs no data access, network calls, submission, or configuration lookup.

    .EXAMPLE
    Import-Csv ./fl-records.csv | ConvertTo-MotorFuelTaxFile -State FL -Period '202607' -FilerId '012345678' -OutputPath ./202607.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AL', 'FL', 'KY', 'NC', 'SC', 'TN', 'VA')]
        [string] $State,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{6}$')]
        [string] $Period,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]] $Record,

        [ValidatePattern('^\d{9}$')]
        [string] $FilerId,

        [datetimeoffset] $GeneratedAt,

        [hashtable] $StateOptions = @{},

        [string] $TemplatePath,

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

        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

        if ($State -eq 'TN') {
            if (-not $PSBoundParameters.ContainsKey('TemplatePath')) {
                throw 'State TN requires TemplatePath.'
            }
            ConvertTo-TennesseeWorkbook -Records $records -TemplatePath $TemplatePath -OutputPath $resolvedOutputPath
            return
        }

        if (-not $PSBoundParameters.ContainsKey('FilerId')) {
            throw "State $State requires FilerId."
        }

        [string[]] $lines = switch ($State) {
            'AL' {
                if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
                    throw "State AL requires GeneratedAt."
                }
                ConvertTo-AlabamaLines -Records $records -Period $Period -FilerId $FilerId -GeneratedAt $GeneratedAt -StateOptions $StateOptions
            }
            'FL' {
                ConvertTo-FloridaLines -Records $records -Period $Period -FilerId $FilerId
            }
            'KY' {
                if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
                    throw "State KY requires GeneratedAt."
                }
                ConvertTo-KentuckyLines -Records $records -Period $Period -FilerId $FilerId -GeneratedAt $GeneratedAt -StateOptions $StateOptions
            }
            'NC' {
                if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
                    throw "State NC requires GeneratedAt."
                }
                ConvertTo-NorthCarolinaLines -Records $records -Period $Period -FilerId $FilerId -GeneratedAt $GeneratedAt -StateOptions $StateOptions
            }
            'SC' {
                if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
                    throw "State SC requires GeneratedAt."
                }
                ConvertTo-SouthCarolinaLines -Records $records -Period $Period -FilerId $FilerId -GeneratedAt $GeneratedAt -StateOptions $StateOptions
            }
            'VA' {
                if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
                    throw "State VA requires GeneratedAt."
                }
                ConvertTo-VirginiaLines -Records $records -Period $Period -FilerId $FilerId -GeneratedAt $GeneratedAt -StateOptions $StateOptions
            }
        }

        $contents = ($lines -join "`n") + "`n"
        [IO.File]::WriteAllText(
            $resolvedOutputPath,
            $contents,
            [Text.UTF8Encoding]::new($false)
        )
    }
}

Export-ModuleMember -Function ConvertTo-MotorFuelTaxFile
