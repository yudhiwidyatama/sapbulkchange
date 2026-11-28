" Application log (SLG1), object ZFI_BULK / subobject UPLOAD (create in SLG0).
" Classic BAL function modules: CL_BALI_LOG release status on 2022 on-premise is unverified.
CLASS zcl_fi_upl_log DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_extnumber TYPE csequence.

    METHODS add
      IMPORTING iv_msgty TYPE symsgty
                iv_text  TYPE string.

    " Writes to the database; the caller issues COMMIT WORK.
    METHODS save.

  PRIVATE SECTION.
    DATA mv_handle TYPE balloghndl.

ENDCLASS.


CLASS zcl_fi_upl_log IMPLEMENTATION.

  METHOD constructor.
    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = VALUE bal_s_log( object    = zif_fi_upl_types=>gc_log_object
                                        subobject = zif_fi_upl_types=>gc_log_subobject
                                        extnumber = iv_extnumber
                                        aluser    = sy-uname
                                        alprog    = sy-repid )
      IMPORTING
        e_log_handle = mv_handle
      EXCEPTIONS
        OTHERS       = 1.
  ENDMETHOD.

  METHOD add.
    IF mv_handle IS INITIAL.
      RETURN.
    ENDIF.
    CALL FUNCTION 'BAL_LOG_MSG_ADD_FREE_TEXT'
      EXPORTING
        i_log_handle = mv_handle
        i_msgty      = iv_msgty
        i_text       = CONV char200( iv_text )
      EXCEPTIONS
        OTHERS       = 1.
  ENDMETHOD.

  METHOD save.
    IF mv_handle IS INITIAL.
      RETURN.
    ENDIF.
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle = VALUE bal_t_logh( ( mv_handle ) )
      EXCEPTIONS
        OTHERS         = 1.
  ENDMETHOD.

ENDCLASS.
