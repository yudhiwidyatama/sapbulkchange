" Background job logic: Validate (authority, parse, resolve, lock check) and Post.
" Runs in the job session, so COMMIT WORK is allowed here (it is not inside RAP).
CLASS zcl_fi_upload_job DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS gc_validate TYPE c LENGTH 1 VALUE 'V'.
    CONSTANTS gc_post     TYPE c LENGTH 1 VALUE 'P'.

    METHODS constructor.

    METHODS run
      IMPORTING iv_uuid   TYPE sysuuid_x16
                iv_action TYPE c.

  PRIVATE SECTION.
    DATA mv_uuid   TYPE sysuuid_x16.
    DATA ms_batch  TYPE zfi_upl_batch.
    DATA mo_engine TYPE REF TO zcl_fi_upload_engine.
    DATA mo_log    TYPE REF TO zcl_fi_upl_log.

    METHODS check_authority RAISING zcx_fi_upload.
    METHODS check_not_posted_before RAISING zcx_fi_upload.

    METHODS build_items
      RETURNING VALUE(rt_items) TYPE zif_fi_upl_types=>tt_items
      RAISING   zcx_fi_upload.

    METHODS persist_items
      IMPORTING it_items TYPE zif_fi_upl_types=>tt_items.

    METHODS update_batch
      IMPORTING iv_status TYPE zfi_upl_batch-status
                iv_text   TYPE string OPTIONAL
                is_counts TYPE zif_fi_upl_types=>ty_counts OPTIONAL.

    METHODS do_validate RAISING zcx_fi_upload.
    METHODS do_post     RAISING zcx_fi_upload.
    METHODS fail IMPORTING iv_text TYPE string.

ENDCLASS.


