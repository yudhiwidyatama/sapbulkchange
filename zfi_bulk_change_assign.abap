*&---------------------------------------------------------------------*
*& Report ZFI_BULK_CHANGE_ASSIGN
*&---------------------------------------------------------------------*
*& Purpose : Mass-change Assignment (ZUONR) on posted FI documents from
*&           an Excel (.xlsx) file, replacing change_assignment.py /
*&           change_assignment_rfc.py / fetch_acdoca_docs.py.
*&
*& Cross-Platform Excel Support (macOS & Windows):
*&   - Zero OLE2 Automation (no ALSM_EXCEL_TO_INTERNAL_TABLE or
*&     TEXT_CONVERT_XLS_TO_SAP, which fail on macOS SAP GUI for Java).
*&   - Binary upload (GUI_UPLOAD BIN -> XSTRING) + server-side OpenXML
*&     parsing via CL_ABAP_ZIP and CL_SXML_STRING_READER.
*&
*& Quality & Tests:
*&   - Embedded ABAP Unit test suite (Ctrl+Shift+F10 in SE38 / ADT).
*&   - See ABAP_ZPROGRAM_PLAN.md for full architectural specification.
*&---------------------------------------------------------------------*
REPORT zfi_bulk_change_assign MESSAGE-ID 00.

*======================================================================*
* Exception Class
*======================================================================*
CLASS lcx_bulk_error DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA mv_msg TYPE string READ-ONLY.
    METHODS constructor
      IMPORTING
        iv_msg      TYPE string
        ix_previous TYPE REF TO cx_root OPTIONAL.
    METHODS get_text REDEFINITION.
ENDCLASS.

CLASS lcx_bulk_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = ix_previous ).
    mv_msg = iv_msg.
  ENDMETHOD.

  METHOD get_text.
    result = mv_msg.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Shared Data Types & Constants
*======================================================================*
CLASS lcl_types DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS:
      c_assign_max_len TYPE i          VALUE 18,
      c_source_beban   TYPE string     VALUE 'BEBAN',
      c_source_vendor  TYPE string     VALUE 'VENDOR',
      BEGIN OF c_status,
        planned             TYPE string VALUE 'PLANNED',
        skipped_already_set TYPE string VALUE 'SKIPPED_ALREADY_SET',
        doc_not_found       TYPE string VALUE 'DOC_NOT_FOUND',
        no_match            TYPE string VALUE 'NO_MATCH',
        ambiguous           TYPE string VALUE 'AMBIGUOUS',
        testrun_ok          TYPE string VALUE 'TESTRUN_OK',
        sent                TYPE string VALUE 'SENT',
        send_error          TYPE string VALUE 'SEND_ERROR',
        changed             TYPE string VALUE 'CHANGED',
        not_changed         TYPE string VALUE 'NOT_CHANGED',
        verify_error        TYPE string VALUE 'VERIFY_ERROR',
        excel_error         TYPE string VALUE 'EXCEL_ERROR',
      END OF c_status,
      BEGIN OF c_mode,
        dry_run  TYPE c LENGTH 1 VALUE 'D',
        test_run TYPE c LENGTH 1 VALUE 'T',
        execute  TYPE c LENGTH 1 VALUE 'E',
      END OF c_mode.

    TYPES:
      BEGIN OF ty_cell,
        col   TYPE i,
        value TYPE string,
      END OF ty_cell,
      tt_cells TYPE SORTED TABLE OF ty_cell WITH UNIQUE KEY col,

      BEGIN OF ty_sheet_row,
        row_num TYPE i,
        cells   TYPE tt_cells,
      END OF ty_sheet_row,
      tt_sheet_rows TYPE STANDARD TABLE OF ty_sheet_row WITH EMPTY KEY,

      BEGIN OF ty_excel_row,
        xl_row  TYPE i,
        doc     TYPE belnr_d,
        year    TYPE gjahr,
        source  TYPE string,
        gl      TYPE string,
        account TYPE string,
        target  TYPE dzuonr,
      END OF ty_excel_row,
      tt_excel_rows TYPE STANDARD TABLE OF ty_excel_row WITH EMPTY KEY,

      BEGIN OF ty_excel_error,
        xl_row  TYPE i,
        message TYPE string,
      END OF ty_excel_error,
      tt_excel_errors TYPE STANDARD TABLE OF ty_excel_error WITH EMPTY KEY,

      BEGIN OF ty_doc_key,
        doc  TYPE belnr_d,
        year TYPE gjahr,
      END OF ty_doc_key,
      tt_doc_keys TYPE STANDARD TABLE OF ty_doc_key WITH EMPTY KEY,

      BEGIN OF ty_acdoca_item,
        doc        TYPE belnr_d,
        year       TYPE gjahr,
        item       TYPE buzei,
        racct      TYPE racct,
        assignment TYPE dzuonr,
        augbl      TYPE augbl,
      END OF ty_acdoca_item,
      tt_acdoca_items TYPE STANDARD TABLE OF ty_acdoca_item WITH EMPTY KEY,

      BEGIN OF ty_plan_row,
        icon    TYPE icon_d,
        xl_row  TYPE i,
        doc     TYPE belnr_d,
        year    TYPE gjahr,
        item    TYPE buzei,
        source  TYPE char10,
        gl      TYPE saknr,
        old     TYPE dzuonr,
        target  TYPE dzuonr,
        status  TYPE char24,
        message TYPE char255,
      END OF ty_plan_row,
      tt_plan_rows TYPE STANDARD TABLE OF ty_plan_row WITH EMPTY KEY,

      BEGIN OF ty_item_change,
        item   TYPE buzei,
        source TYPE string,
        old    TYPE dzuonr,
        target TYPE dzuonr,
      END OF ty_item_change,
      tt_item_changes TYPE STANDARD TABLE OF ty_item_change WITH EMPTY KEY.

    CLASS-METHODS strip_leading_zeros
      IMPORTING iv_val        TYPE clike
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS normalize_belnr
      IMPORTING iv_doc        TYPE clike
      RETURNING VALUE(rv_doc) TYPE belnr_d.
ENDCLASS.

CLASS lcl_types IMPLEMENTATION.
  METHOD strip_leading_zeros.
    rv_out = condense( val = CONV string( iv_val ) ).
    SHIFT rv_out LEFT DELETING LEADING '0'.
  ENDMETHOD.

  METHOD normalize_belnr.
    DATA(lv_str) = condense( val = CONV string( iv_doc ) ).
    IF strlen( lv_str ) < 10 AND lv_str CO '0123456789'.
      WHILE strlen( lv_str ) < 10.
        lv_str = '0' && lv_str.
      ENDWHILE.
    ENDIF.
    rv_doc = CONV belnr_d( lv_str ).
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Cross-Platform OpenXML (.xlsx) Parser (macOS & Windows Compatible)
*   Uses CL_ABAP_ZIP + CL_SXML_STRING_READER on the Application Server.
*   No OLE2, no SAP GUI platform lock-in.
*======================================================================*
CLASS lcl_xlsx_reader DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS parse
      IMPORTING
        iv_xlsx        TYPE xstring
      RETURNING
        VALUE(rt_rows) TYPE lcl_types=>tt_sheet_rows
      RAISING
        lcx_bulk_error.

    CLASS-METHODS col_letters_to_index
      IMPORTING
        iv_cell_ref   TYPE clike
      RETURNING
        VALUE(rv_col) TYPE i.

  PRIVATE SECTION.
    CLASS-METHODS resolve_first_sheet_path
      IMPORTING
        io_zip         TYPE REF TO cl_abap_zip
      RETURNING
        VALUE(rv_path) TYPE string.

    CLASS-METHODS parse_shared_strings
      IMPORTING
        iv_xml            TYPE xstring
      RETURNING
        VALUE(rt_strings) TYPE string_table
      RAISING
        lcx_bulk_error.

    CLASS-METHODS parse_worksheet
      IMPORTING
        iv_xml            TYPE xstring
        it_shared_strings TYPE string_table
      RETURNING
        VALUE(rt_rows)    TYPE lcl_types=>tt_sheet_rows
      RAISING
        lcx_bulk_error.
ENDCLASS.

