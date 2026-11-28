" Same logic as ZRFC_FI_CHANGE_ASSIGN / plan section 3.4: FI_DOCUMENT_CHANGE selects ONE line
" per call (I_BUZEI); all lines of a document share one LUW.
CLASS zcl_fi_doc_changer DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_fi_doc_changer.
ENDCLASS.


CLASS zcl_fi_doc_changer IMPLEMENTATION.

  METHOD zif_fi_doc_changer~change_document.
    DATA lt_accchg TYPE STANDARD TABLE OF accchg.
    DATA lv_msg    TYPE string.

    CALL FUNCTION 'ENQUEUE_EFBKPF'
      EXPORTING
        bukrs = iv_bukrs
        belnr = iv_belnr
        gjahr = iv_gjahr
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      rs_result = VALUE #( success = abap_false
                           message = zcl_fi_upl_msg=>text( iv_no = '019' iv_v1 = sy-msgv1 ) ).
      RETURN.
    ENDIF.

    LOOP AT it_changes ASSIGNING FIELD-SYMBOL(<c>).
      lt_accchg = VALUE #( ( fdname = 'ZUONR' oldval = <c>-old_val newval = <c>-new_val ) ).

      CALL FUNCTION 'FI_DOCUMENT_CHANGE'
        EXPORTING
          i_buzei              = <c>-buzei
          i_bukrs              = iv_bukrs
          i_belnr              = iv_belnr
          i_gjahr              = iv_gjahr
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
        CLEAR lv_msg.
        IF sy-msgid IS NOT INITIAL.
          MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
                  WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_msg.
        ELSE.
          lv_msg = |FI_DOCUMENT_CHANGE sy-subrc { sy-subrc }|.
        ENDIF.
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        CALL FUNCTION 'DEQUEUE_EFBKPF'
          EXPORTING
            bukrs = iv_bukrs
            belnr = iv_belnr
            gjahr = iv_gjahr.
        rs_result = VALUE #( success = abap_false
                             message = |{ zcl_fi_upl_msg=>text( iv_no = '022' iv_v1 = |{ <c>-buzei }| ) } { lv_msg }| ).
        RETURN.
      ENDIF.
    ENDLOOP.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.
    CALL FUNCTION 'DEQUEUE_EFBKPF'
      EXPORTING
        bukrs = iv_bukrs
        belnr = iv_belnr
        gjahr = iv_gjahr.
    rs_result-success = abap_true.
  ENDMETHOD.

ENDCLASS.
