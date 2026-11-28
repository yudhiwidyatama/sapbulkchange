CLASS lhc_batch DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Batch RESULT result.
    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Batch RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Batch RESULT result.
    METHODS validate FOR MODIFY IMPORTING keys FOR ACTION Batch~validate RESULT result.
    METHODS post     FOR MODIFY IMPORTING keys FOR ACTION Batch~post     RESULT result.
    METHODS onfile   FOR DETERMINE ON MODIFY IMPORTING keys FOR Batch~onfile.
    METHODS checkinput FOR VALIDATE ON SAVE IMPORTING keys FOR Batch~checkinput.

    METHODS authorized
      IMPORTING iv_bukrs     TYPE bukrs
      RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDCLASS.


CLASS lhc_batch IMPLEMENTATION.

  METHOD authorized.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD iv_bukrs
      ID 'ACTVT' FIELD zif_fi_upl_types=>gc_actvt_change.
    rv_ok = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD get_global_authorizations.
    " The company-code check needs instance data: instance authorization for update/delete/
    " actions, validation checkInput for create.
    result = VALUE #( %create = if_abap_behv=>auth-allowed
                      %update = if_abap_behv=>auth-allowed
                      %delete = if_abap_behv=>auth-allowed
                      %action-validate = if_abap_behv=>auth-allowed
                      %action-post     = if_abap_behv=>auth-allowed ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( CompanyCode ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    result = VALUE #( FOR b IN lt_batches
      LET auth = COND #( WHEN authorized( b-CompanyCode ) = abap_true
                         THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized )
      IN ( %tky = b-%tky
           %update = auth
           %delete = auth
           %action-validate = auth
           %action-post     = auth ) ).
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( Status NumPlanned ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    result = VALUE #( FOR b IN lt_batches
      LET busy = xsdbool( b-Status = zif_fi_upl_types=>gc_batch_status-validating
                       OR b-Status = zif_fi_upl_types=>gc_batch_status-posting )
          can_validate = xsdbool( b-Status = zif_fi_upl_types=>gc_batch_status-uploaded
                               OR b-Status = zif_fi_upl_types=>gc_batch_status-validated
                               OR b-Status = zif_fi_upl_types=>gc_batch_status-file_error )
          can_post = xsdbool( b-Status = zif_fi_upl_types=>gc_batch_status-validated AND b-NumPlanned > 0 )
      IN ( %tky = b-%tky
           %update = COND #( WHEN busy = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
           %delete = COND #( WHEN busy = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
           %action-validate = COND #( WHEN can_validate = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
           %action-post     = COND #( WHEN can_post = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD validate.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( Status CompanyCode ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    DATA lt_upd TYPE TABLE FOR UPDATE zfi_i_upl_batch\\Batch.
    LOOP AT lt_batches ASSIGNING FIELD-SYMBOL(<b>).
      IF NOT ( <b>-Status = zif_fi_upl_types=>gc_batch_status-uploaded
            OR <b>-Status = zif_fi_upl_types=>gc_batch_status-validated
            OR <b>-Status = zif_fi_upl_types=>gc_batch_status-file_error ).
        APPEND VALUE #( %tky = <b>-%tky ) TO failed-batch.
        APPEND VALUE #( %tky = <b>-%tky
                        %msg = new_message( id = zif_fi_upl_types=>gc_msgid number = '025'
                                            severity = if_abap_behv_message=>severity-error
                                            v1 = <b>-Status ) ) TO reported-batch.
        CONTINUE.
      ENDIF.
      IF authorized( <b>-CompanyCode ) = abap_false.
        APPEND VALUE #( %tky = <b>-%tky ) TO failed-batch.
        APPEND VALUE #( %tky = <b>-%tky
                        %msg = new_message( id = zif_fi_upl_types=>gc_msgid number = '006'
                                            severity = if_abap_behv_message=>severity-error
                                            v1 = <b>-CompanyCode ) ) TO reported-batch.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = <b>-%tky
                      Status = zif_fi_upl_types=>gc_batch_status-validating
                      RequestedAction = 'V'
                      Message = ''
                      %control = VALUE #( Status = if_abap_behv=>mk-on
                                          RequestedAction = if_abap_behv=>mk-on
                                          Message = if_abap_behv=>mk-on ) ) TO lt_upd.
    ENDLOOP.

    MODIFY ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch UPDATE FROM lt_upd.

    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR r IN lt_after ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD post.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( Status CompanyCode NumPlanned FileHash ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    DATA lt_upd TYPE TABLE FOR UPDATE zfi_i_upl_batch\\Batch.
    LOOP AT lt_batches ASSIGNING FIELD-SYMBOL(<b>).
      DATA(lv_msgno) = VALUE symsgno( ).
      DATA(lv_v1)    = VALUE string( ).

      IF <b>-Status <> zif_fi_upl_types=>gc_batch_status-validated.
        lv_msgno = '025'.
        lv_v1    = <b>-Status.
      ELSEIF <b>-NumPlanned = 0.
        lv_msgno = '026'.
      ELSEIF authorized( <b>-CompanyCode ) = abap_false.
        lv_msgno = '006'.
        lv_v1    = <b>-CompanyCode.
      ELSE.
        " Re-upload handling: same file content already posted for this company code.
        SELECT SINGLE batch_uuid FROM zfi_upl_batch
          WHERE file_hash = @<b>-FileHash
            AND bukrs     = @<b>-CompanyCode
            AND status    = @zif_fi_upl_types=>gc_batch_status-done
            AND n_changed > 0
            AND batch_uuid <> @<b>-BatchUUID
          INTO @DATA(lv_other).
        IF sy-subrc = 0.
          lv_msgno = '024'.
          lv_v1    = |{ lv_other }|.
        ENDIF.
      ENDIF.

      IF lv_msgno IS NOT INITIAL.
        APPEND VALUE #( %tky = <b>-%tky ) TO failed-batch.
        APPEND VALUE #( %tky = <b>-%tky
                        %msg = new_message( id = zif_fi_upl_types=>gc_msgid number = lv_msgno
                                            severity = if_abap_behv_message=>severity-error
                                            v1 = lv_v1 ) ) TO reported-batch.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = <b>-%tky
                      Status = zif_fi_upl_types=>gc_batch_status-posting
                      RequestedAction = 'P'
                      Message = ''
                      %control = VALUE #( Status = if_abap_behv=>mk-on
                                          RequestedAction = if_abap_behv=>mk-on
                                          Message = if_abap_behv=>mk-on ) ) TO lt_upd.
    ENDLOOP.

    MODIFY ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch UPDATE FROM lt_upd.

    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR r IN lt_after ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD onfile.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( Attachment ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    DATA lt_upd TYPE TABLE FOR UPDATE zfi_i_upl_batch\\Batch.
    LOOP AT lt_batches ASSIGNING FIELD-SYMBOL(<b>).
      DATA(lv_hash) = VALUE string( ).
      IF <b>-Attachment IS NOT INITIAL.
        TRY.
            cl_abap_message_digest=>calculate_hash_for_raw(
              EXPORTING if_algorithm  = 'SHA256'
                        if_data       = <b>-Attachment
              IMPORTING ef_hashxstring = DATA(lv_hashx) ).
            lv_hash = |{ lv_hashx }|.
          CATCH cx_abap_message_digest.
            CLEAR lv_hash.
        ENDTRY.
      ENDIF.
      " A new file resets the batch to UPLOADED with empty results.
      APPEND VALUE #( %tky = <b>-%tky
                      Status = zif_fi_upl_types=>gc_batch_status-uploaded
                      Message = ''
                      FileSize = xstrlen( <b>-Attachment )
                      FileHash = lv_hash
                      NumRows = 0 NumPlanned = 0 NumSkipped = 0 NumError = 0 NumLocked = 0 NumChanged = 0
                      %control = VALUE #( Status = if_abap_behv=>mk-on Message = if_abap_behv=>mk-on
                                          FileSize = if_abap_behv=>mk-on FileHash = if_abap_behv=>mk-on
                                          NumRows = if_abap_behv=>mk-on NumPlanned = if_abap_behv=>mk-on
                                          NumSkipped = if_abap_behv=>mk-on NumError = if_abap_behv=>mk-on
                                          NumLocked = if_abap_behv=>mk-on NumChanged = if_abap_behv=>mk-on ) ) TO lt_upd.
    ENDLOOP.

    MODIFY ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch UPDATE FROM lt_upd.
  ENDMETHOD.

  METHOD checkinput.
    READ ENTITIES OF zfi_i_upl_batch IN LOCAL MODE
      ENTITY Batch FIELDS ( CompanyCode Ledger Attachment FileName FileSize ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_batches).

    LOOP AT lt_batches ASSIGNING FIELD-SYMBOL(<b>).
      DATA(lv_msgno) = VALUE symsgno( ).
      DATA(lv_v1)    = VALUE string( ).
      DATA(ls_elem)  = VALUE zfi_i_upl_batch\\Batch-%element( ).

      IF <b>-CompanyCode IS INITIAL.
        lv_msgno = '011'. lv_v1 = 'Company Code'. ls_elem-CompanyCode = if_abap_behv=>mk-on.
      ELSEIF <b>-Ledger IS INITIAL.
        lv_msgno = '011'. lv_v1 = 'Ledger'. ls_elem-Ledger = if_abap_behv=>mk-on.
      ELSEIF <b>-Attachment IS INITIAL.
        lv_msgno = '011'. lv_v1 = 'File'. ls_elem-Attachment = if_abap_behv=>mk-on.
      ELSEIF xstrlen( <b>-Attachment ) < 4 OR <b>-Attachment(2) <> CONV xstring( '504B' ).
        " an .xlsx file is a zip archive and starts with 'PK'
        lv_msgno = '001'. ls_elem-Attachment = if_abap_behv=>mk-on.
      ELSEIF <b>-FileName IS NOT INITIAL
         AND NOT matches( val = to_lower( condense( <b>-FileName ) ) regex = '.*\.xlsx' ).
        lv_msgno = '004'. ls_elem-Attachment = if_abap_behv=>mk-on.
      ELSEIF <b>-FileSize > zif_fi_upl_types=>gc_max_bytes.
        lv_msgno = '005'. lv_v1 = |{ zif_fi_upl_types=>gc_max_mb }|. ls_elem-Attachment = if_abap_behv=>mk-on.
      ELSEIF authorized( <b>-CompanyCode ) = abap_false.
        lv_msgno = '006'. lv_v1 = <b>-CompanyCode. ls_elem-CompanyCode = if_abap_behv=>mk-on.
      ENDIF.

      IF lv_msgno IS NOT INITIAL.
        APPEND VALUE #( %tky = <b>-%tky ) TO failed-batch.
        APPEND VALUE #( %tky = <b>-%tky
                        %msg = new_message( id = zif_fi_upl_types=>gc_msgid number = lv_msgno
                                            severity = if_abap_behv_message=>severity-error
                                            v1 = lv_v1 )
                        %element = ls_elem ) TO reported-batch.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


CLASS lsc_zfi_i_upl_batch DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.


CLASS lsc_zfi_i_upl_batch IMPLEMENTATION.

  METHOD save_modified.
    " Validate/Post only set status + RequestedAction. The job is scheduled here, in the save
    " phase, through a tRFC (executed after the RAP COMMIT) - see Z_FI_UPL_SCHEDULE.
    LOOP AT update-batch ASSIGNING FIELD-SYMBOL(<u>)
         WHERE %control-RequestedAction = if_abap_behv=>mk-on
           AND RequestedAction IS NOT INITIAL.
      CALL FUNCTION 'Z_FI_UPL_SCHEDULE' IN BACKGROUND TASK
        EXPORTING
          iv_uuid   = CONV char32( <u>-BatchUUID )
          iv_action = <u>-RequestedAction.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
