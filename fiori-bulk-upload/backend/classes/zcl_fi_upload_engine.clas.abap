" Resolution (ACDOCA), lock check and posting orchestration. No direct DB/FM access:
" everything external goes through zif_fi_db_provider / zif_fi_doc_changer (ABAP Unit doubles).
CLASS zcl_fi_upload_engine DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_db      TYPE REF TO zif_fi_db_provider
                io_changer TYPE REF TO zif_fi_doc_changer OPTIONAL.

    " Status of every NEW row: DOC_NOT_FOUND, ITEM_NOT_FOUND, VALIDATION_FAILED,
    " SKIPPED_ALREADY_SET or PLANNED (warning text for cleared items).
    METHODS resolve
      IMPORTING iv_bukrs TYPE bukrs
                iv_rldnr TYPE fins_ledger
      CHANGING  ct_items TYPE zif_fi_upl_types=>tt_items.

    " PLANNED rows whose document is currently locked become LOCKED.
    METHODS check_locks
      IMPORTING iv_bukrs TYPE bukrs
      CHANGING  ct_items TYPE zif_fi_upl_types=>tt_items.

    " Changes the given documents (one LUW each) and verifies the result:
    " PLANNED -> CHANGED / NOT_CHANGED / SEND_ERROR.
    METHODS post_chunk
      IMPORTING iv_bukrs TYPE bukrs
                iv_rldnr TYPE fins_ledger
                it_docs  TYPE zif_fi_db_provider=>tt_doc_key
      CHANGING  ct_items TYPE zif_fi_upl_types=>tt_items.

    CLASS-METHODS count
      IMPORTING it_items         TYPE zif_fi_upl_types=>tt_items
      RETURNING VALUE(rs_counts) TYPE zif_fi_upl_types=>ty_counts.

  PRIVATE SECTION.
    DATA mo_db      TYPE REF TO zif_fi_db_provider.
    DATA mo_changer TYPE REF TO zif_fi_doc_changer.

    CLASS-METHODS set_status
      IMPORTING iv_status TYPE zfi_upl_item-status
                iv_field  TYPE string OPTIONAL
                iv_text   TYPE string OPTIONAL
      CHANGING  cs_item   TYPE zfi_upl_item.

ENDCLASS.


