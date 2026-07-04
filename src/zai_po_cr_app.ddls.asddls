/*
=============================================================
  CDS VIEW   : ZAI_PO_CR_APP
  SQL VIEW   : ZV_PO_CR_APP
  Description: Identify POs where Creator (EKKO.ernam) and
               Approver (CDHDR.username via Release Strategy)
               are the same person — Segregation of Duties
               (SoD) violation.
               Uses CDHDR/CDPOS on EKKO.FRGZU (Release Status)
               to identify who approved the PO via ME29N/ME28.
               SWW_WI2OBJ / SWWWIHEAD are NOT used because PO
               approval runs through Release Strategy, not
               SAP Business Workflow.
  System     : S/4HANA 2025 On-Premise

  NOTE / TODO:
   * Every CDPOS row on FRGZU is treated as a release event;
     this may include partial or intermediate releases. For a
     stricter check, layer a base view that keeps only the
     final release event (max udate/utime per PO) or add
     EKKO.FRGKE = 'R' correlation.
   * TCODE filter restricts to ME28 / ME29 / ME29N to reduce
     false positives from programmatic FRGZU updates.
=============================================================
*/
@AbapCatalog.sqlViewName: 'ZV_PO_CR_APP'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator = Approver (SoD Violation)'
@VDM.viewType: #CONSUMPTION
@UI.headerInfo: {
    typeName:       'SoD Violation',
    typeNamePlural: 'SoD Violations',
    title:          { value: 'PurchasingDocument' }
}

define view ZAI_PO_CR_APP
  with parameters
    @EndUserText.label: 'PO Change Date From (EKKO.AEDAT)'
    p_aedat_from  : aedat,
    @EndUserText.label: 'PO Change Date To (EKKO.AEDAT)'
    p_aedat_to    : aedat,
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value    : netwr_ap

  as select from ekko as POHeader

    inner join   ekpo  as POItem
      on  POItem.ebeln = POHeader.ebeln

    // Release Strategy change document — who released the PO
    inner join   cdhdr as RelHdr
      on  RelHdr.objectclas = 'EINKBELEG'
      and RelHdr.objectid   = POHeader.ebeln

    inner join   cdpos as RelPos
      on  RelPos.objectclas = RelHdr.objectclas
      and RelPos.objectid   = RelHdr.objectid
      and RelPos.changenr   = RelHdr.changenr
      and RelPos.tabname    = 'EKKO'
      and RelPos.fname      = 'FRGZU'

{
    key POHeader.ebeln              as PurchasingDocument,
    key POItem.ebelp                as PurchasingDocumentItem,
    key RelHdr.changenr             as ChangeDocumentNumber,

    //-- Creator (EKKO.ernam) -----------------------------------
    @UI.lineItem: [{ position: 10, label: 'PO Creator' }]
    POHeader.ernam                  as CreatedBy,

    @UI.lineItem: [{ position: 20, label: 'PO Creation Date' }]
    POHeader.aedat                  as CreationDate,

    @UI.lineItem: [{ position: 30, label: 'Purchasing Doc Type' }]
    POHeader.bsart                  as PurchasingDocumentType,

    @UI.lineItem: [{ position: 40, label: 'Purchasing Org' }]
    POHeader.ekorg                  as PurchasingOrganization,

    @UI.lineItem: [{ position: 50, label: 'Purchasing Group' }]
    POHeader.ekgrp                  as PurchasingGroup,

    @UI.lineItem: [{ position: 60, label: 'Vendor' }]
    POHeader.lifnr                  as Supplier,

    //-- Approver (CDHDR.username — who released via ME29N/ME28)
    @UI.lineItem: [{
        position:    100,
        label:       'Released By',
        criticality: 'SoDCriticality'
    }]
    RelHdr.username                 as ReleasedBy,

    @UI.lineItem: [{ position: 110, label: 'Release Date' }]
    RelHdr.udate                    as ReleaseDate,

    RelHdr.utime                    as ReleaseTime,
    RelHdr.tcode                    as ReleaseTCode,

    RelPos.value_old                as ReleaseStatusBefore,
    RelPos.value_new                as ReleaseStatusAfter,

    //-- PO Item Fields -----------------------------------------
    @Semantics.amount.currencyCode: 'Currency'
    @UI.lineItem: [{ position: 120, label: 'Net Value' }]
    POItem.netwr                    as NetValue,

    @Semantics.currencyCode: true
    POHeader.waers                  as Currency,

    //-- SoD Criticality ----------------------------------------
    // 3 = Red — every returned row is a confirmed SoD violation
    // (Creator = Approver).
    @UI.hidden: true
    cast( 3 as abap.int1 )          as SoDCriticality
}
where
      // Time window on PO change date
      POHeader.aedat   between :p_aedat_from and :p_aedat_to
      // Narrow CDHDR by the same window to protect performance
  and RelHdr.udate     between :p_aedat_from and :p_aedat_to
      // Restrict to release-strategy transactions only
  and RelHdr.tcode     in ( 'ME28', 'ME29', 'ME29N' )
      // Minimum PO net value threshold (item level)
  and POItem.netwr     >= :p_po_value
      // SoD condition — Creator = Approver
  and POHeader.ernam   =  RelHdr.username
      // Only rows where a release code was actually set
  and RelPos.value_new <> ''
      // Exclude deleted PO items
  and POItem.loekz     =  ''