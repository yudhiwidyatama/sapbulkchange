" Server-side OpenXML (.xlsx) reader: CL_ABAP_ZIP + sXML. No OLE/frontend dependency.
" Handles shared strings (incl. rich text, phonetic runs ignored), inline strings,
" formula strings, numerics and sparse rows (column taken from the A1 reference).
" Rows without any non-empty cell are dropped.
CLASS zcl_fi_xlsx_reader DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_cells TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    TYPES: BEGIN OF ty_row,
             row_no TYPE i,
             cells  TYPE tt_cells,
           END OF ty_row,
           tt_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    CLASS-METHODS parse
      IMPORTING iv_xlsx        TYPE xstring
      RETURNING VALUE(rt_rows) TYPE tt_rows
      RAISING   zcx_fi_upload.

    " 'A' -> 1, 'Z' -> 26, 'AA' -> 27; stops at the first non-letter (so 'AA12' -> 27).
    CLASS-METHODS col_letters_to_index
      IMPORTING iv_letters      TYPE csequence
      RETURNING VALUE(rv_index) TYPE i.

  PRIVATE SECTION.
    CLASS-METHODS get_part
      IMPORTING io_zip            TYPE REF TO cl_abap_zip
                iv_name           TYPE string
      RETURNING VALUE(rv_content) TYPE xstring.

    CLASS-METHODS first_sheet_path
      IMPORTING io_zip         TYPE REF TO cl_abap_zip
      RETURNING VALUE(rv_path) TYPE string.

    CLASS-METHODS read_shared_strings
      IMPORTING io_zip            TYPE REF TO cl_abap_zip
      RETURNING VALUE(rt_strings) TYPE string_table
      RAISING   cx_sxml_error.

    CLASS-METHODS read_sheet
      IMPORTING iv_xml         TYPE xstring
                it_shared      TYPE string_table
      RETURNING VALUE(rt_rows) TYPE tt_rows
      RAISING   cx_sxml_error.

    CLASS-METHODS attr
      IMPORTING io_open         TYPE REF TO if_sxml_open_element
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

ENDCLASS.


