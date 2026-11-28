@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'FI bulk upload item (projection)'
@Metadata.allowExtensions: true
define view entity ZFI_C_UPL_ITEM
  as projection on ZFI_I_UPL_ITEM
{
  key BatchUUID,
  key RowNo,
      CompanyCode,
      DocumentNumber,
      FiscalYear,
      LineItem,
      DocumentType,
      PostingDate,
      GLAccount,
      TargetAssignment,
      SourceData,
      OldAssignment,
      ClearingDocument,
      Status,
      StatusCriticality,
      ErrorField,
      Message,

      _Batch : redirected to parent ZFI_C_UPL_BATCH
}
