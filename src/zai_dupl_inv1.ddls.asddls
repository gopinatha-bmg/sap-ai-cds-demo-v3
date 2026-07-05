@AbapCatalog.sqlViewName: 'ZV_DUPL_INV1'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Duplicate Invoice Detection'
@VDM.viewType: #CONSUMPTION

define view ZAI_DUPL_INV1
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from        : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to          : budat,
    @EndUserText.label: 'Company Code'
    p_company_code      : bukrs,
    @EndUserText.label: 'Minimum Gross Amount'
    p_amount_threshold  : netwr_ap,
    @EndUserText.label: 'Amount Tolerance Percent'
    p_tolerance_percent : abap.dec(5,2)

  // NOTE: FI-scope only (BKPF/BSEG). MM logistics invoices (RBKP/RSEG) should be
  //       covered by a sibling view or joined via AWKEY if required by policy.
  // TODO: configure credit-memo document types via mapping table
  //       (currently only 'KG' excluded).
  // TODO: BSTAT parked/held check must be on BKPF, not BSEG (fixed below).
  as select from bkpf as a
    inner join   bseg as b  on  b.bukrs = a.bukrs
                            and b.belnr = a.belnr
                            and b.gjahr = a.gjahr
                            and b.koart = 'K'
    inner join   bkpf as a2 on  a2.bukrs = a.bukrs
                            and a2.xblnr = a.xblnr
    inner join   bseg as b2 on  b2.bukrs = a2.bukrs
                            and b2.belnr = a2.belnr
                            and b2.gjahr = a2.gjahr
                            and b2.koart = 'K'
                            and b2.lifnr = b.lifnr
                            and b2.waers = b.waers

{
  key a.bukrs                                                as CompanyCode,
  key a.belnr                                                as AccountingDocument,
  key a.gjahr                                                as FiscalYear,
      a.xblnr                                                as ExternalInvoiceNumber,
      a.blart                                                as DocumentType,
      a.bldat                                                as InvoiceDate,
      a.budat                                                as PostingDate,
      b.lifnr                                                as VendorId,
      b.wrbtr                                                as GrossAmount,
      b.waers                                                as Currency,
      a2.belnr                                               as DuplicateDocument,
      a2.gjahr                                               as DuplicateFiscalYear,
      a2.bldat                                               as DuplicateInvoiceDate,
      b2.wrbtr                                               as DuplicateGrossAmount,
      dats_days_between( a.bldat, a2.bldat )                 as DaysBetweenInvoices,
      // Higher criticality when amounts match exactly, lower when within tolerance
      case when b.wrbtr = b2.wrbtr then cast( 3 as abap.int1 )
                                   else cast( 2 as abap.int1 )
      end                                                    as RiskCriticality,
      $parameters.p_budat_from                               as ParamPostingDateFrom,
      $parameters.p_budat_to                                 as ParamPostingDateTo,
      $parameters.p_amount_threshold                         as ParamAmountThreshold,
      $parameters.p_tolerance_percent                        as ParamTolerancePercent
}

where a.budat  between $parameters.p_budat_from and $parameters.p_budat_to
  and a.bukrs   = $parameters.p_company_code
  // Exclude reversing documents and (best-effort) reversed originals
  and a.stblg   = ''
  and a2.stblg  = ''
  // Exclude credit memos (extend via config if needed)
  and a.blart  <> 'KG'
  and a2.blart <> 'KG'
  // Parked ('V') / held ('A') documents live on BKPF-BSTAT
  and a.bstat  <> 'V'
  and a.bstat  <> 'A'
  and a2.bstat <> 'V'
  and a2.bstat <> 'A'
  // Amount threshold and tolerance
  and b.wrbtr  >= $parameters.p_amount_threshold
  and b2.wrbtr >= b.wrbtr * ( 1 - $parameters.p_tolerance_percent / 100 )
  and b2.wrbtr <= b.wrbtr * ( 1 + $parameters.p_tolerance_percent / 100 )
  // Deterministic pair ordering: return each duplicate pair once
  and (    a2.gjahr >  a.gjahr
        or ( a2.gjahr = a.gjahr and a2.belnr > a.belnr ) )
  // 90-day window (forward-looking; combined with ordering avoids double pairs)
  and a2.bldat >= a.bldat
  and a2.bldat <= dats_add_days( a.bldat, 90, 'INITIAL' )