" Resolves a ZFI_BULK message to text in the logon language (i18n via message class).
CLASS zcl_fi_upl_msg DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS text
      IMPORTING iv_no          TYPE symsgno
                iv_v1          TYPE csequence OPTIONAL
                iv_v2          TYPE csequence OPTIONAL
                iv_v3          TYPE csequence OPTIONAL
                iv_v4          TYPE csequence OPTIONAL
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_fi_upl_msg IMPLEMENTATION.

  METHOD text.
    DATA lv_text TYPE c LENGTH 220.
    MESSAGE ID zif_fi_upl_types=>gc_msgid TYPE 'E' NUMBER iv_no
            WITH iv_v1 iv_v2 iv_v3 iv_v4 INTO lv_text.
    rv_text = lv_text.
  ENDMETHOD.

ENDCLASS.
