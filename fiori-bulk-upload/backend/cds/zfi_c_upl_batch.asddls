@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'FI bulk upload batch (projection)'
@Metadata.allowExtensions: true
define root view entity ZFI_C_UPL_BATCH
  provider contract transactional_query
  as projection on ZFI_I_UPL_BATCH
{
  key BatchUUID,
      CompanyCode,
      Ledger,
      Status,
      StatusCriticality,
      RequestedAction,
      Message,
      Attachment,
      MimeType,
      FileName,
      FileSize,
      FileHash,
      NumRows,
      NumPlanned,
      NumSkipped,
      NumError,
      NumLocked,
      NumChanged,
      CreatedBy,
      CreatedAt,
      LocalLastChangedBy,
      LocalLastChangedAt,
      LastChangedAt,

      _Item : redirected to composition child ZFI_C_UPL_ITEM
}
