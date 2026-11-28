INTERFACE zif_fi_upl_types PUBLIC.

  TYPES tt_items TYPE STANDARD TABLE OF zfi_upl_item WITH EMPTY KEY
        WITH NON-UNIQUE SORTED KEY k_doc COMPONENTS belnr gjahr.

  TYPES: BEGIN OF ty_counts,
           rows    TYPE i,
           planned TYPE i,
           skipped TYPE i,
           error   TYPE i,
           locked  TYPE i,
           changed TYPE i,
         END OF ty_counts.

  CONSTANTS: BEGIN OF gc_batch_status,
               uploaded   TYPE zfi_upl_batch-status VALUE 'UPLOADED',
               validating TYPE zfi_upl_batch-status VALUE 'VALIDATING',
               validated  TYPE zfi_upl_batch-status VALUE 'VALIDATED',
               file_error TYPE zfi_upl_batch-status VALUE 'FILE_ERROR',
               posting    TYPE zfi_upl_batch-status VALUE 'POSTING',
               done       TYPE zfi_upl_batch-status VALUE 'DONE',
             END OF gc_batch_status.

  CONSTANTS: BEGIN OF gc_item_status,
               new               TYPE zfi_upl_item-status VALUE 'NEW',
               excel_error       TYPE zfi_upl_item-status VALUE 'EXCEL_ERROR',
               doc_not_found     TYPE zfi_upl_item-status VALUE 'DOC_NOT_FOUND',
               item_not_found    TYPE zfi_upl_item-status VALUE 'ITEM_NOT_FOUND',
               validation_failed TYPE zfi_upl_item-status VALUE 'VALIDATION_FAILED',
               skipped           TYPE zfi_upl_item-status VALUE 'SKIPPED_ALREADY_SET',
               planned           TYPE zfi_upl_item-status VALUE 'PLANNED',
               locked            TYPE zfi_upl_item-status VALUE 'LOCKED',
               send_error        TYPE zfi_upl_item-status VALUE 'SEND_ERROR',
               changed           TYPE zfi_upl_item-status VALUE 'CHANGED',
               not_changed       TYPE zfi_upl_item-status VALUE 'NOT_CHANGED',
             END OF gc_item_status.

  CONSTANTS gc_msgid          TYPE symsgid  VALUE 'ZFI_BULK'.
  CONSTANTS gc_max_rows       TYPE i        VALUE 50000.
  CONSTANTS gc_max_bytes      TYPE i        VALUE 20971520. " 20 MB
  CONSTANTS gc_max_mb         TYPE i        VALUE 20.
  CONSTANTS gc_doc_chunk      TYPE i        VALUE 5000.     " documents per ACDOCA read
  CONSTANTS gc_post_chunk     TYPE i        VALUE 500.      " documents per persisted post step
  CONSTANTS gc_source_beban   TYPE c LENGTH 6 VALUE 'BEBAN'.
  CONSTANTS gc_source_vendor  TYPE c LENGTH 6 VALUE 'VENDOR'.
  CONSTANTS gc_actvt_change   TYPE activ_auth  VALUE '02'.
  CONSTANTS gc_log_object     TYPE balobj_d    VALUE 'ZFI_BULK'.
  CONSTANTS gc_log_subobject  TYPE balsubobj   VALUE 'UPLOAD'.

ENDINTERFACE.
