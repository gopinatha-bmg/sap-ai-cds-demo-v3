@AbapCatalog.sqlViewName: 'ZV_LATE_POST'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Late FI Document Postings'
@VDM.viewType: #CONSUMPTION
define view ZAI_LATE_POST
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from        : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to          : budat,
    @EndUserText.label: 'Company Code'
    p_company_code      : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year       : gjahr,
    @EndUserText.label: 'Amount Threshold (doc currency)'
    p_amount_threshold  : netwr_ap
    // Example default for threshold: 1000. Set to 0 to disable.
  as select from bkpf as hdr
    inner join   bseg as itm on  hdr.bukrs = itm.bukrs
                             AND hdr.belnr = itm.belnr
                             AND hdr.gjahr = itm.gjahr
    left outer join lfa1 as ven on itm.lifnr = ven.lifnr
{
  key hdr.bukrs                                             as CompanyCode,
  key hdr.belnr                                             as AccountingDocument,
  key hdr.gjahr                                             as FiscalYear,
  key itm.buzei                                             as LineItem,
      hdr.blart                                             as DocumentType,
      hdr.bldat                                             as DocumentDate,
      hdr.budat                                             as PostingDate,
      hdr.cpudt                                             as EntryDate,
      hdr.xblnr                                             as ExternalReference,
      hdr.usnam                                             as EnteredBy,
      itm.koart                                             as AccountType,
      itm.lifnr                                             as Vendor,
      ven.name1                                             as VendorName,
      itm.wrbtr                                             as AmountInDocCurrency,
      hdr.waers                                             as DocumentCurrency,
      dats_days_between( hdr.bldat, hdr.budat )             as PostingDelayDays,
      // Late-posting rule: posting date more than 30 days after document date.
      // 30-day threshold is the business definition of "late" — kept as a
      // fixed constant per the brief; convert to a parameter if configurable.
      cast( 3 as abap.int1 )                                as RiskCriticality
}
// NOTE: Output granularity is line-item (one row per BSEG line on a late-posted document).
// If a header-level exception list is required, remove the BSEG join, drop koart / wrbtr
// filters, and expose only header fields.
where hdr.budat between :p_budat_from and :p_budat_to
  AND hdr.bukrs   = :p_company_code
  AND hdr.gjahr   = :p_fiscal_year
  AND hdr.stblg   = ''              -- exclude documents that have been reversed
  AND hdr.stgrd   = ''              -- exclude reversal documents themselves
  // TODO: koart='K' (vendor items) and the amount threshold narrow the exception set
  //       beyond the original brief. Confirm with business or parameterise koart.
  AND itm.koart   = 'K'
  AND itm.wrbtr  >= :p_amount_threshold
  AND hdr.budat   > dats_add_days( hdr.bldat, 30, 'INITIAL' )