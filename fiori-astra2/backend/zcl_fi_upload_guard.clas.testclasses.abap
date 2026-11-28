CLASS ltcl_upload_guard DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS workbook_boundary FOR TESTING.
    METHODS rows_boundary FOR TESTING.
    METHODS owner_boundary FOR TESTING.
ENDCLASS.

CLASS ltcl_upload_guard IMPLEMENTATION.
  METHOD workbook_boundary.
    DATA body TYPE xstring.
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>accepts_workbook_size( body ) ).
    DATA(byte) = CONV xstring( 'AA' ).
    " Build a 1 MiB block by doubling binary data, then assemble the exact cap.
    DATA(block) = byte.
    DO 20 TIMES.
      CONCATENATE block block INTO block IN BYTE MODE.
    ENDDO.
    DO 20 TIMES.
      CONCATENATE body block INTO body IN BYTE MODE.
    ENDDO.
    cl_abap_unit_assert=>assert_equals( exp = 20971520 act = xstrlen( body ) ).
    cl_abap_unit_assert=>assert_true( zcl_fi_upload_guard=>accepts_workbook_size( body ) ).
    CONCATENATE body byte INTO body IN BYTE MODE.
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>accepts_workbook_size( body ) ).
  ENDMETHOD.

  METHOD rows_boundary.
    cl_abap_unit_assert=>assert_true( zcl_fi_upload_guard=>accepts_row_count( 49999 ) ).
    cl_abap_unit_assert=>assert_true( zcl_fi_upload_guard=>accepts_row_count( 50000 ) ).
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>accepts_row_count( 50001 ) ).
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>accepts_row_count( -1 ) ).
  ENDMETHOD.

  METHOD owner_boundary.
    cl_abap_unit_assert=>assert_true( zcl_fi_upload_guard=>is_request_owner(
      stored_client = sy-mandt stored_requester = sy-uname ) ).
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>is_request_owner(
      stored_client = sy-mandt stored_requester = space ) ).
    DATA(other_client) = COND mandt( WHEN sy-mandt = '001' THEN '002' ELSE '001' ).
    cl_abap_unit_assert=>assert_false( zcl_fi_upload_guard=>is_request_owner(
      stored_client = other_client stored_requester = sy-uname ) ).
  ENDMETHOD.
ENDCLASS.
