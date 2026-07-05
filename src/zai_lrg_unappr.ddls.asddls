@AbapCatalog.sqlViewName: 'ZV_LRG_UNAPP_DOC'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Large Unapproved FI Documents'
@VDM.viewType: #CONSUMPTION

define view ZAI_LRG_UNAPPR
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from       : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to         : budat,
    @EndUserText.label: 'Amount Threshold'
    p_amount_threshold : netwr_ap
  as select from bkpf as h
    inner join   bseg as i on  h.bukrs = i.bukrs
                           and h.belnr = i.belnr
                           and h.gjahr = i.gjahr
    // Narrow LFA1 join to vendor line items only to reduce lookups.
    left outer join lfa1 as v on  i.lifnr = v.lifnr
                              and i.koart = 'K'
{
  key h.bukrs                                as CompanyCode,
  key h.belnr                                as AccountingDocument,
  key h.gjahr                                as FiscalYear,
  key i.buzei                                as LineItem,
      h.blart                                as DocumentType,
      h.budat                                as PostingDate,
      h.bldat                                as DocumentDate,
      h.xblnr                                as ExternalReference,
      h.usnam                                as EnteredBy,
      h.cpudt                                as EntryDate,
      i.koart                                as AccountType,
      i.lifnr                                as Vendor,
      v.name1                                as VendorName,
      i.hkont                                as GLAccount,
      i.wrbtr                                as Amount,
      i.waers                                as Currency,
      i.shkzg                                as DebitCreditIndicator,
      h.stblg                                as ReverseDocumentNumber,
      h.stjah                                as ReverseFiscalYear,
      h.awtyp                                as ReferenceProcedure,
      // TODO(approval): BKPF-BKTXT is a placeholder proxy for a customer-
      // specific "approval" marker. Replace with the real approval field
      // (Z-field, workflow status table, or released status CDS) via a
      // mapping/composition CDS. Current logic flags docs with blank BKTXT.
      h.bktxt                                as ApprovalFlag,
      cast( 3 as abap.int1 )                 as RiskCriticality
}
where h.budat between :p_budat_from and :p_budat_to
  // Amount threshold — restrict to EUR to match the business brief.
  // TODO: if multi-currency evaluation is required, convert via
  // currency_conversion( ) or evaluate on DMBTR with company code currency.
  and abs( i.wrbtr ) > :p_amount_threshold
  and i.waers = 'EUR'
  // Approval flag blank (placeholder — see TODO above)
  and h.bktxt = ''
  // Exclude both sides of a reversal: the reversed doc (STBLG populated)
  // and the reversing doc itself (XREVERSAL = 'X').
  and h.stblg     = ''
  and h.xreversal = ''
  // Company code scope 1000 / 2000 / 3000 (per control brief).
  // TODO(portability): move to a scope parameter or Z-config mapping CDS
  // so the control is reusable across landscapes.
  and h.bukrs in ( '1000', '2000', '3000' )
  // Exclude intercompany postings. BKPF-BVORG populated is an approximation;
  // TODO: for full accuracy also compare header BUKRS vs item BUKRS across
  // BSEG, or use a dedicated IC indicator/mapping CDS.
  and h.bvorg = ''