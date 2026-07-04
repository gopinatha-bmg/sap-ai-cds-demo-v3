@AbapCatalog.sqlViewName: 'ZV_JE_UNBAL'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Unbalanced Journal Entries'
@VDM.viewType: #CONSUMPTION
define view ZAI_JE_UNBAL
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from       : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to         : budat,
    @EndUserText.label: 'Company Code'
    p_company_code     : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year      : gjahr,
    @EndUserText.label: 'Amount Threshold (Absolute Imbalance in LC)'
    p_amount_threshold : dmbtr
    // suggested default: 0.01
  as select from bkpf as h
    inner join   bseg as i on  i.bukrs = h.bukrs
                           and i.belnr = h.belnr
                           and i.gjahr = h.gjahr
{
  key h.bukrs                                              as CompanyCode,
  key h.belnr                                              as AccountingDocument,
  key h.gjahr                                              as FiscalYear,
      h.blart                                              as DocumentType,
      h.budat                                              as PostingDate,
      h.bldat                                              as DocumentDate,
      h.xblnr                                              as ReferenceDocumentNo,
      h.usnam                                              as UserName,
      h.waers                                              as DocumentCurrency,

      // Signed local-currency total: S=debit(+), H=credit(-). A balanced JE = 0.
      // NOTE: HAVING replicates this expression because CDS HAVING cannot
      // reference SELECT aliases. If duplication becomes an issue, split into
      // a base aggregation CDS on BSEG and layer this exception view on top.
      sum( case when i.shkzg = 'H' then i.dmbtr * -1
                                   else i.dmbtr
           end )                                           as ImbalanceAmountLC,

      sum( case when i.shkzg = 'S' then i.dmbtr else 0 end ) as TotalDebitLC,
      sum( case when i.shkzg = 'H' then i.dmbtr else 0 end ) as TotalCreditLC,
      count( * )                                           as LineItemCount,

      // Static high criticality; consumption layer may override by magnitude.
      cast( 3 as abap.int1 )                               as RiskCriticality
}
where h.bukrs      = :p_company_code
  and h.gjahr      = :p_fiscal_year
  and h.budat      between :p_budat_from and :p_budat_to
  and h.stblg      = ''          // exclude documents that were reversed
  and h.xreversal  = ''          // exclude reversal documents themselves
// TODO: consider excluding noted items / statistical postings via i.bstat if in scope
group by
  h.bukrs,
  h.belnr,
  h.gjahr,
  h.blart,
  h.budat,
  h.bldat,
  h.xblnr,
  h.usnam,
  h.waers
having abs( sum( case when i.shkzg = 'H' then i.dmbtr * -1
                                         else i.dmbtr
                 end ) ) >= :p_amount_threshold