CLASS lcl_xlsx_reader IMPLEMENTATION.
  METHOD col_letters_to_index.
    CONSTANTS lc_alphabet TYPE string VALUE 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.
    DATA(lv_ref) = to_upper( condense( val = CONV string( iv_cell_ref ) ) ).
    rv_col = 0.
    DATA(lv_len) = strlen( lv_ref ).
    DATA(lv_idx) = 0.
    WHILE lv_idx < lv_len.
      DATA(lv_char) = lv_ref+lv_idx(1).
      IF lv_char CA '0123456789$'.
        IF lv_char = '$'.
          lv_idx = lv_idx + 1.
          CONTINUE.
        ENDIF.
        EXIT.
      ENDIF.
      FIND FIRST OCCURRENCE OF lv_char IN lc_alphabet MATCH OFFSET DATA(lv_pos).
      IF sy-subrc = 0.
        rv_col = rv_col * 26 + ( lv_pos + 1 ).
      ENDIF.
      lv_idx = lv_idx + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD parse.
    IF iv_xlsx IS INITIAL.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = 'Uploaded Excel (.xlsx) content is empty'.
    ENDIF.

    DATA(lo_zip) = NEW cl_abap_zip( ).
    lo_zip->load(
      EXPORTING
        zip             = iv_xlsx
      EXCEPTIONS
        zip_parse_error = 1
        OTHERS          = 2 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = 'Invalid .xlsx file (ZIP archive header corrupt or unsupported format)'.
    ENDIF.

    " 1. Read optional xl/sharedStrings.xml
    DATA lt_shared_strings TYPE string_table.
    lo_zip->get(
      EXPORTING
        name                    = 'xl/sharedStrings.xml'
      IMPORTING
        content                 = DATA(lv_ss_xml)
      EXCEPTIONS
        zip_index_error         = 1
        zip_decompression_error = 2
        OTHERS                  = 3 ).
    IF sy-subrc = 0 AND lv_ss_xml IS NOT INITIAL.
      lt_shared_strings = parse_shared_strings( lv_ss_xml ).
    ENDIF.

    " 2. Locate first worksheet path (handles macOS/Windows/openpyxl variations)
    DATA(lv_sheet_path) = resolve_first_sheet_path( lo_zip ).
    lo_zip->get(
      EXPORTING
        name                    = lv_sheet_path
      IMPORTING
        content                 = DATA(lv_sheet_xml)
      EXCEPTIONS
        zip_index_error         = 1
        zip_decompression_error = 2
        OTHERS                  = 3 ).
    IF sy-subrc <> 0 OR lv_sheet_xml IS INITIAL.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = |Worksheet XML not found in .xlsx archive ({ lv_sheet_path })|.
    ENDIF.

    " 3. Parse worksheet rows and cells
    rt_rows = parse_worksheet(
      iv_xml            = lv_sheet_xml
      it_shared_strings = lt_shared_strings ).
  ENDMETHOD.

  METHOD resolve_first_sheet_path.
    rv_path = 'xl/worksheets/sheet1.xml'.

    io_zip->get(
      EXPORTING name    = 'xl/workbook.xml'
      IMPORTING content = DATA(lv_wb_xml)
      EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0 OR lv_wb_xml IS INITIAL.
      RETURN.
    ENDIF.

    " Find first <sheet r:id="..."/>
    DATA lv_rid TYPE string.
    TRY.
        DATA(lo_wb_reader) = cl_sxml_string_reader=>create( lv_wb_xml ).
        DO.
          DATA(lo_node) = lo_wb_reader->read_next_node( ).
          IF lo_node IS INITIAL.
            EXIT.
          ENDIF.
          IF lo_node->type = if_sxml_node=>co_nt_element_open.
            DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
            IF lo_open->qname-name = 'sheet'.
              LOOP AT lo_open->get_attributes( ) INTO DATA(lo_attr).
                IF lo_attr->qname-name = 'id'.
                  lv_rid = lo_attr->get_value( ).
                  EXIT.
                ENDIF.
              ENDLOOP.
              IF lv_rid IS NOT INITIAL.
                EXIT.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDDO.
      CATCH cx_sxml_error.
        RETURN.
    ENDTRY.

    IF lv_rid IS INITIAL.
      RETURN.
    ENDIF.

    io_zip->get(
      EXPORTING name    = 'xl/_rels/workbook.xml.rels'
      IMPORTING content = DATA(lv_rels_xml)
      EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0 OR lv_rels_xml IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_rels_reader) = cl_sxml_string_reader=>create( lv_rels_xml ).
        DO.
          lo_node = lo_rels_reader->read_next_node( ).
          IF lo_node IS INITIAL.
            EXIT.
          ENDIF.
          IF lo_node->type = if_sxml_node=>co_nt_element_open.
            lo_open = CAST if_sxml_open_element( lo_node ).
            IF lo_open->qname-name = 'Relationship'.
              DATA(lv_id) = ``.
              DATA(lv_target) = ``.
              LOOP AT lo_open->get_attributes( ) INTO lo_attr.
                CASE lo_attr->qname-name.
                  WHEN 'Id'.
                    lv_id = lo_attr->get_value( ).
                  WHEN 'Target'.
                    lv_target = lo_attr->get_value( ).
                ENDCASE.
              ENDLOOP.
              IF lv_id = lv_rid AND lv_target IS NOT INITIAL.
                SHIFT lv_target LEFT DELETING LEADING '/'.
                IF NOT ( strlen( lv_target ) >= 3 AND lv_target(3) = 'xl/' ).
                  lv_target = 'xl/' && lv_target.
                ENDIF.
                rv_path = lv_target.
                EXIT.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDDO.
      CATCH cx_sxml_error.
        RETURN.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_shared_strings.
    DATA:
      lv_in_si      TYPE abap_bool,
      lv_in_rph     TYPE abap_bool,
      lv_in_t       TYPE abap_bool,
      lv_current_si TYPE string.

    TRY.
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
                WHEN 'si'.
                  lv_in_si = abap_true.
                  lv_in_rph = abap_false.
                  lv_in_t = abap_false.
                  CLEAR lv_current_si.
                WHEN 'rPh'.
                  lv_in_rph = abap_true.
                WHEN 't'.
                  IF lv_in_si = abap_true AND lv_in_rph = abap_false.
                    lv_in_t = abap_true.
                  ENDIF.
              ENDCASE.

            WHEN if_sxml_node=>co_nt_value.
              IF lv_in_t = abap_true.
                DATA(lo_val) = CAST if_sxml_value_node( lo_node ).
                DATA(lv_chunk) = lo_val->get_value( ).
                CONCATENATE lv_current_si lv_chunk INTO lv_current_si RESPECTING BLANKS.
              ENDIF.

            WHEN if_sxml_node=>co_nt_element_close.
              DATA(lo_close) = CAST if_sxml_close_element( lo_node ).
              CASE lo_close->qname-name.
                WHEN 't'.
                  lv_in_t = abap_false.
                WHEN 'rPh'.
                  lv_in_rph = abap_false.
                WHEN 'si'.
                  APPEND lv_current_si TO rt_strings.
                  lv_in_si = abap_false.
              ENDCASE.
          ENDCASE.
        ENDDO.
      CATCH cx_sxml_error INTO DATA(lx_xml).
        RAISE EXCEPTION TYPE lcx_bulk_error
          EXPORTING
            iv_msg      = |Failed to parse xl/sharedStrings.xml: { lx_xml->get_text( ) }|
            ix_previous = lx_xml.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_worksheet.
    DATA:
      ls_row          TYPE lcl_types=>ty_sheet_row,
      lv_last_row_num TYPE i VALUE 0,
      lv_last_col_idx TYPE i VALUE 0,
      lv_cell_ref     TYPE string,
      lv_cell_type    TYPE string,
      lv_cell_val     TYPE string,
      lv_col_idx      TYPE i,
      lv_in_v         TYPE abap_bool,
      lv_in_is        TYPE abap_bool,
      lv_in_is_t      TYPE abap_bool.

    TRY.
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
                  CLEAR ls_row.
                  lv_last_col_idx = 0.
                  LOOP AT lo_open->get_attributes( ) INTO DATA(lo_attr).
                    IF lo_attr->qname-name = 'r'.
                      ls_row-row_num = CONV i( lo_attr->get_value( ) ).
                    ENDIF.
                  ENDLOOP.
                  IF ls_row-row_num <= 0.
                    ls_row-row_num = lv_last_row_num + 1.
                  ENDIF.
                  lv_last_row_num = ls_row-row_num.

                WHEN 'c'.
                  CLEAR: lv_cell_ref, lv_cell_type, lv_cell_val.
                  lv_in_v    = abap_false.
                  lv_in_is   = abap_false.
                  lv_in_is_t = abap_false.
                  LOOP AT lo_open->get_attributes( ) INTO lo_attr.
                    CASE lo_attr->qname-name.
                      WHEN 'r'.
                        lv_cell_ref = lo_attr->get_value( ).
                      WHEN 't'.
                        lv_cell_type = lo_attr->get_value( ).
                    ENDCASE.
                  ENDLOOP.
                  IF lv_cell_ref IS NOT INITIAL.
                    lv_col_idx = col_letters_to_index( lv_cell_ref ).
                  ELSE.
                    lv_col_idx = lv_last_col_idx + 1.
                  ENDIF.
                  lv_last_col_idx = lv_col_idx.

                WHEN 'v'.
                  lv_in_v = abap_true.

                WHEN 'is'.
                  lv_in_is = abap_true.

                WHEN 't'.
                  IF lv_in_is = abap_true OR lv_cell_type = 'inlineStr'.
                    lv_in_is_t = abap_true.
                  ENDIF.
              ENDCASE.

            WHEN if_sxml_node=>co_nt_value.
              IF lv_in_v = abap_true OR lv_in_is_t = abap_true.
                DATA(lo_val) = CAST if_sxml_value_node( lo_node ).
                DATA(lv_chunk) = lo_val->get_value( ).
                CONCATENATE lv_cell_val lv_chunk INTO lv_cell_val RESPECTING BLANKS.
              ENDIF.

            WHEN if_sxml_node=>co_nt_element_close.
              DATA(lo_close) = CAST if_sxml_close_element( lo_node ).
              CASE lo_close->qname-name.
                WHEN 'v'.
                  lv_in_v = abap_false.
                WHEN 't'.
                  lv_in_is_t = abap_false.
                WHEN 'is'.
                  lv_in_is = abap_false.
                WHEN 'c'.
                  DATA(lv_resolved) = lv_cell_val.
                  IF lv_cell_type = 's' AND lv_cell_val IS NOT INITIAL.
                    DATA(lv_ss_idx) = CONV i( lv_cell_val ) + 1.
                    READ TABLE it_shared_strings INTO lv_resolved INDEX lv_ss_idx.
                    IF sy-subrc <> 0.
                      CLEAR lv_resolved.
                    ENDIF.
                  ENDIF.
                  IF lv_col_idx > 0.
                    INSERT VALUE lcl_types=>ty_cell(
                      col   = lv_col_idx
                      value = lv_resolved ) INTO TABLE ls_row-cells.
                  ENDIF.
                WHEN 'row'.
                  IF ls_row-cells IS NOT INITIAL.
                    APPEND ls_row TO rt_rows.
                  ENDIF.
              ENDCASE.
          ENDCASE.
        ENDDO.
      CATCH cx_sxml_error INTO DATA(lx_xml).
        RAISE EXCEPTION TYPE lcx_bulk_error
          EXPORTING
            iv_msg      = |Failed to parse worksheet XML: { lx_xml->get_text( ) }|
            ix_previous = lx_xml.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Excel Business Validator & Header Mapper (Matches change_assignment.py)
*======================================================================*
CLASS lcl_excel_parser DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS extract_rows
      IMPORTING
        it_sheet_rows TYPE lcl_types=>tt_sheet_rows
        iv_limit_docs TYPE i DEFAULT 0
      EXPORTING
        et_rows       TYPE lcl_types=>tt_excel_rows
        et_errors     TYPE lcl_types=>tt_excel_errors
        et_doc_keys   TYPE lcl_types=>tt_doc_keys
      RAISING
        lcx_bulk_error.

  PRIVATE SECTION.
    CLASS-METHODS get_cell_value
      IMPORTING
        it_cells      TYPE lcl_types=>tt_cells
        iv_col        TYPE i
      RETURNING
        VALUE(rv_val) TYPE string.
ENDCLASS.

CLASS lcl_excel_parser IMPLEMENTATION.
  METHOD get_cell_value.
    READ TABLE it_cells INTO DATA(ls_cell) WITH TABLE KEY col = iv_col.
    IF sy-subrc = 0.
      rv_val = ls_cell-value.
    ENDIF.
  ENDMETHOD.

  METHOD extract_rows.
    CLEAR: et_rows, et_errors, et_doc_keys.

    IF it_sheet_rows IS INITIAL.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = 'Excel worksheet contains no rows'.
    ENDIF.

    " 1. Map header row (first row in worksheet)
    READ TABLE it_sheet_rows INTO DATA(ls_header_row) INDEX 1.
    DATA:
      lv_col_doc_year TYPE i,
      lv_col_source   TYPE i,
      lv_col_gl       TYPE i,
      lv_col_account  TYPE i,
      lv_col_target   TYPE i.

    LOOP AT ls_header_row-cells INTO DATA(ls_hcell).
      DATA(lv_hname) = to_upper( condense( val = ls_hcell-value ) ).
      CASE lv_hname.
        WHEN 'DOC NUMBER + YEAR'.
          lv_col_doc_year = ls_hcell-col.
        WHEN 'SOURCE DATA'.
          lv_col_source = ls_hcell-col.
        WHEN 'G/L ACCOUNT'.
          lv_col_gl = ls_hcell-col.
        WHEN 'ACCOUNT'.
          lv_col_account = ls_hcell-col.
        WHEN 'KODE PROJECT'.
          lv_col_target = ls_hcell-col.
      ENDCASE.
    ENDLOOP.

    DATA lt_missing TYPE string_table.
    IF lv_col_doc_year = 0. APPEND `'Doc Number + Year'` TO lt_missing. ENDIF.
    IF lv_col_source   = 0. APPEND `'Source Data'`       TO lt_missing. ENDIF.
    IF lv_col_gl       = 0. APPEND `'G/L Account'`       TO lt_missing. ENDIF.
    IF lv_col_account  = 0. APPEND `'Account'`           TO lt_missing. ENDIF.
    IF lv_col_target   = 0. APPEND `'KODE PROJECT'`      TO lt_missing. ENDIF.

    IF lt_missing IS NOT INITIAL.
      DATA(lv_missing_str) = concat_lines_of( table = lt_missing sep = ', ' ).
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = |Excel is missing required columns: [{ lv_missing_str }]|.
    ENDIF.

    " 2. Parse and validate data rows
    DATA lt_all_rows TYPE lcl_types=>tt_excel_rows.
    LOOP AT it_sheet_rows INTO DATA(ls_srow) FROM 2.
      DATA(lv_key) = condense( val = get_cell_value( it_cells = ls_srow-cells iv_col = lv_col_doc_year ) ).
      IF lv_key IS INITIAL.
        CONTINUE.
      ENDIF.

      IF strlen( lv_key ) < 5.
        APPEND VALUE #(
          xl_row  = ls_srow-row_num
          message = |bad 'Doc Number + Year': '{ lv_key }'| ) TO et_errors.
        CONTINUE.
      ENDIF.

      DATA(lv_split_pos) = strlen( lv_key ) - 4.
      DATA(lv_doc_raw)   = lv_key(lv_split_pos).
      DATA(lv_year_raw)  = lv_key+lv_split_pos(4).

      IF NOT ( lv_year_raw CO '0123456789' ) OR strlen( lv_doc_raw ) > 10.
        APPEND VALUE #(
          xl_row  = ls_srow-row_num
          message = |bad 'Doc Number + Year': '{ lv_key }'| ) TO et_errors.
        CONTINUE.
      ENDIF.

      DATA(lv_source) = to_upper( condense( val = get_cell_value( it_cells = ls_srow-cells iv_col = lv_col_source ) ) ).
      IF lv_source <> lcl_types=>c_source_beban AND lv_source <> lcl_types=>c_source_vendor.
        APPEND VALUE #(
          xl_row  = ls_srow-row_num
          message = |unknown Source Data '{ lv_source }'| ) TO et_errors.
        CONTINUE.
      ENDIF.

      DATA(lv_target) = condense( val = get_cell_value( it_cells = ls_srow-cells iv_col = lv_col_target ) ).
      IF lv_target IS INITIAL.
        APPEND VALUE #(
          xl_row  = ls_srow-row_num
          message = 'KODE PROJECT is empty' ) TO et_errors.
        CONTINUE.
      ENDIF.

      IF strlen( lv_target ) > lcl_types=>c_assign_max_len.
        APPEND VALUE #(
          xl_row  = ls_srow-row_num
          message = |KODE PROJECT longer than { lcl_types=>c_assign_max_len }: '{ lv_target }'| ) TO et_errors.
        CONTINUE.
      ENDIF.

      DATA(lv_doc_10) = lcl_types=>normalize_belnr( lv_doc_raw ).
      DATA(lv_year_4) = CONV gjahr( lv_year_raw ).

      APPEND VALUE #(
        xl_row  = ls_srow-row_num
        doc     = lv_doc_10
        year    = lv_year_4
        source  = lv_source
        gl      = condense( val = get_cell_value( it_cells = ls_srow-cells iv_col = lv_col_gl ) )
        account = condense( val = get_cell_value( it_cells = ls_srow-cells iv_col = lv_col_account ) )
        target  = CONV dzuonr( lv_target ) ) TO lt_all_rows.
    ENDLOOP.

    " 3. Group distinct (doc, year) keys in discovery order and apply optional --limit
    LOOP AT lt_all_rows INTO DATA(ls_valid).
      READ TABLE et_doc_keys TRANSPORTING NO FIELDS
        WITH KEY doc = ls_valid-doc year = ls_valid-year.
      IF sy-subrc <> 0.
        IF iv_limit_docs > 0 AND lines( et_doc_keys ) >= iv_limit_docs.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( doc = ls_valid-doc year = ls_valid-year ) TO et_doc_keys.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_all_rows INTO ls_valid.
      READ TABLE et_doc_keys TRANSPORTING NO FIELDS
        WITH KEY doc = ls_valid-doc year = ls_valid-year.
      IF sy-subrc = 0.
        APPEND ls_valid TO et_rows.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Interfaces for Database Lookup & FI Document Change (Test Seams)