CLASS zcl_fi_upload_job IMPLEMENTATION.

  METHOD constructor.
    mo_engine = NEW #( io_db      = NEW zcl_fi_db_provider( )
                       io_changer = NEW zcl_fi_doc_changer( ) ).
  ENDMETHOD.

  METHOD run.
    mv_uuid = iv_uuid.
    SELECT SINGLE * FROM zfi_upl_batch WHERE batch_uuid = @iv_uuid INTO @ms_batch.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Stale or duplicate trigger: only the status set by the RAP action starts work.
    DATA(lv_expected) = COND zfi_upl_batch-status(
      WHEN iv_action = gc_validate THEN zif_fi_upl_types=>gc_batch_status-validating
      ELSE zif_fi_upl_types=>gc_batch_status-posting ).
    IF ms_batch-status <> lv_expected.
      RETURN.
    ENDIF.

    mo_log = NEW #( |{ iv_action }-{ iv_uuid }| ).
    UPDATE zfi_upl_batch SET requested_action = @space WHERE batch_uuid = @iv_uuid.
    COMMIT WORK.

    TRY.
        check_authority( ).
        CASE iv_action.
          WHEN gc_validate.
            do_validate( ).
          WHEN gc_post.
            do_post( ).
        ENDCASE.
      CATCH zcx_fi_upload INTO DATA(lx_upl).
        fail( lx_upl->get_text( ) ).
      CATCH cx_root INTO DATA(lx_root).
        fail( lx_root->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD check_authority.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD ms_batch-bukrs
      ID 'ACTVT' FIELD zif_fi_upl_types=>gc_actvt_change.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '006' msgv1 = ms_batch-bukrs ).
    ENDIF.
  ENDMETHOD.

  METHOD check_not_posted_before.
    " Same file content and company code already changed documents in another batch.
    SELECT SINGLE batch_uuid FROM zfi_upl_batch
      WHERE file_hash = @ms_batch-file_hash
        AND bukrs     = @ms_batch-bukrs
        AND status    = @zif_fi_upl_types=>gc_batch_status-done
        AND n_changed > 0
        AND batch_uuid <> @mv_uuid
      INTO @DATA(lv_other).
    IF sy-subrc = 0.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '024' msgv1 = |{ lv_other }| ).
    ENDIF.
  ENDMETHOD.

  METHOD build_items.
    DATA(lt_rows) = zcl_fi_xlsx_reader=>parse( ms_batch-attachment ).
    CLEAR ms_batch-attachment.   " free memory
    rt_items = NEW zcl_fi_upload_parser( )->parse( it_rows       = lt_rows
                                                   iv_batch_uuid = mv_uuid
                                                   iv_bukrs      = ms_batch-bukrs ).
    FREE lt_rows.
    mo_engine->resolve( EXPORTING iv_bukrs = ms_batch-bukrs
                                  iv_rldnr = ms_batch-rldnr
                        CHANGING  ct_items = rt_items ).
    mo_engine->check_locks( EXPORTING iv_bukrs = ms_batch-bukrs
                            CHANGING  ct_items = rt_items ).
  ENDMETHOD.

  METHOD persist_items.
    " Replace the rows of this batch; commit every gc_doc_chunk rows.
    DELETE FROM zfi_upl_item WHERE batch_uuid = @mv_uuid.
    DATA(lv_from) = 1.
    WHILE lv_from <= lines( it_items ).
      DATA(lv_to) = lv_from + zif_fi_upl_types=>gc_doc_chunk - 1.
      DATA(lt_chunk) = VALUE zif_fi_upl_types=>tt_items( FOR <x> IN it_items FROM lv_from TO lv_to ( <x> ) ).
      INSERT zfi_upl_item FROM TABLE @lt_chunk.
      COMMIT WORK.
      lv_from = lv_to + 1.
    ENDWHILE.
    COMMIT WORK.
  ENDMETHOD.

  METHOD update_batch.
    DATA lv_ts TYPE timestampl.
    GET TIME STAMP FIELD lv_ts.
    DATA(lv_msg) = CONV zfi_upl_batch-message( iv_text ).
    IF is_counts IS SUPPLIED.
      UPDATE zfi_upl_batch SET status = @iv_status, message = @lv_msg, requested_action = @space,
             n_rows = @is_counts-rows, n_planned = @is_counts-planned, n_skipped = @is_counts-skipped,
             n_error = @is_counts-error, n_locked = @is_counts-locked, n_changed = @is_counts-changed,
             local_last_changed_by = @sy-uname, local_last_changed_at = @lv_ts, last_changed_at = @lv_ts
             WHERE batch_uuid = @mv_uuid.
    ELSE.
      UPDATE zfi_upl_batch SET status = @iv_status, message = @lv_msg, requested_action = @space,
             local_last_changed_by = @sy-uname, local_last_changed_at = @lv_ts, last_changed_at = @lv_ts
             WHERE batch_uuid = @mv_uuid.
    ENDIF.
  ENDMETHOD.

  METHOD do_validate.
    DATA(lt_items) = build_items( ).
    persist_items( lt_items ).
    DATA(ls_counts) = zcl_fi_upload_engine=>count( lt_items ).
    update_batch( iv_status = zif_fi_upl_types=>gc_batch_status-validated is_counts = ls_counts ).
    mo_log->add( iv_msgty = 'S'
                 iv_text  = zcl_fi_upl_msg=>text( iv_no = '030'
                                                  iv_v1 = |{ ls_counts-rows }|
                                                  iv_v2 = |{ ls_counts-planned }|
                                                  iv_v3 = |{ ls_counts-error }| ) ).
    mo_log->save( ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD do_post.
    check_not_posted_before( ).

    " Re-validate first: rows changed by an earlier (interrupted) run become SKIPPED_ALREADY_SET.
    DATA(lt_items) = build_items( ).
    persist_items( lt_items ).

    DATA lt_docs TYPE SORTED TABLE OF zif_fi_db_provider=>ty_doc_key WITH UNIQUE KEY belnr gjahr.
    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<p>) WHERE status = zif_fi_upl_types=>gc_item_status-planned.
      INSERT VALUE #( belnr = <p>-belnr gjahr = <p>-gjahr ) INTO TABLE lt_docs.
    ENDLOOP.

    DATA lt_chunk TYPE zif_fi_db_provider=>tt_doc_key.
    DATA(lv_idx) = 0.
    LOOP AT lt_docs ASSIGNING FIELD-SYMBOL(<d>).
      lv_idx = lv_idx + 1.
      APPEND <d> TO lt_chunk.
      IF lines( lt_chunk ) < zif_fi_upl_types=>gc_post_chunk AND lv_idx < lines( lt_docs ).
        CONTINUE.
      ENDIF.

      mo_engine->post_chunk( EXPORTING iv_bukrs = ms_batch-bukrs
                                       iv_rldnr = ms_batch-rldnr
                                       it_docs  = lt_chunk
                             CHANGING  ct_items = lt_items ).

      " Persist the rows of this chunk, log one line per document, update progress.
      DATA(lt_upd) = VALUE zif_fi_upl_types=>tt_items( ).
      LOOP AT lt_chunk ASSIGNING FIELD-SYMBOL(<c>).
        DATA(lv_logged) = abap_false.
        LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<u>) USING KEY k_doc
             WHERE belnr = <c>-belnr AND gjahr = <c>-gjahr.
          APPEND <u> TO lt_upd.
          IF lv_logged = abap_false.
            lv_logged = abap_true.
            mo_log->add( iv_msgty = COND #( WHEN <u>-status = zif_fi_upl_types=>gc_item_status-changed THEN 'S' ELSE 'E' )
                         iv_text  = |{ <u>-belnr }/{ <u>-gjahr }: { <u>-status } { <u>-message }| ).
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      MODIFY zfi_upl_item FROM TABLE @lt_upd.
      update_batch( iv_status = zif_fi_upl_types=>gc_batch_status-posting
                    is_counts = zcl_fi_upload_engine=>count( lt_items ) ).
      mo_log->save( ).
      COMMIT WORK.
      CLEAR lt_chunk.
    ENDLOOP.

    DATA(ls_counts) = zcl_fi_upload_engine=>count( lt_items ).
    update_batch( iv_status = zif_fi_upl_types=>gc_batch_status-done is_counts = ls_counts ).
    mo_log->add( iv_msgty = 'S'
                 iv_text  = zcl_fi_upl_msg=>text( iv_no = '031'
                                                  iv_v1 = |{ ls_counts-changed }|
                                                  iv_v2 = |{ ls_counts-error }| ) ).
    mo_log->save( ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD fail.
    mo_log->add( iv_msgty = 'E' iv_text = iv_text ).
    mo_log->save( ).
    update_batch( iv_status = zif_fi_upl_types=>gc_batch_status-file_error iv_text = iv_text ).
    COMMIT WORK.
  ENDMETHOD.

ENDCLASS.
