@AccessControl.authorizationCheck: #NOT_REQUIRED
@AbapCatalog.sqlViewName: 'ZV_POCRAP'
@AbapCatalog.compiler.compareFilter: true
@EndUserText.label: 'PO creator approver SoD'
@VDM.viewType: #CONSUMPTION
define view ZAI_POCRAPV
  with parameters
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value : netwr_ap
  as select from ekko as POHeader
    inner join cdhdr as RelHdr
      on RelHdr.objectid = POHeader.ebeln
    inner join cdpos as RelPos
      on RelPos.changenr = RelHdr.changenr
     and RelPos.tabname  = 'EKKO'
     and ( RelPos.fname  = 'FRGZU'
        or RelPos.fname  = 'FRGKE' )
    left outer join usr02 as TechUser
      on TechUser.bname = RelHdr.username
{
  key POHeader.ebeln          as PurchaseOrder,
      POHeader.bsart          as DocumentType,
      POHeader.bukrs          as CompanyCode,
      POHeader.ekorg          as PurchasingOrganization,
      POHeader.ekgrp          as PurchasingGroup,
      POHeader.lifnr          as Vendor,
      POHeader.ernam          as CreatedBy,
      RelHdr.username         as ReleasedBy,
      RelHdr.udate            as ReleaseDate,
      RelHdr.utime            as ReleaseTime,
      RelHdr.tcode            as ReleaseTCode,
      RelPos.fname            as ChangeField,
      RelPos.value_old        as ReleaseStatusBefore,
      RelPos.value_new        as ReleaseStatusAfter,
      @Semantics.amount.currencyCode: 'Currency'
      POHeader.netwr          as NetValue,
      POHeader.waers          as Currency,
      POHeader.frggr          as ReleaseGroup,
      POHeader.frgsx          as ReleaseStrategy,
      POHeader.frgke          as ReleaseIndicator,
      POHeader.frgzu          as ReleaseStatus,
      @UI.hidden: true
      cast( 3 as abap.int1 )  as SoDCriticality
}
where POHeader.ernam = RelHdr.username
  and POHeader.bsart <> 'UB'
  and POHeader.bsart <> 'FO'
  and ( RelHdr.tcode = 'ME29N' or RelHdr.tcode = 'ME28' )
  and RelHdr.username <> ''
  and ( TechUser.bname is null or TechUser.ustyp <> 'B' )
  and RelPos.value_old <> RelPos.value_new
  and POHeader.netwr >= :p_po_value
  // TODO: Extend technical/background user exclusion with a customer mapping view/table if required.
;