*======================================================================*
INTERFACE lif_db_provider.
  METHODS fetch_items
    IMPORTING
      iv_bukrs         TYPE bukrs
      iv_rldnr         TYPE fins_ledger
      it_doc_keys      TYPE lcl_types=>tt_doc_keys
      iv_bypass_buffer TYPE abap_bool DEFAULT abap_false
    RETURNING
      VALUE(rt_items)  TYPE lcl_types=>tt_acdoca_items.
ENDINTERFACE.

INTERFACE lif_doc_changer.
  METHODS change_document
    IMPORTING
      iv_bukrs     TYPE bukrs
      iv_doc       TYPE belnr_d
      iv_year      TYPE gjahr
      iv_testrun   TYPE abap_bool
      it_changes   TYPE lcl_types=>tt_item_changes
    EXPORTING
      ev_ok        TYPE abap_bool
      ev_message   TYPE string.
ENDINTERFACE.

*======================================================================*
* Production Database Provider (ACDOCA + BSEG Bulk Lookup)
*======================================================================*
CLASS lcl_db_provider DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES lif_db_provider.
ENDCLASS.

CLASS lcl_db_provider IMPLEMENTATION.
  METHOD lif_db_provider~fetch_items.
    CLEAR rt_items.
    IF it_doc_keys IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_keys) = it_doc_keys.
    SORT lt_keys BY doc year.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING doc year.

    TYPES:
      BEGIN OF ty_acdoca_raw,
        belnr TYPE belnr_d,
        gjahr TYPE gjahr,
        docln TYPE docln6,
        racct TYPE racct,
        zuonr TYPE dzuonr,
      END OF ty_acdoca_raw,
      BEGIN OF ty_bseg_raw,
        belnr TYPE belnr_d,
        gjahr TYPE gjahr,
        buzei TYPE buzei,
        augbl TYPE augbl,
      END OF ty_bseg_raw.

    DATA:
      lt_acdoca TYPE STANDARD TABLE OF ty_acdoca_raw WITH EMPTY KEY,
      lt_bseg   TYPE SORTED TABLE OF ty_bseg_raw WITH UNIQUE KEY belnr gjahr buzei.

    IF iv_bypass_buffer = abap_true.
      SELECT belnr, gjahr, docln, racct, zuonr
        FROM acdoca
        BYPASSING BUFFER
        INTO TABLE @lt_acdoca
        FOR ALL ENTRIES IN @lt_keys
        WHERE rldnr  = @iv_rldnr
          AND rbukrs = @iv_bukrs
          AND belnr  = @lt_keys-doc
          AND gjahr  = @lt_keys-year.
    ELSE.
      SELECT belnr, gjahr, docln, racct, zuonr
        FROM acdoca
        INTO TABLE @lt_acdoca
        FOR ALL ENTRIES IN @lt_keys
        WHERE rldnr  = @iv_rldnr
          AND rbukrs = @iv_bukrs
          AND belnr  = @lt_keys-doc
          AND gjahr  = @lt_keys-year.
    ENDIF.

    SELECT belnr, gjahr, buzei, augbl
      FROM bseg
      INTO TABLE @lt_bseg
      FOR ALL ENTRIES IN @lt_keys
      WHERE bukrs = @iv_bukrs
        AND belnr = @lt_keys-doc
        AND gjahr = @lt_keys-year.

    SORT lt_acdoca BY belnr gjahr docln.

    LOOP AT lt_acdoca INTO DATA(ls_ac).
      " Last 3 digits of 6-character DOCLN correspond to BSEG-BUZEI
      DATA(lv_buzei) = CONV buzei( ls_ac-docln+3(3) ).
      DATA(lv_augbl) = VALUE augbl( ).
      READ TABLE lt_bseg INTO DATA(ls_bs)
        WITH TABLE KEY belnr = ls_ac-belnr gjahr = ls_ac-gjahr buzei = lv_buzei.
      IF sy-subrc = 0.
        lv_augbl = ls_bs-augbl.
      ENDIF.

      APPEND VALUE lcl_types=>ty_acdoca_item(
        doc        = ls_ac-belnr
        year       = ls_ac-gjahr
        item       = lv_buzei
        racct      = ls_ac-racct
        assignment = ls_ac-zuonr
        augbl      = lv_augbl ) TO rt_items.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Production Document Changer (ENQUEUE_EFBKPF + FI_DOCUMENT_CHANGE)
*   All-or-nothing per document LUW, matching zrfc_fi_change_assign.abap
*======================================================================*
CLASS lcl_fi_doc_changer DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES lif_doc_changer.
ENDCLASS.

