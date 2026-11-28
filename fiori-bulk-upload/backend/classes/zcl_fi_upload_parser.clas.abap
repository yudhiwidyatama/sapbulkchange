" Converts sheet rows into ZFI_UPL_ITEM rows (no database access).
" Row-level rules of design section 4: mandatory, data type, length, source value, duplicates.
CLASS zcl_fi_upload_parser DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_max_rows TYPE i DEFAULT zif_fi_upl_types=>gc_max_rows.

    METHODS parse
      IMPORTING it_rows         TYPE zcl_fi_xlsx_reader=>tt_rows
                iv_batch_uuid   TYPE sysuuid_x16
                iv_bukrs        TYPE bukrs
      RETURNING VALUE(rt_items) TYPE zif_fi_upl_types=>tt_items
      RAISING   zcx_fi_upload.

    " Excel serial (43496), YYYYMMDD, YYYY-MM-DD, DD.MM.YYYY, DD/MM/YYYY; initial if invalid.
    CLASS-METHODS parse_excel_date
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_date) TYPE d.

    " '1' -> '001', '1.0' -> '001', '1E3' -> '1000'; empty if not a non-negative integer or too long.
    CLASS-METHODS normalize_numc
      IMPORTING iv_text        TYPE csequence
                iv_len         TYPE i
      RETURNING VALUE(rv_numc) TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_cols,
             belnr  TYPE i,
             gjahr  TYPE i,
             buzei  TYPE i,
             blart  TYPE i,
             budat  TYPE i,
             racct  TYPE i,
             target TYPE i,
             source TYPE i,
           END OF ty_cols.
    TYPES: BEGIN OF ty_seen,
             dockey TYPE string,
             row_no TYPE i,
           END OF ty_seen.

    DATA mv_max_rows TYPE i.

    METHODS map_header
      IMPORTING it_cells       TYPE zcl_fi_xlsx_reader=>tt_cells
      RETURNING VALUE(rs_cols) TYPE ty_cols
      RAISING   zcx_fi_upload.

    METHODS cell
      IMPORTING it_cells        TYPE zcl_fi_xlsx_reader=>tt_cells
                iv_col          TYPE i
      RETURNING VALUE(rv_value) TYPE string.

    METHODS set_error
      IMPORTING iv_field TYPE csequence
                iv_msgno TYPE symsgno
                iv_v1    TYPE csequence OPTIONAL
      CHANGING  cs_item  TYPE zfi_upl_item.

    CLASS-METHODS header_key
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_key) TYPE string.

    CLASS-METHODS valid_date
      IMPORTING iv_date      TYPE d
      RETURNING VALUE(rv_ok) TYPE abap_bool.

ENDCLASS.


