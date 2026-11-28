*&---------------------------------------------------------------------*
*& Report ZFI_UPL_RUN - background job entry point (scheduled by Z_FI_UPL_SCHEDULE)
*&---------------------------------------------------------------------*
REPORT zfi_upl_run.

PARAMETERS: p_uuid TYPE c LENGTH 32 OBLIGATORY,   " batch UUID as 32 hex characters
            p_act  TYPE c LENGTH 1  OBLIGATORY.   " V = validate, P = post

START-OF-SELECTION.
  DATA lv_uuid TYPE sysuuid_x16.
  lv_uuid = p_uuid.
  NEW zcl_fi_upload_job( )->run( iv_uuid = lv_uuid iv_action = p_act ).