CLASS lcl_fi_doc_changer IMPLEMENTATION.
  METHOD lif_doc_changer~change_document.
    ev_ok = abap_true.
    CLEAR ev_message.

    IF it_changes IS INITIAL.
      ev_message = 'No items to change'.
      RETURN.
    ENDIF.

    " 1. Authorization check
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD iv_bukrs
      ID 'ACTVT' FIELD '02'.
    IF sy-subrc <> 0.
      ev_ok      = abap_false.
      ev_message = |No authorization (F_BKPF_BUK ACTVT 02) for company code { iv_bukrs }|.
      RETURN.
    ENDIF.

    " 2. Lock FI document header (BKPF)
    CALL FUNCTION 'ENQUEUE_EFBKPF'
      EXPORTING
        belnr          = iv_doc
        bukrs          = iv_bukrs
        gjahr          = iv_year
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      ev_ok      = abap_false.
      ev_message = |Document { iv_doc }/{ iv_year } is locked by user { sy-msgv1 }|.
      RETURN.
    ENDIF.

    IF iv_testrun = abap_true.
      CALL FUNCTION 'DEQUEUE_EFBKPF'
        EXPORTING
          belnr = iv_doc
          bukrs = iv_bukrs
          gjahr = iv_year.
      ev_ok      = abap_true.
      ev_message = 'Test run: authority & lock validation OK, nothing changed'.
      RETURN.
    ENDIF.

    " 3. Order items: BEBAN (G/L) first, then VENDOR (consistent with Python script)
    DATA lt_ordered TYPE lcl_types=>tt_item_changes.
    LOOP AT it_changes INTO DATA(ls_chg) WHERE source = lcl_types=>c_source_beban.
      APPEND ls_chg TO lt_ordered.
    ENDLOOP.
    LOOP AT it_changes INTO ls_chg WHERE source <> lcl_types=>c_source_beban.
      APPEND ls_chg TO lt_ordered.
    ENDLOOP.

    " 4. Call FI_DOCUMENT_CHANGE for each line item in a single LUW
    DATA lt_accchg TYPE STANDARD TABLE OF accchg.
    DATA ls_accchg TYPE accchg.

    LOOP AT lt_ordered INTO ls_chg.
      REFRESH lt_accchg.
      CLEAR ls_accchg.
      ls_accchg-fdname = 'ZUONR'.
      ls_accchg-oldval = ls_chg-old.
      ls_accchg-newval = ls_chg-target.
      APPEND ls_accchg TO lt_accchg.

      CALL FUNCTION 'FI_DOCUMENT_CHANGE'
        EXPORTING
          i_buzei              = ls_chg-item
          i_bukrs              = iv_bukrs
          i_belnr              = iv_doc
          i_gjahr              = iv_year
        TABLES
          t_accchg             = lt_accchg
        EXCEPTIONS
          no_reference         = 1
          no_document          = 2
          many_documents       = 3
          wrong_input          = 4
          overwrite_creditcard = 5
          OTHERS               = 6.

      IF sy-subrc <> 0.
        DATA(lv_subrc) = sy-subrc.
        IF sy-msgid IS NOT INITIAL.
          MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO ev_message.
        ELSE.
          ev_message = |FI_DOCUMENT_CHANGE failed for item { ls_chg-item } (sy-subrc={ lv_subrc })|.
        ENDIF.
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        CALL FUNCTION 'DEQUEUE_EFBKPF'
          EXPORTING
            belnr = iv_doc
            bukrs = iv_bukrs
            gjahr = iv_year.
        ev_ok = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.

    " 5. Commit LUW and release lock
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.

    CALL FUNCTION 'DEQUEUE_EFBKPF'
      EXPORTING
        belnr = iv_doc
        bukrs = iv_bukrs
        gjahr = iv_year.

    ev_ok      = abap_true.
    ev_message = |Assignment changed ({ lines( lt_ordered ) } line(s))|.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Core Orchestrator (Resolve -> Execute -> Re-Read Verify -> CSV Format)
*======================================================================*
CLASS lcl_orchestrator DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        io_db      TYPE REF TO lif_db_provider
        io_changer TYPE REF TO lif_doc_changer.

    METHODS run
      IMPORTING
        iv_bukrs       TYPE bukrs
        iv_rldnr       TYPE fins_ledger DEFAULT '0L'
        iv_mode        TYPE c
        it_excel_rows  TYPE lcl_types=>tt_excel_rows
        it_excel_errs  TYPE lcl_types=>tt_excel_errors OPTIONAL
        it_doc_keys    TYPE lcl_types=>tt_doc_keys
      RETURNING
        VALUE(rt_plan) TYPE lcl_types=>tt_plan_rows.

    CLASS-METHODS resolve_line
      IMPORTING
        is_row        TYPE lcl_types=>ty_excel_row
        it_doc_items  TYPE lcl_types=>tt_acdoca_items
      EXPORTING
        es_item       TYPE lcl_types=>ty_acdoca_item
        ev_status     TYPE string
        ev_message    TYPE string.

    CLASS-METHODS build_csv_lines
      IMPORTING
        it_plan       TYPE lcl_types=>tt_plan_rows
      RETURNING
        VALUE(rt_csv) TYPE string_table.

  PRIVATE SECTION.
    DATA mo_db      TYPE REF TO lif_db_provider.
    DATA mo_changer TYPE REF TO lif_doc_changer.

    CLASS-METHODS status_to_icon
      IMPORTING iv_status      TYPE clike
      RETURNING VALUE(rv_icon) TYPE icon_d.

    CLASS-METHODS escape_csv_field
      IMPORTING iv_val        TYPE clike
      RETURNING VALUE(rv_out) TYPE string.
ENDCLASS.

CLASS lcl_orchestrator IMPLEMENTATION.
  METHOD constructor.
    mo_db      = io_db.
    mo_changer = io_changer.
  ENDMETHOD.

  METHOD status_to_icon.
    CASE CONV string( iv_status ).
      WHEN lcl_types=>c_status-changed
        OR lcl_types=>c_status-testrun_ok.
        rv_icon = icon_led_green.
      WHEN lcl_types=>c_status-planned
        OR lcl_types=>c_status-skipped_already_set
        OR lcl_types=>c_status-sent.
        rv_icon = icon_led_yellow.
      WHEN OTHERS.
        rv_icon = icon_led_red.
    ENDCASE.
  ENDMETHOD.

  METHOD resolve_line.
    CLEAR: es_item, ev_status, ev_message.

    IF it_doc_items IS INITIAL.
      ev_status  = lcl_types=>c_status-doc_not_found.
      ev_message = 'Document not found in ACDOCA'.
      RETURN.
    ENDIF.

    DATA(lv_target_gl) = lcl_types=>strip_leading_zeros( is_row-gl ).
    DATA lt_hits TYPE lcl_types=>tt_acdoca_items.

    LOOP AT it_doc_items INTO DATA(ls_item).
      IF lcl_types=>strip_leading_zeros( ls_item-racct ) = lv_target_gl.
        APPEND ls_item TO lt_hits.
      ENDIF.
    ENDLOOP.

    IF lt_hits IS INITIAL.
      ev_status  = lcl_types=>c_status-no_match.
      ev_message = |No ACDOCA line matches G/L Account { is_row-gl }|.
      RETURN.
    ELSEIF lines( lt_hits ) > 1.
      ev_status  = lcl_types=>c_status-ambiguous.
      ev_message = |Multiple ({ lines( lt_hits ) }) ACDOCA lines match G/L Account { is_row-gl }|.
      RETURN.
    ENDIF.

    READ TABLE lt_hits INTO es_item INDEX 1.
    IF es_item-assignment = is_row-target.
      ev_status  = lcl_types=>c_status-skipped_already_set.
      ev_message = 'Assignment already equals target value'.
    ELSE.
      ev_status  = lcl_types=>c_status-planned.
      IF es_item-augbl IS NOT INITIAL.
        ev_message = |Cleared item (AUGBL={ es_item-augbl }); verify OB32 field status|.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD run.
    CLEAR rt_plan.

    " 0. Record any Excel parsing/validation errors at the top of the report
    LOOP AT it_excel_errs INTO DATA(ls_err).
      APPEND VALUE lcl_types=>ty_plan_row(
        icon    = status_to_icon( lcl_types=>c_status-excel_error )
        xl_row  = ls_err-xl_row
        status  = CONV char24( lcl_types=>c_status-excel_error )
        message = CONV char255( ls_err-message ) ) TO rt_plan.
    ENDLOOP.

    IF it_excel_rows IS INITIAL.
      RETURN.
    ENDIF.

    " 1. Bulk lookup of ACDOCA + BSEG items for all target documents
    DATA(lt_all_items) = mo_db->fetch_items(
      iv_bukrs         = iv_bukrs
      iv_rldnr         = iv_rldnr
      it_doc_keys      = it_doc_keys
      iv_bypass_buffer = abap_false ).

    " 2. Resolve each Excel row to an exact ACDOCA line item
    LOOP AT it_doc_keys INTO DATA(ls_dkey).
      DATA lt_doc_items TYPE lcl_types=>tt_acdoca_items.
      CLEAR lt_doc_items.
      DATA(lv_doc_no0) = lcl_types=>strip_leading_zeros( ls_dkey-doc ).

      LOOP AT lt_all_items INTO DATA(ls_aitem)
        WHERE year = ls_dkey-year.
        IF lcl_types=>strip_leading_zeros( ls_aitem-doc ) = lv_doc_no0.
          APPEND ls_aitem TO lt_doc_items.
        ENDIF.
      ENDLOOP.

      LOOP AT it_excel_rows INTO DATA(ls_xrow)
        WHERE doc  = ls_dkey-doc
          AND year = ls_dkey-year.

        resolve_line(
          EXPORTING
            is_row       = ls_xrow
            it_doc_items = lt_doc_items
          IMPORTING
            es_item      = DATA(ls_matched)
            ev_status    = DATA(lv_status)
            ev_message   = DATA(lv_msg) ).

        APPEND VALUE lcl_types=>ty_plan_row(
          icon    = status_to_icon( lv_status )
          xl_row  = ls_xrow-xl_row
          doc     = ls_xrow-doc
          year    = ls_xrow-year
          item    = ls_matched-item
          source  = CONV char10( ls_xrow-source )
          gl      = CONV saknr( ls_xrow-gl )
          old     = ls_matched-assignment
          target  = ls_xrow-target
          status  = CONV char24( lv_status )
          message = CONV char255( lv_msg ) ) TO rt_plan.
      ENDLOOP.
    ENDLOOP.

    " 3. Stop here if Dry-Run or no PLANNED lines exist
    IF iv_mode = lcl_types=>c_mode-dry_run.
      RETURN.
    ENDIF.

    DATA(lv_has_planned) = abap_false.
    LOOP AT rt_plan TRANSPORTING NO FIELDS
      WHERE status = lcl_types=>c_status-planned.
      lv_has_planned = abap_true.
      EXIT.
    ENDLOOP.
    IF lv_has_planned = abap_false.
      RETURN.
    ENDIF.

    " 4. Execute changes per document (Test-Run or Live Execution)
    DATA lt_sent_keys TYPE lcl_types=>tt_doc_keys.

    LOOP AT it_doc_keys INTO ls_dkey.
      DATA lt_doc_changes TYPE lcl_types=>tt_item_changes.
      CLEAR lt_doc_changes.

      LOOP AT rt_plan INTO DATA(ls_prow)
        WHERE doc    = ls_dkey-doc
          AND year   = ls_dkey-year
          AND status = lcl_types=>c_status-planned.
        APPEND VALUE lcl_types=>ty_item_change(
          item   = ls_prow-item
          source = condense( val = CONV string( ls_prow-source ) )
          old    = ls_prow-old
          target = ls_prow-target ) TO lt_doc_changes.
      ENDLOOP.

      IF lt_doc_changes IS INITIAL.
        CONTINUE.
      ENDIF.

      mo_changer->change_document(
        EXPORTING
          iv_bukrs   = iv_bukrs
          iv_doc     = ls_dkey-doc
          iv_year    = ls_dkey-year
          iv_testrun = xsdbool( iv_mode = lcl_types=>c_mode-test_run )
          it_changes = lt_doc_changes
        IMPORTING
          ev_ok      = DATA(lv_ok)
          ev_message = DATA(lv_chg_msg) ).

      DATA(lv_new_status) = COND string(
        WHEN lv_ok = abap_false THEN lcl_types=>c_status-send_error
        WHEN iv_mode = lcl_types=>c_mode-test_run THEN lcl_types=>c_status-testrun_ok
        ELSE lcl_types=>c_status-sent ).

      LOOP AT rt_plan ASSIGNING FIELD-SYMBOL(<fs_prow>)
        WHERE doc    = ls_dkey-doc
          AND year   = ls_dkey-year
          AND status = lcl_types=>c_status-planned.
        <fs_prow>-status  = CONV char24( lv_new_status ).
        <fs_prow>-icon    = status_to_icon( lv_new_status ).
        <fs_prow>-message = CONV char255( lv_chg_msg ).
      ENDLOOP.

      IF lv_new_status = lcl_types=>c_status-sent.
        APPEND ls_dkey TO lt_sent_keys.
      ENDIF.
    ENDLOOP.

    " 5. Post-Commit Verification: Re-read ACDOCA bypassing buffer
    IF iv_mode = lcl_types=>c_mode-execute AND lt_sent_keys IS NOT INITIAL.
      DATA(lt_now_items) = mo_db->fetch_items(
        iv_bukrs         = iv_bukrs
        iv_rldnr         = iv_rldnr
        it_doc_keys      = lt_sent_keys
        iv_bypass_buffer = abap_true ).

      LOOP AT rt_plan ASSIGNING <fs_prow>
        WHERE status = lcl_types=>c_status-sent.
        DATA(lv_pdoc_no0) = lcl_types=>strip_leading_zeros( <fs_prow>-doc ).
        DATA(lv_found)    = abap_false.
        DATA(lv_cur_val)  = VALUE dzuonr( ).

        LOOP AT lt_now_items INTO DATA(ls_now)
          WHERE year = <fs_prow>-year
            AND item = <fs_prow>-item.
          IF lcl_types=>strip_leading_zeros( ls_now-doc ) = lv_pdoc_no0.
            lv_found   = abap_true.
            lv_cur_val = ls_now-assignment.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF lv_found = abap_true AND lv_cur_val = <fs_prow>-target.
          <fs_prow>-status = CONV char24( lcl_types=>c_status-changed ).
          <fs_prow>-icon   = status_to_icon( lcl_types=>c_status-changed ).
        ELSE.
          <fs_prow>-status  = CONV char24( lcl_types=>c_status-not_changed ).
          <fs_prow>-icon    = status_to_icon( lcl_types=>c_status-not_changed ).
          <fs_prow>-message = CONV char255(
            |{ <fs_prow>-message }; current value '{ lv_cur_val }' differs from '{ <fs_prow>-target }'| ).
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD escape_csv_field.
    rv_out = CONV string( iv_val ).
    IF rv_out CA ',"' OR rv_out CA cl_abap_char_utilities=>cr_lf.
      REPLACE ALL OCCURRENCES OF '"' IN rv_out WITH '""'.
      rv_out = '"' && rv_out && '"'.
    ENDIF.
  ENDMETHOD.

  METHOD build_csv_lines.
    " Matches Python CSV columns: doc,year,item,source,old,target,status,message
    APPEND 'doc,year,item,source,old,target,status,message' TO rt_csv.
    LOOP AT it_plan INTO DATA(ls_p).
      DATA(lv_doc)    = escape_csv_field( condense( val = CONV string( ls_p-doc ) ) ).
      DATA(lv_year)   = escape_csv_field( condense( val = CONV string( ls_p-year ) ) ).
      DATA(lv_item)   = escape_csv_field( condense( val = CONV string( ls_p-item ) ) ).
      DATA(lv_source) = escape_csv_field( condense( val = CONV string( ls_p-source ) ) ).
      DATA(lv_old)    = escape_csv_field( condense( val = CONV string( ls_p-old ) ) ).
      DATA(lv_target) = escape_csv_field( condense( val = CONV string( ls_p-target ) ) ).
      DATA(lv_status) = escape_csv_field( condense( val = CONV string( ls_p-status ) ) ).
      DATA(lv_msg)    = escape_csv_field( condense( val = CONV string( ls_p-message ) ) ).

      APPEND |{ lv_doc },{ lv_year },{ lv_item },{ lv_source },{ lv_old },{ lv_target },{ lv_status },{ lv_msg }|
        TO rt_csv.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Cross-Platform Frontend & Application Server File I/O (macOS & Windows)
