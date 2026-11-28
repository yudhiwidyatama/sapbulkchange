@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'FI bulk upload batch'
define root view entity ZFI_I_UPL_BATCH
  as select from zfi_upl_batch
  composition [0..*] of ZFI_I_UPL_ITEM as _Item
{
  key batch_uuid            as BatchUUID,
      bukrs                 as CompanyCode,
      rldnr                 as Ledger,
      status                as Status,
      case status
        when 'DONE'       then 3
        when 'VALIDATED'  then 2
        when 'FILE_ERROR' then 1
        else 0
      end                   as StatusCriticality,
      requested_action      as RequestedAction,
      message               as Message,

      @Semantics.largeObject: {
        mimeType: 'MimeType',
        fileName: 'FileName',
        acceptableMimeTypes: [ 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ],
        contentDispositionPreference: #ATTACHMENT
      }
      attachment            as Attachment,
      @Semantics.mimeType: true
      mimetype              as MimeType,
      filename              as FileName,
      file_size             as FileSize,
      file_hash             as FileHash,

      n_rows                as NumRows,
      n_planned             as NumPlanned,
      n_skipped             as NumSkipped,
      n_error               as NumError,
      n_locked              as NumLocked,
      n_changed             as NumChanged,

      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      local_last_changed_by as LocalLastChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,

      _Item
}
