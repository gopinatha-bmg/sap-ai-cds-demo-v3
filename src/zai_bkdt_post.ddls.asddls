@AbapCatalog.sqlViewName: 'ZV_BKDT_POST'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Back-Dated GL Postings Outside Fiscal Period'
@VDM.viewType: #CONSUMPTION
define view ZAI_BKDT_POST
  with parameters
    p_budat_from       : budat,
    p_budat_to         : budat,
    p_company_code     : bukrs,
    p_fiscal_year      : gjahr,
    p_amount_threshold : dmbtr        -- GL local-currency amount domain

  as select from bkpf as h
    inner join   bseg as i on  i.bukrs = h.bukrs
                           and i.belnr = h.belnr
                           and i.gjahr = h.gjahr

{
  key h.bukrs                                                as CompanyCode,
  key h.belnr                                                as AccountingDocument,
  key h.gjahr                                                as FiscalYear,
  key i.buzei                                                as LineItem,
      h.blart                                                as DocumentType,
      h.bldat                                                as DocumentDate,
      h.budat                                                as PostingDate,
      h.cpudt                                                as EntryDate,
      h.monat                                                as FiscalPeriod,
      h.xblnr                                                as ReferenceDocument,
      h.usnam                                                as EnteredBy,
      i.hkont                                                as GLAccount,
      i.koart                                                as AccountType,
      i.shkzg                                                as DebitCreditIndicator,
      i.dmbtr                                                as AmountInLocalCurrency,
      i.wrbtr                                                as AmountInDocCurrency,
      i.waers                                                as DocumentCurrency,
      h.stblg                                                as ReversalDocument,

      // Positive when entry date is after posting date (i.e. back-dated posting)
      dats_days_between( h.budat, h.cpudt )                  as DaysBackdated,

      // NOTE: assumes a calendar-month fiscal year variant (e.g. K4).
      // For non-calendar variants, derive period from T009B instead.
      cast( substring( cast( h.budat as abap.char( 8 ) ), 5, 2 ) as abap.numc( 2 ) )
                                                              as DerivedPeriodFromBudat,

      // Simple risk banding based on how far back the posting was dated
      case when dats_days_between( h.budat, h.cpudt ) >= 30 then cast( 3 as abap.int1 )
           when dats_days_between( h.budat, h.cpudt ) >= 7  then cast( 2 as abap.int1 )
           else                                                   cast( 1 as abap.int1 )
      end                                                    as RiskCriticality
}
where h.budat  between :p_budat_from and :p_budat_to
  and h.bukrs   =  :p_company_code
  and h.gjahr   =  :p_fiscal_year
  and h.stblg   =  ''            -- not itself a reversed original
  and h.stgrd   =  ''            -- not a reversal document
  and i.koart   =  'S'           -- GL line items only
  and i.dmbtr   >= :p_amount_threshold
  // Single place expressing the exception rule:
  and (    h.cpudt >  h.budat
        or h.monat <> cast( substring( cast( h.budat as abap.char( 8 ) ), 5, 2 ) as abap.numc( 2 ) ) )