CLASS zcl_fi_upload_parser IMPLEMENTATION.

  METHOD constructor.
    mv_max_rows = iv_max_rows.
  ENDMETHOD.

  METHOD header_key.
    rv_key = to_lower( condense( iv_text ) ).
    REPLACE ALL OCCURRENCES OF ` ` IN rv_key WITH ``.
    REPLACE ALL OCCURRENCES OF `.` IN rv_key WITH ``.
  ENDMETHOD.

  METHOD map_header.
    LOOP AT it_cells ASSIGNING FIELD-SYMBOL(<cell>).
      DATA(lv_idx) = sy-tabix.
      CASE header_key( <cell> ).
        WHEN 'documentnumber' OR 'docnumber' OR 'docno' OR 'documentno' OR 'belnr'.
          IF rs_cols-belnr = 0. rs_cols-belnr = lv_idx. ENDIF.
        WHEN 'fiscalyear' OR 'year' OR 'gjahr'.
          IF rs_cols-gjahr = 0. rs_cols-gjahr = lv_idx. ENDIF.
        WHEN 'buzei' OR 'lineitem' OR 'item' OR 'itm' OR 'lineitemno' OR 'docitem'.
          IF rs_cols-buzei = 0. rs_cols-buzei = lv_idx. ENDIF.
        WHEN 'documenttype' OR 'doctype' OR 'type' OR 'blart'.
          IF rs_cols-blart = 0. rs_cols-blart = lv_idx. ENDIF.
        WHEN 'postingdate' OR 'postdate' OR 'pstngdate' OR 'budat'.
          IF rs_cols-budat = 0. rs_cols-budat = lv_idx. ENDIF.
        WHEN 'g/laccount' OR 'g/l' OR 'glaccount' OR 'hkont' OR 'racct'.
          IF rs_cols-racct = 0. rs_cols-racct = lv_idx. ENDIF.
        WHEN 'kodeproject'.
          IF rs_cols-target = 0. rs_cols-target = lv_idx. ENDIF.
        WHEN 'sourcedata'.
          IF rs_cols-source = 0. rs_cols-source = lv_idx. ENDIF.
      ENDCASE.
    ENDLOOP.

    DATA lt_missing TYPE string_table.
    IF rs_cols-belnr  = 0. APPEND `Document Number` TO lt_missing. ENDIF.
    IF rs_cols-buzei  = 0. APPEND `Line Item`       TO lt_missing. ENDIF.
    IF rs_cols-blart  = 0. APPEND `Document Type`   TO lt_missing. ENDIF.
    IF rs_cols-budat  = 0. APPEND `Posting Date`    TO lt_missing. ENDIF.
    IF rs_cols-racct  = 0. APPEND `G/L Account`     TO lt_missing. ENDIF.
    IF rs_cols-target = 0. APPEND `KODE PROJECT`    TO lt_missing. ENDIF.
    IF lt_missing IS NOT INITIAL.
      DATA(lv_list) = concat_lines_of( table = lt_missing sep = `, ` ).
      DATA(lv_len)  = strlen( lv_list ).
      RAISE EXCEPTION NEW zcx_fi_upload(
        msgno = '002'
        msgv1 = substring( val = lv_list len = nmin( val1 = 50 val2 = lv_len ) )
        msgv2 = COND string( WHEN lv_len > 50 THEN substring( val = lv_list off = 50 ) ) ).
    ENDIF.
  ENDMETHOD.

  METHOD cell.
    IF iv_col = 0 OR iv_col > lines( it_cells ).
      RETURN.
    ENDIF.
    rv_value = condense( it_cells[ iv_col ] ).
  ENDMETHOD.

  METHOD set_error.
    IF cs_item-status <> zif_fi_upl_types=>gc_item_status-new.
      RETURN.   " keep the first error of the row
    ENDIF.
    cs_item-status      = zif_fi_upl_types=>gc_item_status-excel_error.
    cs_item-error_field = iv_field.
    cs_item-message     = zcl_fi_upl_msg=>text( iv_no = iv_msgno iv_v1 = COND #( WHEN iv_v1 IS SUPPLIED THEN iv_v1 ELSE iv_field ) ).
  ENDMETHOD.

  METHOD normalize_numc.
    DATA(lv_text) = condense( CONV string( iv_text ) ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.
    IF lv_text CA 'Ee'.
      TRY.
          DATA(lv_dec) = CONV decfloat34( lv_text ).
          lv_text = |{ lv_dec DECIMALS = 0 }|.
        CATCH cx_sy_conversion_error.
          RETURN.
      ENDTRY.
    ELSEIF lv_text CS '.'.
      IF matches( val = lv_text regex = '\d+\.0*' ).
        lv_text = substring_before( val = lv_text sub = '.' ).
      ELSE.
        RETURN.
      ENDIF.
    ENDIF.
    IF lv_text IS INITIAL OR lv_text CN '0123456789'.
      RETURN.
    ENDIF.
    SHIFT lv_text LEFT DELETING LEADING '0'.
    IF lv_text IS INITIAL.
      lv_text = '0'.
    ENDIF.
    IF strlen( lv_text ) > iv_len.
      RETURN.
    ENDIF.
    rv_numc = |{ lv_text WIDTH = iv_len ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD valid_date.
    IF iv_date IS INITIAL OR iv_date(4) < '1900' OR iv_date(4) > '2999'
       OR iv_date+4(2) NOT BETWEEN '01' AND '12' OR iv_date+6(2) = '00'.
      RETURN.
    ENDIF.
    DATA(lv_first) = CONV d( |{ iv_date(6) }01| ).
    DATA(lv_next)  = lv_first + 31.
    lv_next+6(2) = '01'.
    DATA(lv_last) = lv_next - 1.
    rv_ok = xsdbool( iv_date+6(2) <= lv_last+6(2) ).
  ENDMETHOD.

  METHOD parse_excel_date.
    DATA(lv_text) = condense( CONV string( iv_text ) ).
    DATA lv_date TYPE d.
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.
    IF matches( val = lv_text regex = '\d+(\.0+)?' ).
      DATA(lv_int) = substring_before( val = |{ lv_text }.| sub = '.' ).
      IF strlen( lv_int ) = 8.
        lv_date = lv_int.
      ELSEIF strlen( lv_int ) <= 7.
        DATA(lv_serial) = CONV i( lv_int ).
        IF lv_serial >= 1.
          lv_date = '18991230'.
          lv_date = lv_date + lv_serial.
        ENDIF.
      ENDIF.
    ELSEIF matches( val = lv_text regex = '\d{4}-\d{2}-\d{2}' ).
      lv_date = |{ lv_text(4) }{ lv_text+5(2) }{ lv_text+8(2) }|.
    ELSEIF matches( val = lv_text regex = '\d{2}[./]\d{2}[./]\d{4}' ).
      lv_date = |{ lv_text+6(4) }{ lv_text+3(2) }{ lv_text(2) }|.
    ENDIF.
    IF valid_date( lv_date ) = abap_true.
      rv_date = lv_date.
    ENDIF.
  ENDMETHOD.

  METHOD parse.
    IF lines( it_rows ) = 0.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '027' ).
    ENDIF.
    IF lines( it_rows ) - 1 > mv_max_rows.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '003' msgv1 = |{ mv_max_rows }| ).
    ENDIF.

    DATA(ls_cols) = map_header( it_rows[ 1 ]-cells ).
    DATA lt_seen TYPE HASHED TABLE OF ty_seen WITH UNIQUE KEY dockey.

    LOOP AT it_rows ASSIGNING FIELD-SYMBOL(<row>) FROM 2.
      DATA(lv_belnr_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-belnr ).
      DATA(lv_gjahr_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-gjahr ).
      DATA(lv_buzei_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-buzei ).
      DATA(lv_blart_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-blart ).
      DATA(lv_budat_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-budat ).
      DATA(lv_racct_txt)  = cell( it_cells = <row>-cells iv_col = ls_cols-racct ).
      DATA(lv_target_txt) = cell( it_cells = <row>-cells iv_col = ls_cols-target ).
      DATA(lv_source_txt) = cell( it_cells = <row>-cells iv_col = ls_cols-source ).

      IF lv_belnr_txt IS INITIAL AND lv_gjahr_txt IS INITIAL AND lv_buzei_txt IS INITIAL
         AND lv_blart_txt IS INITIAL AND lv_budat_txt IS INITIAL AND lv_racct_txt IS INITIAL
         AND lv_target_txt IS INITIAL.
        CONTINUE.   " blank row
      ENDIF.

      DATA(ls_item) = VALUE zfi_upl_item( batch_uuid = iv_batch_uuid
                                          row_no     = <row>-row_no
                                          bukrs      = iv_bukrs
                                          status     = zif_fi_upl_types=>gc_item_status-new ).

      " Document number
      DATA(lv_belnr) = normalize_numc( iv_text = lv_belnr_txt iv_len = 10 ).
      IF lv_belnr IS INITIAL OR lv_belnr CO '0'.
        set_error( EXPORTING iv_field = 'Document Number' iv_msgno = '007' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-belnr = lv_belnr.
      ENDIF.

      " Posting date (needed before the fiscal year default)
      DATA(lv_budat) = parse_excel_date( lv_budat_txt ).
      IF lv_budat IS INITIAL.
        set_error( EXPORTING iv_field = 'Posting Date' iv_msgno = '010' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-budat = lv_budat.
      ENDIF.

      " Fiscal year (defaults to the year of the posting date)
      IF lv_gjahr_txt IS NOT INITIAL.
        DATA(lv_gjahr) = normalize_numc( iv_text = lv_gjahr_txt iv_len = 4 ).
        IF lv_gjahr IS INITIAL OR lv_gjahr = '0000'.
          set_error( EXPORTING iv_field = 'Fiscal Year' iv_msgno = '008' CHANGING cs_item = ls_item ).
        ELSE.
          ls_item-gjahr = lv_gjahr.
        ENDIF.
      ELSEIF lv_budat IS NOT INITIAL.
        ls_item-gjahr = lv_budat(4).
      ELSE.
        set_error( EXPORTING iv_field = 'Fiscal Year' iv_msgno = '008' CHANGING cs_item = ls_item ).
      ENDIF.

      " Line item 1..999
      DATA(lv_buzei) = normalize_numc( iv_text = lv_buzei_txt iv_len = 3 ).
      IF lv_buzei IS INITIAL OR lv_buzei = '000'.
        set_error( EXPORTING iv_field = 'Line Item' iv_msgno = '009' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-buzei = lv_buzei.
      ENDIF.

      " Document type, G/L account
      IF lv_blart_txt IS INITIAL OR strlen( lv_blart_txt ) > 4.
        set_error( EXPORTING iv_field = 'Document Type' iv_msgno = '011' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-blart = to_upper( lv_blart_txt ).
      ENDIF.
      IF lv_racct_txt IS INITIAL OR strlen( lv_racct_txt ) > 10.
        set_error( EXPORTING iv_field = 'G/L Account' iv_msgno = '011' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-racct = lv_racct_txt.
      ENDIF.

      " Target assignment (ZUONR is CHAR 18)
      IF lv_target_txt IS INITIAL.
        set_error( EXPORTING iv_field = 'KODE PROJECT' iv_msgno = '011' CHANGING cs_item = ls_item ).
      ELSEIF strlen( lv_target_txt ) > 18.
        set_error( EXPORTING iv_field = 'KODE PROJECT' iv_msgno = '012' CHANGING cs_item = ls_item ).
      ELSE.
        ls_item-target_zuonr = lv_target_txt.
      ENDIF.

      " Source data: BEBAN (default) or VENDOR
      IF lv_source_txt IS INITIAL.
        ls_item-source_data = zif_fi_upl_types=>gc_source_beban.
      ELSE.
        DATA(lv_source) = to_upper( lv_source_txt ).
        IF lv_source = zif_fi_upl_types=>gc_source_beban OR lv_source = zif_fi_upl_types=>gc_source_vendor.
          ls_item-source_data = lv_source.
        ELSE.
          set_error( EXPORTING iv_field = 'Source Data' iv_msgno = '013' CHANGING cs_item = ls_item ).
        ENDIF.
      ENDIF.

      " Duplicate (document, year, line item) within the file
      IF ls_item-status = zif_fi_upl_types=>gc_item_status-new.
        DATA(lv_key) = |{ ls_item-belnr }{ ls_item-gjahr }{ ls_item-buzei }|.
        READ TABLE lt_seen ASSIGNING FIELD-SYMBOL(<seen>) WITH TABLE KEY dockey = lv_key.
        IF sy-subrc = 0.
          set_error( EXPORTING iv_field = 'Line Item' iv_msgno = '014' iv_v1 = |{ <seen>-row_no }|
                     CHANGING cs_item = ls_item ).
        ELSE.
          INSERT VALUE #( dockey = lv_key row_no = <row>-row_no ) INTO TABLE lt_seen.
        ENDIF.
      ENDIF.

      APPEND ls_item TO rt_items.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
