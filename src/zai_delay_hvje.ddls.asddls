@AbapCatalog.sqlViewName: 'ZV_DELAY_HVJE'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Delayed High-Value Journal Postings'
@VDM.viewType: #CONSUMPTION
define view ZAI_DELAY_HVJE
  with parameters
    p_budat_from        : budat,
    p_budat_to          : budat,
    p_company_code      : bukrs,
    p_fiscal_year       : gjahr,
    p_amount_threshold  : dmbtr

  as select from bkpf as h
    inner join   bseg as i on  i.bukrs = h.bukrs
                           and i.belnr = h.belnr
                           and i.gjahr = h.gjahr
    left outer join lfa1 as v on v.lifnr = i.lifnr

{
  key h.bukrs                                                 as CompanyCode,
  key h.belnr                                                 as AccountingDocument,
  key h.gjahr                                                 as FiscalYear,
  key i.buzei                                                 as LineItem,
      h.blart                                                 as DocumentType,
      h.bldat                                                 as DocumentDate,
      h.budat                                                 as PostingDate,
      h.cpudt                                                 as EntryDate,
      h.xblnr                                                 as ExternalReference,
      h.usnam                                                 as EnteredBy,
      i.hkont                                                 as GLAccount,
      i.koart                                                 as AccountType,
      i.lifnr                                                 as Vendor,
      v.name1                                                 as VendorName,
      i.dmbtr                                                 as AmountInLocalCurrency,
      h.hwaer                                                 as LocalCurrency,
      i.wrbtr                                                 as AmountInDocCurrency,
      i.waers                                                 as DocumentCurrency,
      i.shkzg                                                 as DebitCreditIndicator,
      dats_days_between( h.bldat, h.budat )                   as PostingDelayDays,
      // TODO: replace static rating with amount-band tiers if required
      cast( 3 as abap.int1 )                                  as RiskCriticality
}

where h.budat  between :p_budat_from and :p_budat_to
  and h.bukrs   =  :p_company_code
  and h.gjahr   =  :p_fiscal_year
  and h.stblg   =  ''            // exclude reversal documents
  and h.bstat   =  ''            // exclude statistical / noise document status
  and i.dmbtr   >  :p_amount_threshold
  and h.budat   >  dats_add_days( h.bldat, 30, initial )