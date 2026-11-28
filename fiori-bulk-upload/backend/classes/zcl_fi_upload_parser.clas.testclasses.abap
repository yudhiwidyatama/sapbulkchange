CLASS ltcl_parser DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS c_uuid TYPE sysuuid_x16 VALUE '00000000000000000000000000000001'.
    METHODS header RETURNING VALUE(rs_row) TYPE zcl_fi_xlsx_reader=>ty_row.
    METHODS row
      IMPORTING iv_no TYPE i it_cells TYPE zcl_fi_xlsx_reader=>tt_cells
      RETURNING VALUE(rs_row) TYPE zcl_fi_xlsx_reader=>ty_row.

    METHODS dates         FOR TESTING.
    METHODS numc          FOR TESTING.
    METHODS valid_row     FOR TESTING RAISING zcx_fi_upload.
    METHODS year_default  FOR TESTING RAISING zcx_fi_upload.
    METHODS row_errors    FOR TESTING RAISING zcx_fi_upload.
    METHODS duplicate_row FOR TESTING RAISING zcx_fi_upload.
    METHODS blank_row     FOR TESTING RAISING zcx_fi_upload.
    METHODS missing_header FOR TESTING.
    METHODS too_many_rows  FOR TESTING.
ENDCLASS.


CLASS ltcl_parser IMPLEMENTATION.

  METHOD header.
    rs_row = VALUE #( row_no = 1 cells = VALUE #( ( `Document Number` ) ( `Fiscal Year` ) ( `Line Item` )
      ( `Document Type` ) ( `Posting Date` ) ( `G/L Account` ) ( `KODE PROJECT` ) ( `Source Data` ) ) ).
  ENDMETHOD.

  METHOD row.
    rs_row = VALUE #( row_no = iv_no cells = it_cells ).
  ENDMETHOD.

  METHOD dates.
    cl_abap_unit_assert=>assert_equals( exp = '20190131' act = zcl_fi_upload_parser=>parse_excel_date( '43496' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '20190131' act = zcl_fi_upload_parser=>parse_excel_date( '43496.0' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '20190131' act = zcl_fi_upload_parser=>parse_excel_date( '20190131' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '20190131' act = zcl_fi_upload_parser=>parse_excel_date( '2019-01-31' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '20190228' act = zcl_fi_upload_parser=>parse_excel_date( '28.02.2019' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '20190228' act = zcl_fi_upload_parser=>parse_excel_date( '28/02/2019' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>parse_excel_date( '2019-02-30' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>parse_excel_date( '31.04.2019' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>parse_excel_date( 'garbage' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>parse_excel_date( '' ) ).
  ENDMETHOD.

  METHOD numc.
    cl_abap_unit_assert=>assert_equals( exp = `001`        act = zcl_fi_upload_parser=>normalize_numc( iv_text = '1'   iv_len = 3 ) ).
    cl_abap_unit_assert=>assert_equals( exp = `001`        act = zcl_fi_upload_parser=>normalize_numc( iv_text = '1.0' iv_len = 3 ) ).
    cl_abap_unit_assert=>assert_equals( exp = `0000001000` act = zcl_fi_upload_parser=>normalize_numc( iv_text = '1E3' iv_len = 10 ) ).
    cl_abap_unit_assert=>assert_equals( exp = `1900000001` act = zcl_fi_upload_parser=>normalize_numc( iv_text = '1900000001' iv_len = 10 ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>normalize_numc( iv_text = '1000' iv_len = 3 ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>normalize_numc( iv_text = '1.5'  iv_len = 3 ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>normalize_numc( iv_text = 'abc'  iv_len = 3 ) ).
    cl_abap_unit_assert=>assert_initial( zcl_fi_upload_parser=>normalize_numc( iv_text = '-1'   iv_len = 3 ) ).
  ENDMETHOD.

  METHOD valid_row.
    DATA(lt_items) = NEW zcl_fi_upload_parser( )->parse(
      it_rows = VALUE #( ( header( ) )
        ( row( iv_no = 2 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `1` ) ( `sa` ) ( `43496` ) ( `0000600000` ) ( `PRJ-1` ) ( `vendor` ) ) ) ) )
      iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( lt_items ) ).
    DATA(ls_i) = lt_items[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = 'NEW'        act = ls_i-status ).
    cl_abap_unit_assert=>assert_equals( exp = '1900000001' act = ls_i-belnr ).
    cl_abap_unit_assert=>assert_equals( exp = '2019'       act = ls_i-gjahr ).
    cl_abap_unit_assert=>assert_equals( exp = '001'        act = ls_i-buzei ).
    cl_abap_unit_assert=>assert_equals( exp = 'SA'         act = ls_i-blart ).
    cl_abap_unit_assert=>assert_equals( exp = '20190131'   act = ls_i-budat ).
    cl_abap_unit_assert=>assert_equals( exp = 'VENDOR'     act = ls_i-source_data ).
    cl_abap_unit_assert=>assert_equals( exp = 2            act = ls_i-row_no ).
  ENDMETHOD.

  METHOD year_default.
    " Fiscal Year empty -> year of posting date; Source Data empty -> BEBAN
    DATA(lt_items) = NEW zcl_fi_upload_parser( )->parse(
      it_rows = VALUE #( ( header( ) )
        ( row( iv_no = 2 it_cells = VALUE #( ( `19` ) ( `` ) ( `2` ) ( `SA` ) ( `2021-05-17` ) ( `600000` ) ( `P` ) ) ) ) )
      iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
    cl_abap_unit_assert=>assert_equals( exp = '0000000019' act = lt_items[ 1 ]-belnr ).
    cl_abap_unit_assert=>assert_equals( exp = '2021'       act = lt_items[ 1 ]-gjahr ).
    cl_abap_unit_assert=>assert_equals( exp = 'BEBAN'      act = lt_items[ 1 ]-source_data ).
    cl_abap_unit_assert=>assert_equals( exp = 'NEW'        act = lt_items[ 1 ]-status ).
  ENDMETHOD.

  METHOD row_errors.
    DATA(lt_items) = NEW zcl_fi_upload_parser( )->parse(
      it_rows = VALUE #( ( header( ) )
        ( row( iv_no = 2 it_cells = VALUE #( ( `` ) ( `2019` ) ( `1` ) ( `SA` ) ( `43496` ) ( `600000` ) ( `P` ) ( `` ) ) ) )
        ( row( iv_no = 3 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `0` ) ( `SA` ) ( `43496` ) ( `600000` ) ( `P` ) ( `` ) ) ) )
        ( row( iv_no = 4 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `1` ) ( `SA` ) ( `nope` ) ( `600000` ) ( `P` ) ( `` ) ) ) )
        ( row( iv_no = 5 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `1` ) ( `SA` ) ( `43496` ) ( `600000` ) ( `0123456789ABCDEFGHI` ) ( `` ) ) ) )
        ( row( iv_no = 6 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `1` ) ( `SA` ) ( `43496` ) ( `600000` ) ( `P` ) ( `XYZ` ) ) ) )
        ( row( iv_no = 7 it_cells = VALUE #( ( `1900000001` ) ( `2019` ) ( `1` ) ( `SA` ) ( `43496` ) ( `` ) ( `P` ) ( `` ) ) ) ) )
      iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = lines( lt_items ) ).
    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<i>).
      cl_abap_unit_assert=>assert_equals( exp = 'EXCEL_ERROR' act = <i>-status msg = |row { <i>-row_no }| ).
      cl_abap_unit_assert=>assert_not_initial( act = <i>-message msg = |row { <i>-row_no } message| ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( exp = 'Document Number' act = lt_items[ 1 ]-error_field ).
    cl_abap_unit_assert=>assert_equals( exp = 'Line Item'       act = lt_items[ 2 ]-error_field ).
    cl_abap_unit_assert=>assert_equals( exp = 'Posting Date'    act = lt_items[ 3 ]-error_field ).
    cl_abap_unit_assert=>assert_equals( exp = 'KODE PROJECT'    act = lt_items[ 4 ]-error_field ).
    cl_abap_unit_assert=>assert_equals( exp = 'Source Data'     act = lt_items[ 5 ]-error_field ).
    cl_abap_unit_assert=>assert_equals( exp = 'G/L Account'     act = lt_items[ 6 ]-error_field ).
  ENDMETHOD.

  METHOD duplicate_row.
    DATA(lt_cells) = VALUE zcl_fi_xlsx_reader=>tt_cells( ( `1900000001` ) ( `2019` ) ( `1` ) ( `SA` ) ( `43496` ) ( `600000` ) ( `P` ) ).
    DATA(lt_items) = NEW zcl_fi_upload_parser( )->parse(
      it_rows = VALUE #( ( header( ) ) ( row( iv_no = 2 it_cells = lt_cells ) ) ( row( iv_no = 9 it_cells = lt_cells ) ) )
      iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
    cl_abap_unit_assert=>assert_equals( exp = 'NEW'         act = lt_items[ 1 ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'EXCEL_ERROR' act = lt_items[ 2 ]-status ).
    cl_abap_unit_assert=>assert_char_cp( act = lt_items[ 2 ]-message exp = '*2*' ).   " names first row
  ENDMETHOD.

  METHOD blank_row.
    DATA(lt_items) = NEW zcl_fi_upload_parser( )->parse(
      it_rows = VALUE #( ( header( ) ) ( row( iv_no = 2 it_cells = VALUE #( ( `` ) ( `` ) ( `` ) ) ) ) )
      iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
    cl_abap_unit_assert=>assert_initial( lt_items ).
  ENDMETHOD.

  METHOD missing_header.
    TRY.
        NEW zcl_fi_upload_parser( )->parse(
          it_rows = VALUE #( ( row_no = 1 cells = VALUE #( ( `Document Number` ) ( `Line Item` ) ) ) )
          iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
        cl_abap_unit_assert=>fail( 'exception expected' ).
      CATCH zcx_fi_upload INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( exp = '002' act = lx->if_t100_message~t100key-msgno ).
        cl_abap_unit_assert=>assert_char_cp( act = lx->if_t100_dyn_msg~msgv1 exp = '*KODE PROJECT*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD too_many_rows.
    " row limit is a constructor parameter so the test does not need 50,001 rows
    TRY.
        NEW zcl_fi_upload_parser( iv_max_rows = 2 )->parse(
          it_rows = VALUE #( ( header( ) ) ( row_no = 2 ) ( row_no = 3 ) ( row_no = 4 ) )
          iv_batch_uuid = c_uuid iv_bukrs = '1000' ).
        cl_abap_unit_assert=>fail( 'exception expected' ).
      CATCH zcx_fi_upload INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( exp = '003' act = lx->if_t100_message~t100key-msgno ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
