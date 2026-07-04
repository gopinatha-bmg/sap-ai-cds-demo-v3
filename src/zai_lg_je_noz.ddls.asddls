@AbapCatalog.sqlViewName: 'ZV_ACDOCA_LGAMT'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Large JE Missing Assignment'
@VDM.viewType: #CONSUMPTION

define view ZAI_LG_JE_NOZ
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from       : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to         : budat,
    @EndUserText.label: 'Company Code'
    p_company_code     : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year      : gjahr,
    @EndUserText.label: 'Amount Threshold (in Threshold Currency)'
    p_amount_threshold : hsl,
    @EndUserText.label: 'Threshold Currency (e.g. USD)'
    p_currency         : waers
    // Brief: "exceeds 100,000 USD" — pass p_amount_threshold = 100000, p_currency = 'USD'.
    // Note: BKPF/BSEG intentionally not read; ACDOCA is the universal journal in S/4HANA.

  as select from acdoca as a

    left outer join lfa1 as v
      on a.lifnr = v.lifnr

{
  key a.rbukrs                    as CompanyCode,
  key a.gjahr                     as FiscalYear,
  key a.belnr                     as AccountingDocument,
  key a.docln                     as DocumentLineItem,
      a.budat                     as PostingDate,
      a.bldat                     as DocumentDate,
      a.blart                     as DocumentType,
      a.hsl                       as AmountInCoCodeCurrency,
      a.rhcur                     as CoCodeCurrency,
      a.wsl                       as AmountInDocCurrency,
      a.rwcur                     as DocumentCurrency,
      a.racct                     as GLAccount,
      a.zuonr                     as AssignmentReference,
      a.sgtxt                     as ItemText,
      a.lifnr                     as Supplier,
      v.name1                     as SupplierName,
      a.kunnr                     as Customer,
      a.awtyp                     as ReferenceProcedure,
      a.awkey                     as ReferenceDocumentKey,
      a.usnam                     as UserName,
      // Criticality handled in consumption/UI layer per guardrails
      cast( 3 as abap.int1 )      as RiskCriticality
}
where a.budat  between :p_budat_from and :p_budat_to
  and a.rbukrs = :p_company_code
  and a.gjahr  = :p_fiscal_year
  // Enforce USD (or configured) currency so the "100,000 USD" rule is semantically correct.
  // If company code currency is not the threshold currency, evaluate document currency amount instead.
  and ( ( a.rhcur = :p_currency and abs( a.hsl ) >= :p_amount_threshold )
     or ( a.rwcur = :p_currency and abs( a.wsl ) >= :p_amount_threshold ) )
  and a.zuonr  = ''
  // TODO: optionally exclude reversal postings via a.xtruereversal / awtyp+awkey if required by policy.