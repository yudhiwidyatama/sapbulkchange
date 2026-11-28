@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'FI bulk upload item'
define view entity ZFI_I_UPL_ITEM
  as select from zfi_upl_item
  association to parent ZFI_I_UPL_BATCH as _Batch on $projection.BatchUUID = _Batch.BatchUUID
{
  key batch_uuid   as BatchUUID,
  key row_no       as RowNo,
      bukrs        as CompanyCode,
      belnr        as DocumentNumber,
      gjahr        as FiscalYear,
      buzei        as LineItem,
      blart        as DocumentType,
      budat        as PostingDate,
      racct        as GLAccount,
      target_zuonr as TargetAssignment,
      source_data  as SourceData,
      old_zuonr    as OldAssignment,
      augbl        as ClearingDocument,
      status       as Status,
      case status
        when 'CHANGED'             then 3
        when 'PLANNED'             then 3
        when 'SKIPPED_ALREADY_SET' then 2
        when 'LOCKED'              then 2
        else 1
      end          as StatusCriticality,
      error_field  as ErrorField,
      message      as Message,

      _Batch
}