*======================================================================*
CLASS lcl_file_io DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS browse_local_xlsx
      CHANGING cv_path TYPE string.

    CLASS-METHODS browse_local_csv
      CHANGING cv_path TYPE string.

    CLASS-METHODS load_xlsx_bytes
      IMPORTING
        iv_path         TYPE string
        iv_app_server   TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rv_bytes) TYPE xstring
      RAISING
        lcx_bulk_error.

    CLASS-METHODS save_csv_file
      IMPORTING
        iv_path       TYPE string
        iv_app_server TYPE abap_bool DEFAULT abap_false
        it_csv_lines  TYPE string_table
      RAISING
        lcx_bulk_error.
ENDCLASS.

CLASS lcl_file_io IMPLEMENTATION.
  METHOD browse_local_xlsx.
    DATA:
      lt_files TYPE filetable,
      lv_rc    TYPE i.

    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        window_title            = 'Select Excel (.xlsx) File for Assignment Change'
        default_extension       = 'xlsx'
        file_filter             = 'Excel Files (*.xlsx)|*.xlsx|All Files (*.*)|*.*'
      CHANGING
        file_table              = lt_files
        rc                      = lv_rc
      EXCEPTIONS
        file_open_dialog_failed = 1
        cntl_error              = 2
        error_no_gui            = 3
        not_supported_by_gui    = 4
        OTHERS                  = 5 ).
    IF sy-subrc = 0 AND lv_rc >= 1.
      READ TABLE lt_files INTO DATA(ls_file) INDEX 1.
      IF sy-subrc = 0.
        cv_path = ls_file-filename.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD browse_local_csv.
    DATA:
      lv_filename TYPE string,
      lv_path     TYPE string,
      lv_fullpath TYPE string,
      lv_action   TYPE i.

    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING
        window_title              = 'Save Assignment Change Results CSV'
        default_extension         = 'csv'
        default_file_name         = |assignment_change_results_{ sy-datum }_{ sy-uzeit }.csv|
        file_filter               = 'CSV Files (*.csv)|*.csv'
      CHANGING
        filename                  = lv_filename
        path                      = lv_path
        fullpath                  = lv_fullpath
        user_action               = lv_action
      EXCEPTIONS
        cntl_error                = 1
        error_no_gui              = 2
        not_supported_by_gui      = 3
        invalid_default_file_name = 4
        OTHERS                    = 5 ).
    IF sy-subrc = 0 AND lv_action = cl_gui_frontend_services=>action_ok.
      cv_path = lv_fullpath.
    ENDIF.
  ENDMETHOD.

  METHOD load_xlsx_bytes.
    IF iv_path IS INITIAL.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = 'Excel file path is empty'.
    ENDIF.

    DATA lv_os_msg TYPE string.
    IF iv_app_server = abap_true.
      OPEN DATASET iv_path FOR INPUT IN BINARY MODE MESSAGE lv_os_msg.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_bulk_error
          EXPORTING iv_msg = |Cannot open application server file '{ iv_path }': { lv_os_msg }|.
      ENDIF.
      READ DATASET iv_path INTO rv_bytes.
      CLOSE DATASET iv_path.
      RETURN.
    ENDIF.

    " Frontend binary upload (Works identically on macOS SAP GUI for Java & Windows SAP GUI)
    DATA:
      lt_solix      TYPE solix_tab,
      lv_filelength TYPE i.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename                = iv_path
        filetype                = 'BIN'
      IMPORTING
        filelength              = lv_filelength
      CHANGING
        data_tab                = lt_solix
      EXCEPTIONS
        file_open_error         = 1
        file_read_error         = 2
        no_batch                = 3
        gui_refuse_filetransfer = 4
        invalid_type            = 5
        no_authority            = 6
        unknown_error           = 7
        bad_data_format         = 8
        header_not_allowed      = 9
        separator_not_allowed   = 10
        header_too_long         = 11
        unknown_dp_error        = 12
        access_denied           = 13
        dp_out_of_memory        = 14
        disk_full               = 15
        dp_timeout              = 16
        not_supported_by_gui    = 17
        error_no_gui            = 18
        OTHERS                  = 19 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = |GUI_UPLOAD failed for '{ iv_path }' (sy-subrc={ sy-subrc })|.
    ENDIF.

    rv_bytes = cl_bcs_convert=>solix_to_xstring(
      it_solix = lt_solix
      iv_size  = lv_filelength ).
  ENDMETHOD.

  METHOD save_csv_file.
    IF iv_path IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_os_msg TYPE string.
    IF iv_app_server = abap_true.
      OPEN DATASET iv_path FOR OUTPUT IN TEXT MODE ENCODING UTF-8 MESSAGE lv_os_msg.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_bulk_error
          EXPORTING iv_msg = |Cannot write application server CSV '{ iv_path }': { lv_os_msg }|.
      ENDIF.
      LOOP AT it_csv_lines INTO DATA(lv_line).
        TRANSFER lv_line TO iv_path.
      ENDLOOP.
      CLOSE DATASET iv_path.
      RETURN.
    ENDIF.

    DATA(lt_lines) = it_csv_lines.
    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename                = iv_path
        filetype                = 'ASC'
        codepage                = '4110' " UTF-8 on macOS and Windows
      CHANGING
        data_tab                = lt_lines
      EXCEPTIONS
        file_write_error        = 1
        no_batch                = 2
        gui_refuse_filetransfer = 3
        invalid_type            = 4
        no_authority            = 5
        unknown_error           = 6
        header_not_allowed      = 7
        separator_not_allowed   = 8
        filesize_not_allowed    = 9
        header_too_long         = 10
        dp_error_create         = 11
        dp_error_send           = 12
        dp_error_write          = 13
        unknown_dp_error        = 14
        access_denied           = 15
        dp_out_of_memory        = 16
        disk_full               = 17
        dp_timeout              = 18
        file_not_found          = 19
        dataprovider_exception  = 20
        control_flush_error     = 21
        not_supported_by_gui    = 22
        error_no_gui            = 23
        OTHERS                  = 24 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_bulk_error
        EXPORTING iv_msg = |GUI_DOWNLOAD failed for '{ iv_path }' (sy-subrc={ sy-subrc })|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* ALV Output Presenter
*======================================================================*
CLASS lcl_alv_presenter DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS display
      IMPORTING
        iv_bukrs TYPE bukrs
        iv_mode  TYPE c
        it_plan  TYPE lcl_types=>tt_plan_rows.
ENDCLASS.

