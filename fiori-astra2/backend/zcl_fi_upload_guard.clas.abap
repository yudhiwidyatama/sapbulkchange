CLASS zcl_fi_upload_guard DEFINITION PUBLIC FINAL CREATE PRIVATE.
  PUBLIC SECTION.
    CONSTANTS max_workbook_bytes TYPE i VALUE 20971520.
    CONSTANTS max_data_rows TYPE i VALUE 50000.
    CLASS-METHODS accepts_workbook_size
      IMPORTING body TYPE xstring
      RETURNING VALUE(allowed) TYPE abap_bool.
    CLASS-METHODS accepts_row_count
      IMPORTING nonblank_data_rows TYPE i
      RETURNING VALUE(allowed) TYPE abap_bool.
    CLASS-METHODS is_request_owner
      IMPORTING stored_client TYPE mandt stored_requester TYPE syuname
      RETURNING VALUE(allowed) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_upload_guard IMPLEMENTATION.
  METHOD accepts_workbook_size.
    " Raw XLSX bytes, not base64 length or a client-declared Content-Length.
    DATA(bytes) = xstrlen( body ).
    allowed = xsdbool( bytes > 0 AND bytes <= max_workbook_bytes ).
  ENDMETHOD.

  METHOD accepts_row_count.
    " Called after each nonblank first-sheet data row, before row-level validation.
    " Includes invalid rows; excludes the header. Empty workbook is rejected separately.
    allowed = xsdbool( nonblank_data_rows >= 0 AND nonblank_data_rows <= max_data_rows ).
  ENDMETHOD.

  METHOD is_request_owner.
    " Only pass server-persisted owner fields. This is NOT an FI authorization check.
    allowed = xsdbool( stored_requester IS NOT INITIAL AND stored_client = sy-mandt
                       AND stored_requester = sy-uname ).
  ENDMETHOD.
ENDCLASS.
