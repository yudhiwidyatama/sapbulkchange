*&---------------------------------------------------------------------*
*& Function module Z_FI_UPL_SCHEDULE   (create in SE37, function group ZFI_UPL)
*&   Processing type: Remote-Enabled Module (required for IN BACKGROUND TASK)
*&---------------------------------------------------------------------*
*& Called from the RAP saver (save_modified) with CALL FUNCTION ... IN BACKGROUND TASK,
*& i.e. executed as tRFC after the RAP COMMIT. It only schedules the job: JOB_OPEN /
*& SUBMIT / JOB_CLOSE are not allowed inside the RAP interaction/save phase.
*& On failure the tRFC entry stays in SM58 and can be re-executed.
*&---------------------------------------------------------------------*
FUNCTION z_fi_upl_schedule.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_UUID) TYPE  CHAR32
*"     VALUE(IV_ACTION) TYPE  CHAR1
*"----------------------------------------------------------------------
  DATA: lv_jobname  TYPE btcjob,
        lv_jobcount TYPE btcjobcnt.

  lv_jobname = |ZFI_UPL_{ iv_action }_{ iv_uuid(8) }|.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING
      jobname          = lv_jobname
    IMPORTING
      jobcount         = lv_jobcount
    EXCEPTIONS
      cant_create_job  = 1
      invalid_job_data = 2
      jobname_missing  = 3
      OTHERS           = 4.
  IF sy-subrc <> 0.
    MESSAGE ID 'ZFI_BULK' TYPE 'E' NUMBER '032' WITH 'JOB_OPEN'.
  ENDIF.

  SUBMIT zfi_upl_run
    WITH p_uuid = iv_uuid
    WITH p_act  = iv_action
    VIA JOB lv_jobname NUMBER lv_jobcount
    AND RETURN.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobcount  = lv_jobcount
      jobname   = lv_jobname
      strtimmed = 'X'
    EXCEPTIONS
      cant_start_immediate = 1
      invalid_startdate    = 2
      jobname_missing      = 3
      job_close_failed     = 4
      job_nosteps          = 5
      job_notex            = 6
      lock_failed          = 7
      OTHERS               = 8.
  IF sy-subrc <> 0.
    MESSAGE ID 'ZFI_BULK' TYPE 'E' NUMBER '032' WITH 'JOB_CLOSE'.
  ENDIF.
ENDFUNCTION.