CLASS lcl_alv_presenter IMPLEMENTATION.
  METHOD display.
    DATA(lt_display) = it_plan.

    " Compute summary counts by status
    DATA:
      lv_cnt_planned TYPE i,
      lv_cnt_changed TYPE i,
      lv_cnt_skipped TYPE i,
      lv_cnt_testok  TYPE i,
      lv_cnt_errors  TYPE i.

    LOOP AT lt_display INTO DATA(ls_row).
      CASE CONV string( ls_row-status ).
        WHEN lcl_types=>c_status-planned.
          lv_cnt_planned = lv_cnt_planned + 1.
        WHEN lcl_types=>c_status-changed.
          lv_cnt_changed = lv_cnt_changed + 1.
        WHEN lcl_types=>c_status-skipped_already_set.
          lv_cnt_skipped = lv_cnt_skipped + 1.
        WHEN lcl_types=>c_status-testrun_ok.
          lv_cnt_testok = lv_cnt_testok + 1.
        WHEN OTHERS.
          lv_cnt_errors = lv_cnt_errors + 1.
      ENDCASE.
    ENDLOOP.

    IF sy-batch = abap_true.
      WRITE: / 'SAP FI Bulk Assignment (ZUONR) Change Summary',
             / 'Company Code:', iv_bukrs, 'Mode:', iv_mode,
             / 'Total Rows  :', lines( lt_display ),
             / 'Planned     :', lv_cnt_planned,
             / 'Changed     :', lv_cnt_changed,
             / 'TestRun OK  :', lv_cnt_testok,
             / 'Skipped     :', lv_cnt_skipped,
             / 'Errors      :', lv_cnt_errors.
      ULINE.
      LOOP AT lt_display INTO ls_row.
        WRITE: / ls_row-doc, ls_row-year, ls_row-item, ls_row-source,
                 ls_row-old, '->', ls_row-target, ls_row-status, ls_row-message(80).
      ENDLOOP.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = DATA(lo_alv)
          CHANGING
            t_table      = lt_display ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_alv->get_display_settings( )->set_list_header(
          |FI Bulk Assignment Change (BUKRS { iv_bukrs }) - Total: { lines( lt_display ) } | &&
          |Planned: { lv_cnt_planned } Changed: { lv_cnt_changed } | &&
          |Skipped: { lv_cnt_skipped } Errors: { lv_cnt_errors }| ).

        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->set_optimize( abap_true ).

        TRY.
            DATA(lo_col_icon) = CAST cl_salv_column_table( lo_cols->get_column( 'ICON' ) ).
            lo_col_icon->set_icon( abap_true ).
            lo_col_icon->set_short_text( 'St.' ).
            lo_col_icon->set_medium_text( 'Light' ).
            lo_col_icon->set_long_text( 'Status Light' ).

            lo_cols->get_column( 'XL_ROW' )->set_short_text( 'Row' ).
            lo_cols->get_column( 'XL_ROW' )->set_medium_text( 'Excel Row' ).
            lo_cols->get_column( 'SOURCE' )->set_short_text( 'Source' ).
            lo_cols->get_column( 'SOURCE' )->set_medium_text( 'Source Data' ).
            lo_cols->get_column( 'OLD' )->set_short_text( 'Old ZUONR' ).
            lo_cols->get_column( 'OLD' )->set_medium_text( 'Old Assignment' ).
            lo_cols->get_column( 'TARGET' )->set_short_text( 'New ZUONR' ).
            lo_cols->get_column( 'TARGET' )->set_medium_text( 'Target Assignment' ).
            lo_cols->get_column( 'STATUS' )->set_short_text( 'Status' ).
            lo_cols->get_column( 'STATUS' )->set_medium_text( 'Line Status' ).
            lo_cols->get_column( 'MESSAGE' )->set_short_text( 'Message' ).
            lo_cols->get_column( 'MESSAGE' )->set_medium_text( 'Processing Message' ).
          CATCH cx_salv_not_found.
        ENDTRY.

        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* Selection Screen Definition
*======================================================================*
SELECTION-SCREEN BEGIN OF BLOCK b_file WITH FRAME TITLE t_b01.
  PARAMETERS:
    p_file   TYPE string LOWER CASE OBLIGATORY,
    p_appsrv AS CHECKBOX DEFAULT ' '.
SELECTION-SCREEN END OF BLOCK b_file.

SELECTION-SCREEN BEGIN OF BLOCK b_sap WITH FRAME TITLE t_b02.
  PARAMETERS:
    p_bukrs TYPE bukrs OBLIGATORY DEFAULT '1000',
    p_rldnr TYPE fins_ledger OBLIGATORY DEFAULT '0L',
    p_limit TYPE i DEFAULT 0.
SELECTION-SCREEN END OF BLOCK b_sap.

SELECTION-SCREEN BEGIN OF BLOCK b_mode WITH FRAME TITLE t_b03.
  PARAMETERS:
    p_dryrun RADIOBUTTON GROUP grp1 DEFAULT 'X',
    p_testrn RADIOBUTTON GROUP grp1,
    p_exec   RADIOBUTTON GROUP grp1.
SELECTION-SCREEN END OF BLOCK b_mode.

SELECTION-SCREEN BEGIN OF BLOCK b_out WITH FRAME TITLE t_b04.
  PARAMETERS:
    p_csv    AS CHECKBOX DEFAULT ' ',
    p_csvfil TYPE string LOWER CASE.
SELECTION-SCREEN END OF BLOCK b_out.