CLASS zcl_fi_upload_engine IMPLEMENTATION.

  METHOD constructor.
    mo_db      = io_db.
    mo_changer = io_changer.
  ENDMETHOD.

  METHOD set_status.
    cs_item-status      = iv_status.
    cs_item-error_field = iv_field.
    cs_item-message     = iv_text.
  ENDMETHOD.

  METHOD resolve.
    DATA lt_keys TYPE zif_fi_db_provider=>tt_doc_key.
    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<k>) WHERE status = zif_fi_upl_types=>gc_item_status-new.
      APPEND VALUE #( belnr = <k>-belnr gjahr = <k>-gjahr ) TO lt_keys.
    ENDLOOP.
    SORT lt_keys BY belnr gjahr.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING belnr gjahr.

    DATA(lt_lines) = mo_db->read_lines( iv_bukrs    = iv_bukrs
                                        iv_rldnr    = iv_rldnr
                                        it_doc_keys = lt_keys ).

    DATA lt_diff TYPE string_table.
    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<i>) WHERE status = zif_fi_upl_types=>gc_item_status-new.

      IF NOT line_exists( lt_lines[ belnr = <i>-belnr gjahr = <i>-gjahr ] ).
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-doc_not_found
                              iv_field  = `Document Number`
                              iv_text   = zcl_fi_upl_msg=>text( iv_no = '015' iv_v1 = <i>-belnr iv_v2 = <i>-gjahr iv_v3 = iv_bukrs )
                    CHANGING  cs_item   = <i> ).
        CONTINUE.
      ENDIF.

      ASSIGN lt_lines[ belnr = <i>-belnr gjahr = <i>-gjahr buzei = <i>-buzei ] TO FIELD-SYMBOL(<l>).
      IF sy-subrc <> 0.
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-item_not_found
                              iv_field  = `Line Item`
                              iv_text   = zcl_fi_upl_msg=>text( iv_no = '016' iv_v1 = <i>-buzei iv_v2 = <i>-belnr iv_v3 = <i>-gjahr )
                    CHANGING  cs_item   = <i> ).
        CONTINUE.
      ENDIF.

      <i>-old_zuonr = <l>-zuonr.
      <i>-augbl     = <l>-augbl.

      " Document type, posting date and G/L account must match the system line.
      CLEAR lt_diff.
      IF to_upper( condense( CONV string( <i>-blart ) ) ) <> to_upper( condense( CONV string( <l>-blart ) ) ).
        APPEND |Document Type (file { <i>-blart } / system { <l>-blart })| TO lt_diff.
      ENDIF.
      IF <i>-budat <> <l>-budat.
        APPEND |Posting Date (file { <i>-budat } / system { <l>-budat })| TO lt_diff.
      ENDIF.
      DATA(lv_file_gl) = shift_left( val = CONV string( <i>-racct ) sub = '0' ).
      DATA(lv_sys_gl)  = shift_left( val = CONV string( <l>-racct ) sub = '0' ).
      IF lv_file_gl <> lv_sys_gl.
        APPEND |G/L Account (file { lv_file_gl } / system { lv_sys_gl })| TO lt_diff.
      ENDIF.

      IF lt_diff IS NOT INITIAL.
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-validation_failed
                              iv_field  = `Doc Type / Date / G/L`
                              iv_text   = zcl_fi_upl_msg=>text( iv_no = '017'
                                            iv_v1 = VALUE string( lt_diff[ 1 ] OPTIONAL )
                                            iv_v2 = VALUE string( lt_diff[ 2 ] OPTIONAL )
                                            iv_v3 = VALUE string( lt_diff[ 3 ] OPTIONAL ) )
                    CHANGING  cs_item   = <i> ).
        CONTINUE.
      ENDIF.

      IF <l>-zuonr = <i>-target_zuonr.
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-skipped
                              iv_text   = zcl_fi_upl_msg=>text( '020' )
                    CHANGING  cs_item   = <i> ).
      ELSE.
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-planned
                              iv_text   = COND string( WHEN <l>-augbl IS NOT INITIAL
                                                       THEN zcl_fi_upl_msg=>text( iv_no = '018' iv_v1 = <l>-augbl ) )
                    CHANGING  cs_item   = <i> ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_locks.
    DATA(lt_locks) = mo_db->read_locks( iv_bukrs ).
    IF lt_locks IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<i>) WHERE status = zif_fi_upl_types=>gc_item_status-planned.
      ASSIGN lt_locks[ belnr = <i>-belnr gjahr = <i>-gjahr ] TO FIELD-SYMBOL(<lock>).
      IF sy-subrc = 0.
        set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-locked
                              iv_field  = `Document Number`
                              iv_text   = zcl_fi_upl_msg=>text( iv_no = '019' iv_v1 = <lock>-owner )
                    CHANGING  cs_item   = <i> ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD post_chunk.
    DATA lt_sent TYPE zif_fi_db_provider=>tt_doc_key.

    LOOP AT it_docs ASSIGNING FIELD-SYMBOL(<d>).
      DATA(lt_changes) = VALUE zif_fi_doc_changer=>tt_change( ).
      LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<p>) USING KEY k_doc
           WHERE belnr = <d>-belnr AND gjahr = <d>-gjahr
             AND status = zif_fi_upl_types=>gc_item_status-planned.
        APPEND VALUE #( buzei = <p>-buzei source = <p>-source_data
                        old_val = <p>-old_zuonr new_val = <p>-target_zuonr ) TO lt_changes.
      ENDLOOP.
      IF lt_changes IS INITIAL.
        CONTINUE.
      ENDIF.
      SORT lt_changes STABLE BY source.   " BEBAN before VENDOR

      DATA(ls_result) = mo_changer->change_document( iv_bukrs   = iv_bukrs
                                                     iv_belnr   = <d>-belnr
                                                     iv_gjahr   = <d>-gjahr
                                                     it_changes = lt_changes ).
      IF ls_result-success = abap_true.
        APPEND <d> TO lt_sent.
      ELSE.
        LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<e>) USING KEY k_doc
             WHERE belnr = <d>-belnr AND gjahr = <d>-gjahr
               AND status = zif_fi_upl_types=>gc_item_status-planned.
          set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-send_error
                                iv_field  = `KODE PROJECT`
                                iv_text   = ls_result-message
                      CHANGING  cs_item   = <e> ).
        ENDLOOP.
      ENDIF.
    ENDLOOP.

    IF lt_sent IS INITIAL.
      RETURN.
    ENDIF.

    " Post-commit verification: re-read ACDOCA and compare ZUONR with the target.
    DATA(lt_lines) = mo_db->read_lines( iv_bukrs    = iv_bukrs
                                        iv_rldnr    = iv_rldnr
                                        it_doc_keys = lt_sent ).
    LOOP AT lt_sent ASSIGNING FIELD-SYMBOL(<s>).
      LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<v>) USING KEY k_doc
           WHERE belnr = <s>-belnr AND gjahr = <s>-gjahr
             AND status = zif_fi_upl_types=>gc_item_status-planned.
        ASSIGN lt_lines[ belnr = <v>-belnr gjahr = <v>-gjahr buzei = <v>-buzei ] TO FIELD-SYMBOL(<l>).
        DATA(lv_found) = xsdbool( sy-subrc = 0 ).
        IF lv_found = abap_true AND <l>-zuonr = <v>-target_zuonr.
          set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-changed
                                iv_text   = zcl_fi_upl_msg=>text( '021' )
                      CHANGING  cs_item   = <v> ).
        ELSE.
          set_status( EXPORTING iv_status = zif_fi_upl_types=>gc_item_status-not_changed
                                iv_field  = `KODE PROJECT`
                                iv_text   = zcl_fi_upl_msg=>text( iv_no = '023'
                                              iv_v1 = COND string( WHEN lv_found = abap_true THEN <l>-zuonr ) )
                      CHANGING  cs_item   = <v> ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD count.
    rs_counts-rows = lines( it_items ).
    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<i>).
      CASE <i>-status.
        WHEN zif_fi_upl_types=>gc_item_status-planned.
          rs_counts-planned = rs_counts-planned + 1.
        WHEN zif_fi_upl_types=>gc_item_status-skipped.
          rs_counts-skipped = rs_counts-skipped + 1.
        WHEN zif_fi_upl_types=>gc_item_status-locked.
          rs_counts-locked = rs_counts-locked + 1.
        WHEN zif_fi_upl_types=>gc_item_status-changed.
          rs_counts-changed = rs_counts-changed + 1.
        WHEN zif_fi_upl_types=>gc_item_status-excel_error
          OR zif_fi_upl_types=>gc_item_status-doc_not_found
          OR zif_fi_upl_types=>gc_item_status-item_not_found
          OR zif_fi_upl_types=>gc_item_status-validation_failed
          OR zif_fi_upl_types=>gc_item_status-send_error
          OR zif_fi_upl_types=>gc_item_status-not_changed.
          rs_counts-error = rs_counts-error + 1.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