CLASS zcl_fi_xlsx_reader IMPLEMENTATION.

  METHOD parse.
    DATA(lo_zip) = NEW cl_abap_zip( ).
    lo_zip->load( EXPORTING zip = iv_xlsx
                  EXCEPTIONS zip_parse_error = 1
                             OTHERS          = 2 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '001' ).
    ENDIF.

    DATA(lv_sheet) = get_part( io_zip = lo_zip iv_name = first_sheet_path( lo_zip ) ).
    IF lv_sheet IS INITIAL.
      RAISE EXCEPTION NEW zcx_fi_upload( msgno = '001' ).
    ENDIF.

    TRY.
        rt_rows = read_sheet( iv_xml    = lv_sheet
                              it_shared = read_shared_strings( lo_zip ) ).
      CATCH cx_sxml_error INTO DATA(lx_sxml).
        RAISE EXCEPTION NEW zcx_fi_upload( msgno = '001' previous = lx_sxml ).
    ENDTRY.
  ENDMETHOD.

  METHOD col_letters_to_index.
    DATA(lv_letters) = to_upper( CONV string( iv_letters ) ).
    DO strlen( lv_letters ) TIMES.
      DATA(lv_off) = sy-index - 1.
      DATA(lv_ch)  = lv_letters+lv_off(1).
      IF lv_ch < 'A' OR lv_ch > 'Z'.
        EXIT.
      ENDIF.
      rv_index = rv_index * 26 + find( val = sy-abcde sub = lv_ch ) + 1.
    ENDDO.
  ENDMETHOD.

  METHOD get_part.
    io_zip->get( EXPORTING name = iv_name
                 IMPORTING content = rv_content
                 EXCEPTIONS zip_index_error         = 1
                            zip_decompression_error = 2
                            OTHERS                  = 3 ).
    IF sy-subrc <> 0.
      CLEAR rv_content.
    ENDIF.
  ENDMETHOD.

  METHOD attr.
    LOOP AT io_open->get_attributes( ) INTO DATA(lo_attr).
      IF lo_attr->qname-name = iv_name.
        rv_value = lo_attr->get_value( ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD first_sheet_path.
    rv_path = `xl/worksheets/sheet1.xml`.   " fallback
    DATA(lv_wb)   = get_part( io_zip = io_zip iv_name = `xl/workbook.xml` ).
    DATA(lv_rels) = get_part( io_zip = io_zip iv_name = `xl/_rels/workbook.xml.rels` ).
    IF lv_wb IS INITIAL OR lv_rels IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_rid TYPE string.
    TRY.
        DATA(lo_wb) = cl_sxml_string_reader=>create( lv_wb ).
        DO.
          DATA(lo_node) = lo_wb->read_next_node( ).
          IF lo_node IS INITIAL.
            EXIT.
          ENDIF.
          IF lo_node->type = if_sxml_node=>co_nt_element_open.
            DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
            IF lo_open->qname-name = 'sheet'.
              lv_rid = attr( io_open = lo_open iv_name = 'id' ).   " r:id
              EXIT.
            ENDIF.
          ENDIF.
        ENDDO.
        IF lv_rid IS INITIAL.
          RETURN.
        ENDIF.

        DATA(lo_rels) = cl_sxml_string_reader=>create( lv_rels ).
        DO.
          DATA(lo_rnode) = lo_rels->read_next_node( ).
          IF lo_rnode IS INITIAL.
            EXIT.
          ENDIF.
          IF lo_rnode->type = if_sxml_node=>co_nt_element_open.
            DATA(lo_ropen) = CAST if_sxml_open_element( lo_rnode ).
            IF lo_ropen->qname-name = 'Relationship' AND attr( io_open = lo_ropen iv_name = 'Id' ) = lv_rid.
              DATA(lv_target) = attr( io_open = lo_ropen iv_name = 'Target' ).
              IF lv_target IS NOT INITIAL.
                IF lv_target(1) = '/'.
                  rv_path = substring( val = lv_target off = 1 ).
                ELSE.
                  rv_path = |xl/{ lv_target }|.
                ENDIF.
              ENDIF.
              EXIT.
            ENDIF.
          ENDIF.
        ENDDO.
      CATCH cx_sxml_error.
        RETURN.   " keep fallback path
    ENDTRY.
  ENDMETHOD.

  METHOD read_shared_strings.
    DATA(lv_xml) = get_part( io_zip = io_zip iv_name = `xl/sharedStrings.xml` ).
    IF lv_xml IS INITIAL.
      RETURN.
    ENDIF.

    DATA: lv_cur   TYPE string,
          lv_in_si TYPE abap_bool,
          lv_in_t  TYPE abap_bool,
          lv_in_ph TYPE abap_bool.

    DATA(lo_reader) = cl_sxml_string_reader=>create( lv_xml ).
    DO.
      DATA(lo_node) = lo_reader->read_next_node( ).
      IF lo_node IS INITIAL.
        EXIT.
      ENDIF.
      CASE lo_node->type.
        WHEN if_sxml_node=>co_nt_element_open.
          DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
          CASE lo_open->qname-name.
            WHEN 'si'.
              CLEAR lv_cur.
              lv_in_si = abap_true.
            WHEN 'rPh'.
              lv_in_ph = abap_true.
            WHEN 't'.
              IF lv_in_si = abap_true AND lv_in_ph = abap_false.
                lv_in_t = abap_true.
              ENDIF.
          ENDCASE.
        WHEN if_sxml_node=>co_nt_value.
          IF lv_in_t = abap_true.
            lv_cur = lv_cur && CAST if_sxml_value_node( lo_node )->get_value( ).
          ENDIF.
        WHEN if_sxml_node=>co_nt_element_close.
          DATA(lo_close) = CAST if_sxml_close_element( lo_node ).
          CASE lo_close->qname-name.
            WHEN 't'.
              lv_in_t = abap_false.
            WHEN 'rPh'.
              lv_in_ph = abap_false.
            WHEN 'si'.
              APPEND lv_cur TO rt_strings.
              lv_in_si = abap_false.
          ENDCASE.
      ENDCASE.
    ENDDO.
  ENDMETHOD.

  METHOD read_sheet.
    DATA: ls_row   TYPE ty_row,
          lv_col   TYPE i,
          lv_type  TYPE string,
          lv_text  TYPE string,
          lv_in_v  TYPE abap_bool,
          lv_in_is TYPE abap_bool,
          lv_in_t  TYPE abap_bool,
          lv_has   TYPE abap_bool.

    DATA(lo_reader) = cl_sxml_string_reader=>create( iv_xml ).
    DO.
      DATA(lo_node) = lo_reader->read_next_node( ).
      IF lo_node IS INITIAL.
        EXIT.
      ENDIF.
      CASE lo_node->type.
        WHEN if_sxml_node=>co_nt_element_open.
          DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
          CASE lo_open->qname-name.
            WHEN 'row'.
              CLEAR: ls_row, lv_has.
              ls_row-row_no = lines( rt_rows ) + 1.   " fallback when r is missing
              DATA(lv_r) = attr( io_open = lo_open iv_name = 'r' ).
              IF lv_r CO '0123456789' AND lv_r IS NOT INITIAL.
                ls_row-row_no = CONV i( lv_r ).
              ENDIF.
            WHEN 'c'.
              lv_col  = col_letters_to_index( attr( io_open = lo_open iv_name = 'r' ) ).
              lv_type = attr( io_open = lo_open iv_name = 't' ).
              CLEAR lv_text.
            WHEN 'v'.
              lv_in_v = abap_true.
            WHEN 'is'.
              lv_in_is = abap_true.
            WHEN 't'.
              IF lv_in_is = abap_true.
                lv_in_t = abap_true.
              ENDIF.
          ENDCASE.

        WHEN if_sxml_node=>co_nt_value.
          IF lv_in_v = abap_true OR lv_in_t = abap_true.
            lv_text = lv_text && CAST if_sxml_value_node( lo_node )->get_value( ).
          ENDIF.

        WHEN if_sxml_node=>co_nt_element_close.
          DATA(lo_close) = CAST if_sxml_close_element( lo_node ).
          CASE lo_close->qname-name.
            WHEN 'v'.
              lv_in_v = abap_false.
            WHEN 't'.
              lv_in_t = abap_false.
            WHEN 'is'.
              lv_in_is = abap_false.
            WHEN 'c'.
              IF lv_type = 's'.
                TRY.
                    DATA(lv_idx) = CONV i( lv_text ) + 1.
                    lv_text = VALUE #( it_shared[ lv_idx ] DEFAULT `` ).
                  CATCH cx_sy_conversion_error.
                    CLEAR lv_text.
                ENDTRY.
              ENDIF.
              IF lv_col > 0.
                WHILE lines( ls_row-cells ) < lv_col.
                  APPEND `` TO ls_row-cells.
                ENDWHILE.
                ls_row-cells[ lv_col ] = lv_text.
                IF lv_text IS NOT INITIAL.
                  lv_has = abap_true.
                ENDIF.
              ENDIF.
            WHEN 'row'.
              IF lv_has = abap_true.
                APPEND ls_row TO rt_rows.
              ENDIF.
          ENDCASE.
      ENDCASE.
    ENDDO.
  ENDMETHOD.

ENDCLASS.
