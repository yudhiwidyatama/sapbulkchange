CLASS ltd_db DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_fi_db_provider.
    DATA mt_lines TYPE zif_fi_db_provider=>tt_line.
    DATA mt_locks TYPE zif_fi_db_provider=>tt_lock.
ENDCLASS.

CLASS ltd_db IMPLEMENTATION.
  METHOD zif_fi_db_provider~read_lines.
    LOOP AT it_doc_keys ASSIGNING FIELD-SYMBOL(<k>).
      LOOP AT mt_lines ASSIGNING FIELD-SYMBOL(<l>) WHERE belnr = <k>-belnr AND gjahr = <k>-gjahr.
        INSERT <l> INTO TABLE rt_lines.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_fi_db_provider~read_locks.
    rt_locks = mt_locks.
  ENDMETHOD.
ENDCLASS.


CLASS ltd_changer DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_fi_doc_changer.
    DATA mo_db TYPE REF TO ltd_db.
    DATA mv_fail_belnr TYPE belnr_d.        " documents that fail
    DATA mv_silent_belnr TYPE belnr_d.      " documents reported OK but not changed in the DB
    DATA mt_calls TYPE STANDARD TABLE OF zif_fi_doc_changer=>ty_change WITH EMPTY KEY.
ENDCLASS.

CLASS ltd_changer IMPLEMENTATION.
  METHOD zif_fi_doc_changer~change_document.
    IF iv_belnr = mv_fail_belnr.
      rs_result = VALUE #( success = abap_false message = 'boom' ).
      RETURN.
    ENDIF.
    LOOP AT it_changes ASSIGNING FIELD-SYMBOL(<c>).
      APPEND <c> TO mt_calls.
      IF iv_belnr <> mv_silent_belnr.
        ASSIGN mo_db->mt_lines[ belnr = iv_belnr gjahr = iv_gjahr buzei = <c>-buzei ] TO FIELD-SYMBOL(<l>).
        <l>-zuonr = <c>-new_val.
      ENDIF.
    ENDLOOP.
    rs_result-success = abap_true.
  ENDMETHOD.
ENDCLASS.


CLASS ltcl_engine DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA mo_db      TYPE REF TO ltd_db.
    DATA mo_changer TYPE REF TO ltd_changer.
    DATA mo_cut     TYPE REF TO zcl_fi_upload_engine.

    METHODS setup.
    METHODS item
      IMPORTING iv_row TYPE i iv_belnr TYPE belnr_d DEFAULT '1900000001' iv_buzei TYPE buzei
                iv_blart TYPE blart DEFAULT 'SA' iv_budat TYPE budat DEFAULT '20190131'
                iv_racct TYPE racct DEFAULT '0000600000' iv_target TYPE dzuonr DEFAULT 'PRJ-NEW'
                iv_source TYPE c DEFAULT 'BEBAN'
      RETURNING VALUE(rs_item) TYPE zfi_upl_item.

    METHODS statuses       FOR TESTING.
    METHODS mismatch_text  FOR TESTING.
    METHODS locks          FOR TESTING.
    METHODS post_ok        FOR TESTING.
    METHODS post_order     FOR TESTING.
    METHODS post_failure   FOR TESTING.
    METHODS post_verify    FOR TESTING.
    METHODS counting       FOR TESTING.
ENDCLASS.


