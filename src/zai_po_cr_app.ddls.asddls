@AbapCatalog.sqlViewName: 'ZV_PO_CR_APP'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator = Approver SoD Violation'
@VDM.viewType: #CONSUMPTION
@UI.headerInfo: {
    typeName:       'PO SoD Violation',
    typeNamePlural: 'PO SoD Violations',
    title: { value: 'PurchaseOrder' }
}

define view ZAI_PO_CR_APP
  with parameters
    @EndUserText.label: 'PO Change Date From'
    p_aedat_from   : erdat,
    @EndUserText.label: 'PO Change Date To'
    p_aedat_to     : erdat,
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value     : netwr_ap
  as select from ekko as POHeader
    inner join   ekpo as POItem on  POItem.ebeln = POHeader.ebeln
    // CDHDR/CDPOS: PO release events captured via change docs on EKKO-FRGZU.
    // TODO: confirm release tcodes in scope (ME28/ME29N) if further narrowing required.
    inner join   cdhdr as RelHdr on  RelHdr.objectclas = 'EINKBELEG'
                                 and RelHdr.objectid   = POHeader.ebeln
    inner join   cdpos as RelPos on  RelPos.objectclas = RelHdr.objectclas
                                 and RelPos.objectid   = RelHdr.objectid
                                 and RelPos.changenr   = RelHdr.changenr
                                 and RelPos.tabname    = 'EKKO'
                                 and RelPos.fname      = 'FRGZU'
{
    key POHeader.ebeln              as PurchaseOrder,
    key POItem.ebelp                as POItem,
    key RelHdr.changenr             as ChangeDocNumber,

    //-- Creator (EKKO.ernam) --------------------------------------
    @UI.lineItem: [{ position: 10, label: 'Created By' }]
    POHeader.ernam                  as CreatedBy,

    @UI.lineItem: [{ position: 20, label: 'Creation Date' }]
    POHeader.aedat                  as CreatedOn,

    //-- Approver (CDHDR.username — released via ME29N/ME28) -------
    // Note: multiple release change docs per PO may yield multiple rows
    // per (PO, item). Consumers should aggregate/distinct if needed.
    @UI.lineItem: [{
        position:    30,
        label:       'Released By',
        criticality: 'SoDCriticality'
    }]
    RelHdr.username                 as ReleasedBy,

    @UI.lineItem: [{ position: 40, label: 'Release Date' }]
    RelHdr.udate                    as ReleaseDate,
    RelHdr.utime                    as ReleaseTime,
    RelHdr.tcode                    as ReleaseTCode,

    //-- Release status before / after (FRGZU bitmap) --------------
    RelPos.value_old                as ReleaseStatusBefore,
    RelPos.value_new                as ReleaseStatusAfter,

    //-- PO header attributes --------------------------------------
    @UI.lineItem: [{ position: 50, label: 'Company Code' }]
    POHeader.bukrs                  as CompanyCode,

    @UI.lineItem: [{ position: 60, label: 'Vendor' }]
    POHeader.lifnr                  as Supplier,

    @UI.lineItem: [{ position: 70, label: 'Doc Type' }]
    POHeader.bsart                  as PODocType,

    POHeader.frggr                  as ReleaseGroup,
    POHeader.frgsx                  as ReleaseStrategy,
    POHeader.frgke                  as ReleaseIndicator,
    POHeader.frgzu                  as ReleaseStatus,

    //-- PO item amount --------------------------------------------
    @Semantics.amount.currencyCode: 'Currency'
    @UI.lineItem: [{ position: 80, label: 'Net Value' }]
    POItem.netwr                    as NetValue,

    @Semantics.currencyCode: true
    POHeader.waers                  as Currency,

    //-- SoD Criticality: all returned rows are confirmed violations
    @UI.hidden: true
    cast( 3 as abap.int1 )          as SoDCriticality
}
where
      // Time window (PO change/creation date)
      POHeader.aedat between :p_aedat_from and :p_aedat_to
      // Minimum PO net value threshold
  and POItem.netwr    >= :p_po_value
      // Only finally released POs
  and POHeader.frgke  <> ''
      // SoD violation: creator and approver are the same person
  and POHeader.ernam   = RelHdr.username
      // Exclude blank usernames
  and RelHdr.username <> ''
      // Exclude deleted PO items (kept in WHERE, not in join, to avoid duplication)
  and POItem.loekz    = ''