INITIALIZATION.
  t_b01 = '1. Excel (.xlsx) Input File (macOS & Windows)'.
  t_b02 = '2. SAP Document Selection Scope'.
  t_b03 = '3. Execution Mode'.
  t_b04 = '4. Optional Audit CSV Export'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  lcl_file_io=>browse_local_xlsx( CHANGING cv_path = p_file ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_csvfil.
  lcl_file_io=>browse_local_csv( CHANGING cv_path = p_csvfil ).

*======================================================================*
* Main Report Execution
*======================================================================*
START-OF-SELECTION.
  TRY.
      " 1. Upload binary .xlsx and parse OpenXML in memory
      DATA(lv_xlsx_bytes) = lcl_file_io=>load_xlsx_bytes(
        iv_path       = p_file
        iv_app_server = p_appsrv ).

      DATA(lt_sheet_rows) = lcl_xlsx_reader=>parse( lv_xlsx_bytes ).

      lcl_excel_parser=>extract_rows(
        EXPORTING
          it_sheet_rows = lt_sheet_rows
          iv_limit_docs = p_limit
        IMPORTING
          et_rows       = DATA(lt_excel_rows)
          et_errors     = DATA(lt_excel_errs)
          et_doc_keys   = DATA(lt_doc_keys) ).

      DATA(lv_mode) = COND char1(
        WHEN p_dryrun = abap_true THEN lcl_types=>c_mode-dry_run
        WHEN p_testrn = abap_true THEN lcl_types=>c_mode-test_run
        ELSE lcl_types=>c_mode-execute ).

      " 2. Safety confirmation popup before live database updates.
      "    A read-only dry-run pass resolves the real counts first.
      IF lv_mode = lcl_types=>c_mode-execute AND sy-batch = abap_false.
        DATA lv_answer TYPE c LENGTH 1.

        DATA(lt_preview) = NEW lcl_orchestrator(
          io_db      = NEW lcl_db_provider( )
          io_changer = NEW lcl_fi_doc_changer( ) )->run(
            iv_bukrs      = p_bukrs
            iv_rldnr      = p_rldnr
            iv_mode       = lcl_types=>c_mode-dry_run
            it_excel_rows = lt_excel_rows
            it_excel_errs = lt_excel_errs
            it_doc_keys   = lt_doc_keys ).

        DATA lt_planned_docs TYPE lcl_types=>tt_doc_keys.
        DATA(lv_n_planned) = 0.
        DATA(lv_n_skipped) = 0.
        DATA(lv_n_excel)   = 0.
        DATA(lv_n_unres)   = 0.
        LOOP AT lt_preview INTO DATA(ls_prev).
          CASE ls_prev-status.
            WHEN lcl_types=>c_status-planned.
              lv_n_planned = lv_n_planned + 1.
              READ TABLE lt_planned_docs TRANSPORTING NO FIELDS
                WITH KEY doc = ls_prev-doc year = ls_prev-year.
              IF sy-subrc <> 0.
                APPEND VALUE lcl_types=>ty_doc_key( doc = ls_prev-doc year = ls_prev-year )
                  TO lt_planned_docs.
              ENDIF.
            WHEN lcl_types=>c_status-skipped_already_set.
              lv_n_skipped = lv_n_skipped + 1.
            WHEN lcl_types=>c_status-excel_error.
              lv_n_excel = lv_n_excel + 1.
            WHEN OTHERS.
              lv_n_unres = lv_n_unres + 1.
          ENDCASE.
        ENDLOOP.

        IF lv_n_planned = 0.
          MESSAGE |Nothing to change: 0 planned lines ({ lv_n_skipped } already set, { lv_n_unres } unresolved, { lv_n_excel } Excel errors).| TYPE 'I'.
          lcl_alv_presenter=>display(
            iv_bukrs = p_bukrs
            iv_mode  = lcl_types=>c_mode-dry_run
            it_plan  = lt_preview ).
          RETURN.
        ENDIF.

        DATA(lv_question) =
          |Modify Assignment (ZUONR) in Company { p_bukrs }? | &&
          |Planned: { lv_n_planned } line(s) on { lines( lt_planned_docs ) } document(s). | &&
          |Skipped (already set): { lv_n_skipped }. | &&
          |Unresolved (not found/no match/ambiguous): { lv_n_unres }. | &&
          |Excel errors: { lv_n_excel }.|.

        CALL FUNCTION 'POPUP_TO_CONFIRM'
          EXPORTING
            titlebar              = 'Confirm Live FI Assignment Bulk Change'
            text_question         = lv_question
            text_button_1         = 'Execute'
            text_button_2         = 'Cancel'
            default_button        = '2'
            display_cancel_button = ' '
          IMPORTING
            answer                = lv_answer
          EXCEPTIONS
            OTHERS                = 1.
        IF lv_answer <> '1'.
          MESSAGE 'Execution cancelled by user.' TYPE 'S'.
          RETURN.
        ENDIF.
      ENDIF.

      " 3. Run orchestrator
      DATA(lo_orchestrator) = NEW lcl_orchestrator(
        io_db      = NEW lcl_db_provider( )
        io_changer = NEW lcl_fi_doc_changer( ) ).

      DATA(lt_plan) = lo_orchestrator->run(
        iv_bukrs      = p_bukrs
        iv_rldnr      = p_rldnr
        iv_mode       = lv_mode
        it_excel_rows = lt_excel_rows
        it_excel_errs = lt_excel_errs
        it_doc_keys   = lt_doc_keys ).

      " 4. Optional CSV export
      IF p_csv = abap_true AND p_csvfil IS NOT INITIAL.
        DATA(lt_csv) = lcl_orchestrator=>build_csv_lines( lt_plan ).
        lcl_file_io=>save_csv_file(
          iv_path       = p_csvfil
          iv_app_server = p_appsrv
          it_csv_lines  = lt_csv ).
      ENDIF.

      " 5. Display ALV result grid
      lcl_alv_presenter=>display(
        iv_bukrs = p_bukrs
        iv_mode  = lv_mode
        it_plan  = lt_plan ).

    CATCH lcx_bulk_error INTO DATA(lx_err).
      MESSAGE lx_err->get_text( ) TYPE 'I' DISPLAY LIKE 'E'.
  ENDTRY.

*======================================================================*
* ABAP Unit Test Suite (Ctrl+Shift+F10 in SE38 / Eclipse ADT)
*   Tests cross-platform .xlsx parsing, Excel validation, line
*   resolution, execution modes, rollback, verification, and CSV export.
*======================================================================*

*----------------------------------------------------------------------*
* Test Helper: Builds a real OpenXML .xlsx ZIP archive in memory
*----------------------------------------------------------------------*
CLASS lth_xlsx_builder DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    CLASS-METHODS build_xlsx
      IMPORTING
        iv_shared_strings_xml TYPE string OPTIONAL
        iv_sheet_xml          TYPE string
        iv_target_path        TYPE string DEFAULT 'worksheets/sheet1.xml'
      RETURNING
        VALUE(rv_xlsx)        TYPE xstring.
ENDCLASS.

CLASS lth_xlsx_builder IMPLEMENTATION.
  METHOD build_xlsx.
    DATA(lo_zip) = NEW cl_abap_zip( ).

    DATA(lv_wb_xml) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ` &&
      `xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` &&
      `<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>`.

    DATA(lv_rels_xml) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` &&
      |<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="{ iv_target_path }"/>| &&
      `</Relationships>`.

    lo_zip->add(
      name    = 'xl/workbook.xml'
      content = cl_abap_codepage=>convert_to( lv_wb_xml ) ).
    lo_zip->add(
      name    = 'xl/_rels/workbook.xml.rels'
      content = cl_abap_codepage=>convert_to( lv_rels_xml ) ).

    IF iv_shared_strings_xml IS NOT INITIAL.
      lo_zip->add(
        name    = 'xl/sharedStrings.xml'
        content = cl_abap_codepage=>convert_to( iv_shared_strings_xml ) ).
    ENDIF.

    lo_zip->add(
      name    = 'xl/worksheets/sheet1.xml'
      content = cl_abap_codepage=>convert_to( iv_sheet_xml ) ).

    rv_xlsx = lo_zip->save( ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Unit Test 1: Cross-Platform OpenXML .xlsx Parser (lcl_xlsx_reader)
*----------------------------------------------------------------------*
CLASS ltcl_xlsx_reader_test DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS test_col_letters_to_index   FOR TESTING.
    METHODS test_parse_openpyxl_mac_win FOR TESTING RAISING lcx_bulk_error.
    METHODS test_rich_text_and_phonetic FOR TESTING RAISING lcx_bulk_error.
    METHODS test_leading_slash_rel_path FOR TESTING RAISING lcx_bulk_error.
ENDCLASS.

CLASS ltcl_xlsx_reader_test IMPLEMENTATION.
  METHOD test_col_letters_to_index.
    cl_abap_unit_assert=>assert_equals( exp = 1  act = lcl_xlsx_reader=>col_letters_to_index( 'A1' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 6  act = lcl_xlsx_reader=>col_letters_to_index( 'F2' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 9  act = lcl_xlsx_reader=>col_letters_to_index( 'I49' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 26 act = lcl_xlsx_reader=>col_letters_to_index( 'Z10' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 27 act = lcl_xlsx_reader=>col_letters_to_index( 'AA1' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 28 act = lcl_xlsx_reader=>col_letters_to_index( '$AB$12' ) ).
  ENDMETHOD.

  METHOD test_parse_openpyxl_mac_win.
    " Mirrors actual cells from 'Contoh Data SAP for change Assignment.xlsx'
    " Includes shared strings (t="s"), inline strings (t="inlineStr"),
    " formula cached strings (t="str" like Y3), numeric cells, and sparse columns (A..AA).
    DATA(lv_ss) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="8" uniqueCount="8">` &&
      `<si><t>Doc Number + Year</t></si>` &&
      `<si><t>Source Data</t></si>` &&
      `<si><t>G/L Account</t></si>` &&
      `<si><t>Account</t></si>` &&
      `<si><t>KODE PROJECT</t></si>` &&
      `<si><t>1000041372019</t></si>` &&
      `<si><t>BEBAN</t></si>` &&
      `<si><t>P-1409SCC-TTES0601</t></si>` &&
      `</sst>`.

    DATA(lv_sheet) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<sheetData>` &&
      `<row r="1">` &&
      `<c r="A1" t="s"><v>0</v></c>` &&
      `<c r="B1" t="s"><v>1</v></c>` &&
      `<c r="F1" t="s"><v>2</v></c>` &&
      `<c r="G1" t="s"><v>3</v></c>` &&
      `<c r="I1" t="s"><v>4</v></c>` &&
      `</row>` &&
      `<row r="2">` &&
      `<c r="A2" t="s"><v>5</v></c>` &&
      `<c r="B2" t="s"><v>6</v></c>` &&
      `<c r="F2" t="inlineStr"><is><t>51376037</t></is></c>` &&
      `<c r="G2"><v>51376037</v></c>` &&
      `<c r="I2" t="s"><v>7</v></c>` &&
      `<c r="Y2" t="str"><f>W2</f><v>IDR</v></c>` &&
      `</row>` &&
      `</sheetData></worksheet>`.

    DATA(lv_xlsx) = lth_xlsx_builder=>build_xlsx(
      iv_shared_strings_xml = lv_ss
      iv_sheet_xml          = lv_sheet ).

    DATA(lt_rows) = lcl_xlsx_reader=>parse( lv_xlsx ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_rows ) ).

    READ TABLE lt_rows INTO DATA(ls_row2) INDEX 2.
    READ TABLE ls_row2-cells INTO DATA(ls_c_a) WITH TABLE KEY col = 1.
    READ TABLE ls_row2-cells INTO DATA(ls_c_f) WITH TABLE KEY col = 6.
    READ TABLE ls_row2-cells INTO DATA(ls_c_g) WITH TABLE KEY col = 7.
    READ TABLE ls_row2-cells INTO DATA(ls_c_i) WITH TABLE KEY col = 9.
    READ TABLE ls_row2-cells INTO DATA(ls_c_y) WITH TABLE KEY col = 25.

    cl_abap_unit_assert=>assert_equals( exp = '1000041372019'      act = ls_c_a-value ).
    cl_abap_unit_assert=>assert_equals( exp = '51376037'           act = ls_c_f-value ).
    cl_abap_unit_assert=>assert_equals( exp = '51376037'           act = ls_c_g-value ).
    cl_abap_unit_assert=>assert_equals( exp = 'P-1409SCC-TTES0601' act = ls_c_i-value ).
    cl_abap_unit_assert=>assert_equals( exp = 'IDR'                act = ls_c_y-value ).
  ENDMETHOD.

  METHOD test_rich_text_and_phonetic.
    " macOS and Windows Excel often save partially formatted cells as <si><r><t>...</t></r></si>
    " and may embed <rPh><t>phonetic</t></rPh> which must be ignored.
    DATA(lv_ss) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<si><r><t>P-1409</t></r><r><t>SCC-TTES0601</t></r><rPh><t>IGNORE_ME</t></rPh></si>` &&
      `</sst>`.

    DATA(lv_sheet) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData></worksheet>`.

    DATA(lv_xlsx) = lth_xlsx_builder=>build_xlsx(
      iv_shared_strings_xml = lv_ss
      iv_sheet_xml          = lv_sheet ).

    DATA(lt_rows) = lcl_xlsx_reader=>parse( lv_xlsx ).
    READ TABLE lt_rows INTO DATA(ls_r1) INDEX 1.
    READ TABLE ls_r1-cells INTO DATA(ls_c1) WITH TABLE KEY col = 1.
    cl_abap_unit_assert=>assert_equals( exp = 'P-1409SCC-TTES0601' act = ls_c1-value ).
  ENDMETHOD.

  METHOD test_leading_slash_rel_path.
    " Some OpenXML writers on macOS/Linux emit Target="/xl/worksheets/sheet1.xml"
    DATA(lv_sheet) =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>OK</t></is></c></row></sheetData></worksheet>`.

    DATA(lv_xlsx) = lth_xlsx_builder=>build_xlsx(
      iv_sheet_xml   = lv_sheet
      iv_target_path = '/xl/worksheets/sheet1.xml' ).

    DATA(lt_rows) = lcl_xlsx_reader=>parse( lv_xlsx ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( lt_rows ) ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Unit Test 2: Excel Business Rules & Limit (lcl_excel_parser)
*----------------------------------------------------------------------*
CLASS ltcl_excel_parser_test DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS build_sample_sheet
      RETURNING VALUE(rt_sheet) TYPE lcl_types=>tt_sheet_rows.

    METHODS test_valid_and_invalid_rows FOR TESTING RAISING lcx_bulk_error.
    METHODS test_limit_documents        FOR TESTING RAISING lcx_bulk_error.
    METHODS test_missing_header_raises  FOR TESTING.
ENDCLASS.

CLASS ltcl_excel_parser_test IMPLEMENTATION.
  METHOD build_sample_sheet.
    " Row 1: Headers matching Contoh Data SAP for change Assignment.xlsx
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 1
      cells   = VALUE #(
        ( col = 1 value = 'Doc Number + Year' )
        ( col = 2 value = 'Source Data' )
        ( col = 6 value = 'G/L Account' )
        ( col = 7 value = 'Account' )
        ( col = 9 value = 'KODE PROJECT' ) ) ) TO rt_sheet.

    " Row 2: Valid BEBAN line for doc 100004137 / 2019
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 2
      cells   = VALUE #(
        ( col = 1 value = '1000041372019' )
        ( col = 2 value = 'BEBAN' )
        ( col = 6 value = '51376037' )
        ( col = 7 value = '51376037' )
        ( col = 9 value = 'P-1409SCC-TTES0601' ) ) ) TO rt_sheet.

    " Row 3: Valid VENDOR line for doc 100004137 / 2019
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 3
      cells   = VALUE #(
        ( col = 1 value = '1000041372019' )
        ( col = 2 value = 'VENDOR' )
        ( col = 6 value = '20101002' )
        ( col = 7 value = '99000024' )
        ( col = 9 value = 'P-1409SCC-TTES0601' ) ) ) TO rt_sheet.

    " Row 4: Valid BEBAN line for 2nd doc 100010920 / 2019
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 4
      cells   = VALUE #(
        ( col = 1 value = '1000109202019' )
        ( col = 2 value = 'beban' )
        ( col = 6 value = '51376037' )
        ( col = 7 value = '51376037' )
        ( col = 9 value = 'P-1411SCC-TTES0717' ) ) ) TO rt_sheet.

    " Row 5: Invalid short key (< 5 chars)
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 5
      cells   = VALUE #(
        ( col = 1 value = '2019' )
        ( col = 2 value = 'BEBAN' )
        ( col = 6 value = '51376037' )
        ( col = 7 value = '51376037' )
        ( col = 9 value = 'P-1411SCC-TTES0717' ) ) ) TO rt_sheet.

    " Row 6: Invalid Source Data
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 6
      cells   = VALUE #(
        ( col = 1 value = '1000109372019' )
        ( col = 2 value = 'CUSTOMER' )
        ( col = 6 value = '51376037' )
        ( col = 7 value = '51376037' )
        ( col = 9 value = 'P-1411SCC-TTES0717' ) ) ) TO rt_sheet.

    " Row 7: Invalid KODE PROJECT (> 18 chars)
    APPEND VALUE lcl_types=>ty_sheet_row(
      row_num = 7
      cells   = VALUE #(
        ( col = 1 value = '1000109372019' )
        ( col = 2 value = 'BEBAN' )
        ( col = 6 value = '51376037' )
        ( col = 7 value = '51376037' )
        ( col = 9 value = 'PROJECT-CODE-TOO-LONG-123' ) ) ) TO rt_sheet.
  ENDMETHOD.

  METHOD test_valid_and_invalid_rows.
    lcl_excel_parser=>extract_rows(
      EXPORTING
        it_sheet_rows = build_sample_sheet( )
      IMPORTING
        et_rows       = DATA(lt_rows)
        et_errors     = DATA(lt_errors)
        et_doc_keys   = DATA(lt_keys) ).

    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( lt_rows ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( lt_errors ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_keys ) ).

    READ TABLE lt_rows INTO DATA(ls_first) INDEX 1.
    cl_abap_unit_assert=>assert_equals( exp = '0100004137' act = ls_first-doc ).
    cl_abap_unit_assert=>assert_equals( exp = '2019'       act = ls_first-year ).
    cl_abap_unit_assert=>assert_equals( exp = 'BEBAN'      act = ls_first-source ).
  ENDMETHOD.

  METHOD test_limit_documents.
    lcl_excel_parser=>extract_rows(
      EXPORTING
        it_sheet_rows = build_sample_sheet( )
        iv_limit_docs = 1
      IMPORTING
        et_rows       = DATA(lt_rows)
        et_doc_keys   = DATA(lt_keys) ).

    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( lt_keys ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_rows ) ).
  ENDMETHOD.

  METHOD test_missing_header_raises.
    DATA lt_bad_sheet TYPE lcl_types=>tt_sheet_rows.
    APPEND VALUE #(
      row_num = 1
      cells   = VALUE #( ( col = 1 value = 'Wrong Column' ) ) ) TO lt_bad_sheet.

    TRY.
        lcl_excel_parser=>extract_rows(
          EXPORTING it_sheet_rows = lt_bad_sheet
          IMPORTING et_rows       = DATA(lt_rows) ).
        cl_abap_unit_assert=>fail( 'Expected lcx_bulk_error for missing headers' ).
      CATCH lcx_bulk_error INTO DATA(lx_err).
        cl_abap_unit_assert=>assert_char_cp(
          act = lx_err->get_text( )
          exp = '*missing required columns*' ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Unit Test 3: Orchestrator, Line Resolution, Execution & CSV Export
*----------------------------------------------------------------------*
CLASS ltd_mock_db DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES lif_db_provider.
    DATA mt_items      TYPE lcl_types=>tt_acdoca_items.
    DATA mt_post_items TYPE lcl_types=>tt_acdoca_items.
ENDCLASS.

CLASS ltd_mock_db IMPLEMENTATION.
  METHOD lif_db_provider~fetch_items.
    IF iv_bypass_buffer = abap_true AND mt_post_items IS NOT INITIAL.
      rt_items = mt_post_items.
    ELSE.
      rt_items = mt_items.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_mock_changer DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES lif_doc_changer.
    DATA mv_calls        TYPE i.
    DATA mv_force_fail   TYPE abap_bool.
    DATA mt_last_changes TYPE lcl_types=>tt_item_changes.
ENDCLASS.

CLASS ltd_mock_changer IMPLEMENTATION.
  METHOD lif_doc_changer~change_document.
    mv_calls = mv_calls + 1.
    mt_last_changes = it_changes.
    IF mv_force_fail = abap_true.
      ev_ok      = abap_false.
      ev_message = 'Mock FI_DOCUMENT_CHANGE error (FINS_ACDOC_POST089)'.
    ELSE.
      ev_ok      = abap_true.
      ev_message = 'Mock change OK'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_orchestrator_test DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS test_all_resolution_statuses FOR TESTING.
    METHODS test_dry_run_vs_live_exec    FOR TESTING.
    METHODS test_error_and_csv_export    FOR TESTING.
ENDCLASS.

CLASS ltcl_orchestrator_test IMPLEMENTATION.
  METHOD test_all_resolution_statuses.
    " Doc 1 (0100004137/2019): 001 needs change, 002 already set
    " Doc 2 (0100010920/2019): ambiguous (two lines with same G/L) and no_match
    " Doc 3 (0100099999/2019): not in ACDOCA -> DOC_NOT_FOUND
    DATA(lo_db) = NEW ltd_mock_db( ).
    lo_db->mt_items = VALUE #(
      ( doc = '0100004137' year = '2019' item = '001' racct = '0051376037' assignment = 'BPR NTB Sumbawa' )
      ( doc = '0100004137' year = '2019' item = '002' racct = '0020101002' assignment = 'P-1409SCC-TTES0601' )
      ( doc = '0100010920' year = '2019' item = '001' racct = '0051376037' assignment = 'OLD1' )
      ( doc = '0100010920' year = '2019' item = '002' racct = '0051376037' assignment = 'OLD2' ) ).

    DATA(lt_rows) = VALUE lcl_types=>tt_excel_rows(
      ( xl_row = 2 doc = '0100004137' year = '2019' source = 'BEBAN'  gl = '51376037' target = 'P-1409SCC-TTES0601' )
      ( xl_row = 3 doc = '0100004137' year = '2019' source = 'VENDOR' gl = '20101002' target = 'P-1409SCC-TTES0601' )
      ( xl_row = 4 doc = '0100010920' year = '2019' source = 'BEBAN'  gl = '51376037' target = 'P-1411SCC-TTES0717' )
      ( xl_row = 5 doc = '0100010920' year = '2019' source = 'VENDOR' gl = '99999999' target = 'P-1411SCC-TTES0717' )
      ( xl_row = 6 doc = '0100099999' year = '2019' source = 'BEBAN'  gl = '51376037' target = 'P-1411SCC-TTES0717' ) ).

    DATA(lt_keys) = VALUE lcl_types=>tt_doc_keys(
      ( doc = '0100004137' year = '2019' )
      ( doc = '0100010920' year = '2019' )
      ( doc = '0100099999' year = '2019' ) ).

    DATA(lo_changer) = NEW ltd_mock_changer( ).
    DATA(lo_orch)    = NEW lcl_orchestrator( io_db = lo_db io_changer = lo_changer ).

    DATA(lt_plan) = lo_orch->run(
      iv_bukrs      = '1000'
      iv_mode       = lcl_types=>c_mode-dry_run
      it_excel_rows = lt_rows
      it_doc_keys   = lt_keys ).

    cl_abap_unit_assert=>assert_equals( exp = 0 act = lo_changer->mv_calls ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = lines( lt_plan ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'PLANNED'             act = lt_plan[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'SKIPPED_ALREADY_SET' act = lt_plan[ 2 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'AMBIGUOUS'           act = lt_plan[ 3 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'NO_MATCH'            act = lt_plan[ 4 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'DOC_NOT_FOUND'       act = lt_plan[ 5 ]-status ).
  ENDMETHOD.

  METHOD test_dry_run_vs_live_exec.
    DATA(lo_db) = NEW ltd_mock_db( ).
    lo_db->mt_items = VALUE #(
      ( doc = '0100004137' year = '2019' item = '001' racct = '0051376037' assignment = 'BPR NTB Sumbawa' )
      ( doc = '0100004137' year = '2019' item = '002' racct = '0020101002' assignment = 'BPR NTB Sumbawa' ) ).
    lo_db->mt_post_items = VALUE #(
      ( doc = '0100004137' year = '2019' item = '001' racct = '0051376037' assignment = 'P-1409SCC-TTES0601' )
      ( doc = '0100004137' year = '2019' item = '002' racct = '0020101002' assignment = 'P-1409SCC-TTES0601' ) ).

    DATA(lt_rows) = VALUE lcl_types=>tt_excel_rows(
      ( xl_row = 2 doc = '0100004137' year = '2019' source = 'BEBAN'  gl = '51376037' target = 'P-1409SCC-TTES0601' )
      ( xl_row = 3 doc = '0100004137' year = '2019' source = 'VENDOR' gl = '20101002' target = 'P-1409SCC-TTES0601' ) ).
    DATA(lt_keys) = VALUE lcl_types=>tt_doc_keys( ( doc = '0100004137' year = '2019' ) ).

    DATA(lo_changer) = NEW ltd_mock_changer( ).
    DATA(lo_orch)    = NEW lcl_orchestrator( io_db = lo_db io_changer = lo_changer ).

    DATA(lt_plan) = lo_orch->run(
      iv_bukrs      = '1000'
      iv_mode       = lcl_types=>c_mode-execute
      it_excel_rows = lt_rows
      it_doc_keys   = lt_keys ).

    cl_abap_unit_assert=>assert_equals( exp = 1         act = lo_changer->mv_calls ).
    cl_abap_unit_assert=>assert_equals( exp = 'CHANGED' act = lt_plan[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'CHANGED' act = lt_plan[ 2 ]-status ).
  ENDMETHOD.

  METHOD test_error_and_csv_export.
    DATA(lo_db) = NEW ltd_mock_db( ).
    lo_db->mt_items = VALUE #(
      ( doc = '0100004137' year = '2019' item = '001' racct = '0051376037' assignment = 'BPR NTB Sumbawa' ) ).

    DATA(lt_rows) = VALUE lcl_types=>tt_excel_rows(
      ( xl_row = 2 doc = '0100004137' year = '2019' source = 'BEBAN' gl = '51376037' target = 'P-1409SCC-TTES0601' ) ).
    DATA(lt_keys) = VALUE lcl_types=>tt_doc_keys( ( doc = '0100004137' year = '2019' ) ).

    DATA(lo_changer) = NEW ltd_mock_changer( ).
    lo_changer->mv_force_fail = abap_true.
    DATA(lo_orch) = NEW lcl_orchestrator( io_db = lo_db io_changer = lo_changer ).

    DATA(lt_plan) = lo_orch->run(
      iv_bukrs      = '1000'
      iv_mode       = lcl_types=>c_mode-execute
      it_excel_rows = lt_rows
      it_doc_keys   = lt_keys ).

    cl_abap_unit_assert=>assert_equals( exp = 'SEND_ERROR' act = lt_plan[ 1 ]-status ).

    DATA(lt_csv) = lcl_orchestrator=>build_csv_lines( lt_plan ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_csv ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'doc,year,item,source,old,target,status,message'
      act = lt_csv[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp(
      act = lt_csv[ 2 ]
      exp = '0100004137,2019,001,BEBAN,BPR NTB Sumbawa,P-1409SCC-TTES0601,SEND_ERROR,*' ).
  ENDMETHOD.
ENDCLASS.