CLASS ltcl_engine IMPLEMENTATION.

  METHOD setup.
    mo_db = NEW #( ).
    mo_db->mt_lines = VALUE #(
      ( belnr = '1900000001' gjahr = '2019' buzei = '001' racct = '0000600000' blart = 'SA' budat = '20190131' zuonr = 'OLD' )
      ( belnr = '1900000001' gjahr = '2019' buzei = '002' racct = '0000600000' blart = 'SA' budat = '20190131' zuonr = 'PRJ-NEW' )
      ( belnr = '1900000001' gjahr = '2019' buzei = '003' racct = '0000700000' blart = 'SA' budat = '20190131' zuonr = 'OLD' augbl = '2000000001' )
      ( belnr = '1900000001' gjahr = '2019' buzei = '004' racct = '0000800000' blart = 'KR' budat = '20190131' zuonr = '' )
      ( belnr = '1900000002' gjahr = '2019' buzei = '001' racct = '0000600000' blart = 'SA' budat = '20190131' zuonr = '' ) ).
    mo_changer = NEW #( ).
    mo_changer->mo_db = mo_db.
    mo_cut = NEW #( io_db = mo_db io_changer = mo_changer ).
  ENDMETHOD.

  METHOD item.
    rs_item = VALUE #( row_no = iv_row bukrs = '1000' belnr = iv_belnr gjahr = '2019' buzei = iv_buzei
                       blart = iv_blart budat = iv_budat racct = iv_racct target_zuonr = iv_target
                       source_data = iv_source status = zif_fi_upl_types=>gc_item_status-new ).
  ENDMETHOD.

  METHOD statuses.
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items(
      ( item( iv_row = 2 iv_buzei = '001' ) )                       " planned (old value differs)
      ( item( iv_row = 3 iv_buzei = '002' ) )                       " already set
      ( item( iv_row = 4 iv_belnr = '1900000009' iv_buzei = '001' ) ) " document missing
      ( item( iv_row = 5 iv_buzei = '099' ) )                       " item missing
      ( item( iv_row = 6 iv_buzei = '001' iv_blart = 'KR' ) )       " doc type mismatch
      ( item( iv_row = 7 iv_buzei = '003' iv_racct = '600000' ) )   " GL mismatch (700000 in system)
      ( item( iv_row = 8 iv_buzei = '003' iv_racct = '700000' ) )   " leading zeros ignored, cleared item
      ( item( iv_row = 9 iv_buzei = '001' iv_budat = '20190201' ) ) " date mismatch
      ( item( iv_row = 10 iv_buzei = '004' iv_blart = 'KR' iv_racct = '800000' ) ) ). " empty ZUONR -> planned
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).

    cl_abap_unit_assert=>assert_equals( exp = 'PLANNED'             act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'OLD'                 act = lt_items[ 1 ]-old_zuonr ).
    cl_abap_unit_assert=>assert_equals( exp = 'SKIPPED_ALREADY_SET' act = lt_items[ 2 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'DOC_NOT_FOUND'       act = lt_items[ 3 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'ITEM_NOT_FOUND'      act = lt_items[ 4 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'VALIDATION_FAILED'   act = lt_items[ 5 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'VALIDATION_FAILED'   act = lt_items[ 6 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'PLANNED'             act = lt_items[ 7 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = '2000000001'          act = lt_items[ 7 ]-augbl ).
    cl_abap_unit_assert=>assert_not_initial( act = lt_items[ 7 ]-message msg = 'cleared-item warning' ).
    cl_abap_unit_assert=>assert_equals( exp = 'VALIDATION_FAILED'   act = lt_items[ 8 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'PLANNED'             act = lt_items[ 9 ]-status ).
  ENDMETHOD.

  METHOD mismatch_text.
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items( ( item( iv_row = 2 iv_buzei = '001' iv_blart = 'KR' iv_budat = '20190201' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = 'VALIDATION_FAILED' act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_char_cp( act = lt_items[ 1 ]-message exp = '*Document Type*' ).
    cl_abap_unit_assert=>assert_char_cp( act = lt_items[ 1 ]-message exp = '*Posting Date*' ).
  ENDMETHOD.

  METHOD locks.
    mo_db->mt_locks = VALUE #( ( belnr = '1900000002' gjahr = '2019' owner = 'JDOE' ) ).
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items(
      ( item( iv_row = 2 iv_buzei = '001' ) )
      ( item( iv_row = 3 iv_belnr = '1900000002' iv_buzei = '001' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    mo_cut->check_locks( EXPORTING iv_bukrs = '1000' CHANGING ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = 'PLANNED' act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'LOCKED'  act = lt_items[ 2 ]-status ).
    cl_abap_unit_assert=>assert_char_cp( act = lt_items[ 2 ]-message exp = '*JDOE*' ).
  ENDMETHOD.

  METHOD post_ok.
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items(
      ( item( iv_row = 2 iv_buzei = '001' ) ) ( item( iv_row = 3 iv_belnr = '1900000002' iv_buzei = '001' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    mo_cut->post_chunk( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L'
                                  it_docs = VALUE #( ( belnr = '1900000001' gjahr = '2019' ) ( belnr = '1900000002' gjahr = '2019' ) )
                        CHANGING  ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = 'CHANGED' act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'CHANGED' act = lt_items[ 2 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( mo_changer->mt_calls ) ).
  ENDMETHOD.

  METHOD post_order.
    " BEBAN lines first, VENDOR lines after, whatever the file order
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items(
      ( item( iv_row = 2 iv_buzei = '001' iv_source = 'VENDOR' ) )
      ( item( iv_row = 3 iv_buzei = '003' iv_racct = '700000' iv_source = 'BEBAN' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    mo_cut->post_chunk( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L'
                                  it_docs = VALUE #( ( belnr = '1900000001' gjahr = '2019' ) )
                        CHANGING  ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = '003' act = mo_changer->mt_calls[ 1 ]-buzei ).
    cl_abap_unit_assert=>assert_equals( exp = '001' act = mo_changer->mt_calls[ 2 ]-buzei ).
  ENDMETHOD.

  METHOD post_failure.
    mo_changer->mv_fail_belnr = '1900000001'.
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items(
      ( item( iv_row = 2 iv_buzei = '001' ) ) ( item( iv_row = 3 iv_belnr = '1900000002' iv_buzei = '001' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    mo_cut->post_chunk( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L'
                                  it_docs = VALUE #( ( belnr = '1900000001' gjahr = '2019' ) ( belnr = '1900000002' gjahr = '2019' ) )
                        CHANGING  ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = 'SEND_ERROR' act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'boom'       act = lt_items[ 1 ]-message ).
    cl_abap_unit_assert=>assert_equals( exp = 'CHANGED'    act = lt_items[ 2 ]-status msg = 'next document continues' ).
  ENDMETHOD.

  METHOD post_verify.
    mo_changer->mv_silent_belnr = '1900000001'.   " FM said OK but ZUONR is unchanged
    DATA(lt_items) = VALUE zif_fi_upl_types=>tt_items( ( item( iv_row = 2 iv_buzei = '001' ) ) ).
    mo_cut->resolve( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L' CHANGING ct_items = lt_items ).
    mo_cut->post_chunk( EXPORTING iv_bukrs = '1000' iv_rldnr = '0L'
                                  it_docs = VALUE #( ( belnr = '1900000001' gjahr = '2019' ) )
                        CHANGING  ct_items = lt_items ).
    cl_abap_unit_assert=>assert_equals( exp = 'NOT_CHANGED' act = lt_items[ 1 ]-status ).
  ENDMETHOD.

  METHOD counting.
    DATA(ls_c) = zcl_fi_upload_engine=>count( VALUE #(
      ( status = 'PLANNED' ) ( status = 'SKIPPED_ALREADY_SET' ) ( status = 'LOCKED' ) ( status = 'CHANGED' )
      ( status = 'EXCEL_ERROR' ) ( status = 'DOC_NOT_FOUND' ) ( status = 'NOT_CHANGED' ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 7 act = ls_c-rows ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_c-planned ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_c-skipped ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_c-locked ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_c-changed ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = ls_c-error ).
  ENDMETHOD.

ENDCLASS.
