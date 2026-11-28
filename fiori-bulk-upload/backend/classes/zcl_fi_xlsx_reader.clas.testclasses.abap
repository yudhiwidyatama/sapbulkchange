CLASS ltcl_xlsx_reader DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS build_xlsx RETURNING VALUE(rv_xlsx) TYPE xstring.
    METHODS add_part IMPORTING io_zip TYPE REF TO cl_abap_zip iv_name TYPE string iv_xml TYPE string.
    METHODS col_letters FOR TESTING.
    METHODS parse_cells FOR TESTING RAISING zcx_fi_upload.
    METHODS not_a_zip   FOR TESTING.
ENDCLASS.


CLASS ltcl_xlsx_reader IMPLEMENTATION.

  METHOD add_part.
    io_zip->add( name = iv_name content = cl_abap_codepage=>convert_to( iv_xml ) ).
  ENDMETHOD.

  METHOD build_xlsx.
    DATA(lo_zip) = NEW cl_abap_zip( ).
    add_part( io_zip = lo_zip iv_name = `xl/workbook.xml`
      iv_xml = `<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" `
            && `xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">`
            && `<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>` ).
    add_part( io_zip = lo_zip iv_name = `xl/_rels/workbook.xml.rels`
      iv_xml = `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`
            && `<Relationship Id="rId1" Type="worksheet" Target="/xl/worksheets/sheet1.xml"/></Relationships>` ).
    add_part( io_zip = lo_zip iv_name = `xl/sharedStrings.xml`
      iv_xml = `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">`
            && `<si><t>Hello</t></si>`
            && `<si><r><t>Rich </t></r><r><t>Text</t></r><rPh sb="0" eb="1"><t>PHON</t></rPh></si></sst>` ).
    add_part( io_zip = lo_zip iv_name = `xl/worksheets/sheet1.xml`
      iv_xml = `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`
            && `<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c>`
            && `<c r="AA1" t="inlineStr"><is><t>Inl</t></is></c></row>`
            && `<row r="2"><c r="A2"><v>43496</v></c><c r="B2" t="str"><f>1+1</f><v>fx</v></c></row>`
            && `<row r="3"/></sheetData></worksheet>` ).
    rv_xlsx = lo_zip->save( ).
  ENDMETHOD.

  METHOD col_letters.
    cl_abap_unit_assert=>assert_equals( exp = 1  act = zcl_fi_xlsx_reader=>col_letters_to_index( 'A' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 26 act = zcl_fi_xlsx_reader=>col_letters_to_index( 'Z' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 27 act = zcl_fi_xlsx_reader=>col_letters_to_index( 'AA' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 27 act = zcl_fi_xlsx_reader=>col_letters_to_index( 'AA12' ) ).
  ENDMETHOD.

  METHOD parse_cells.
    DATA(lt_rows) = zcl_fi_xlsx_reader=>parse( build_xlsx( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_rows ) msg = 'empty row 3 is dropped' ).
    DATA(ls_r1) = lt_rows[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_r1-row_no ).
    cl_abap_unit_assert=>assert_equals( exp = 27 act = lines( ls_r1-cells ) msg = 'sparse columns keep position' ).
    cl_abap_unit_assert=>assert_equals( exp = `Hello`     act = ls_r1-cells[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = ``          act = ls_r1-cells[ 2 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `Rich Text` act = ls_r1-cells[ 3 ] msg = 'rich text joined, phonetic run ignored' ).
    cl_abap_unit_assert=>assert_equals( exp = `Inl`       act = ls_r1-cells[ 27 ] ).
    DATA(ls_r2) = lt_rows[ 2 ].
    cl_abap_unit_assert=>assert_equals( exp = `43496` act = ls_r2-cells[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `fx`    act = ls_r2-cells[ 2 ] ).
  ENDMETHOD.

  METHOD not_a_zip.
    TRY.
        zcl_fi_xlsx_reader=>parse( cl_abap_codepage=>convert_to( `this is not a zip` ) ).
        cl_abap_unit_assert=>fail( 'exception expected' ).
      CATCH zcx_fi_upload.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
