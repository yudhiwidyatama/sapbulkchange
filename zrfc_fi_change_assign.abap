*&---------------------------------------------------------------------*
*& Function module ZRFC_FI_CHANGE_ASSIGN  (Remote-Enabled Module)
*&---------------------------------------------------------------------*
*& Purpose : change the Assignment field (BSEG-ZUONR) of lines of ONE
*&           posted FI document per call. Thin wrapper around the
*&           standard FI_DOCUMENT_CHANGE (same logic as FB02 field change),
*&           called from Python over SOAP /sap/bc/soap/rfc, same pattern
*&           as zrfc_pr_change / create_pr_bapi.py.
*&
*& ---- DDIC objects to create first (SE11) ---------------------------
*&  Structure ZFIS_ASSIGN_CHG
*&      BUZEI   type BUZEI      (item number, NUMC 3)
*&      ZUONR   type DZUONR     (Assignment, CHAR 18)
*&      OLDVAL  type DZUONR     (optional: expected current value, guard)
*&
*& ---- SE37 interface (Remote-Enabled Module = X, "Pass by value") ----
*&  IMPORTING
*&     VALUE(IV_BUKRS)   TYPE BUKRS
*&     VALUE(IV_BELNR)   TYPE BELNR_D
*&     VALUE(IV_GJAHR)   TYPE GJAHR
*&     VALUE(IV_TESTRUN) TYPE BAPIFLAG-BAPIFLAG OPTIONAL
*&  TABLES
*&      IT_ITEMS  STRUCTURE ZFIS_ASSIGN_CHG
*&      RETURN    STRUCTURE BAPIRET2 OPTIONAL
*&
*& ---- Verify before activating (ADT was offline when this was drafted)
*&  (ACCCHG components and FI_DOCUMENT_CHANGE parameters verified via ADT:
*&   ACCCHG = FDNAME/OLDVAL/NEWVAL; item selected by I_BUZEI, one call per line.)
*&  3. FB02 on one test document: ZUONR must be editable for that line
*&     (OB32 / field status; cleared items may be restricted).
*&  4. Authorization: calling user needs F_BKPF_BUK (ACTVT 02) for the
*&     company code, plus S_RFC for the function group.
*&---------------------------------------------------------------------*
FUNCTION zrfc_fi_change_assign.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_BUKRS) TYPE  BUKRS
*"     VALUE(IV_BELNR) TYPE  BELNR_D
*"     VALUE(IV_GJAHR) TYPE  GJAHR
*"     VALUE(IV_TESTRUN) TYPE  BAPIFLAG-BAPIFLAG OPTIONAL
*"  TABLES
*"      IT_ITEMS STRUCTURE  ZFIS_ASSIGN_CHG
*"      RETURN STRUCTURE  BAPIRET2 OPTIONAL
*"----------------------------------------------------------------------

  TYPES: BEGIN OF ty_work,
           buzei TYPE buzei,
           old   TYPE dzuonr,
           new   TYPE dzuonr,
         END OF ty_work.
  DATA: lt_work   TYPE STANDARD TABLE OF ty_work,
        lt_accchg TYPE STANDARD TABLE OF accchg,
        ls_accchg TYPE accchg,
        ls_bseg   TYPE bseg,
        lv_ok     TYPE abap_bool VALUE abap_true.

  REFRESH return.

  DEFINE add_msg.
    CLEAR return.
    return-type       = &1.
    return-id         = 'ZFI'.
    return-number     = '000'.
    return-message    = &2.
    return-message_v1 = &3.
    return-message_v2 = &4.
    APPEND return.
    IF &1 CA 'EA'.
      lv_ok = abap_false.
    ENDIF.
  END-OF-DEFINITION.

* ---- 1. input checks --------------------------------------------------
  IF it_items[] IS INITIAL.
    add_msg 'E' 'No items supplied' '' ''.
    RETURN.
  ENDIF.

  IF iv_bukrs IS INITIAL OR iv_belnr IS INITIAL OR iv_gjahr IS INITIAL.
    add_msg 'E' 'Company code, document number and fiscal year are required' '' ''.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
    ID 'BUKRS' FIELD iv_bukrs
    ID 'ACTVT' FIELD '02'.
  IF sy-subrc <> 0.
    add_msg 'E' 'No authorization to change documents in company code' iv_bukrs ''.
    RETURN.
  ENDIF.

  SELECT SINGLE bukrs, belnr, gjahr, stblg
    FROM bkpf
    INTO @DATA(ls_bkpf)
    WHERE bukrs = @iv_bukrs
      AND belnr = @iv_belnr
      AND gjahr = @iv_gjahr.
  IF sy-subrc <> 0.
    add_msg 'E' 'Document not found' iv_belnr iv_gjahr.
    RETURN.
  ENDIF.

* ---- 2. per-item checks, build change table ---------------------------
  LOOP AT it_items.
    SELECT SINGLE zuonr, augbl
      FROM bseg
      INTO ( @ls_bseg-zuonr, @ls_bseg-augbl )
      WHERE bukrs = @iv_bukrs
        AND belnr = @iv_belnr
        AND gjahr = @iv_gjahr
        AND buzei = @it_items-buzei.
    IF sy-subrc <> 0.
      add_msg 'E' 'Line item not found' iv_belnr it_items-buzei.
      CONTINUE.
    ENDIF.

*   optional guard: caller states what it expects to be there now
    IF it_items-oldval IS NOT INITIAL AND it_items-oldval <> ls_bseg-zuonr.
      add_msg 'E' 'Current Assignment differs from expected value' it_items-buzei ls_bseg-zuonr.
      CONTINUE.
    ENDIF.

    IF ls_bseg-zuonr = it_items-zuonr.
      add_msg 'W' 'Assignment already has the requested value, skipped' it_items-buzei ''.
      CONTINUE.
    ENDIF.

    IF ls_bseg-augbl IS NOT INITIAL.
      add_msg 'W' 'Line is cleared; change may be rejected by field status' it_items-buzei ls_bseg-augbl.
    ENDIF.

    APPEND VALUE #( buzei = it_items-buzei
                    old   = ls_bseg-zuonr
                    new   = it_items-zuonr ) TO lt_work.
  ENDLOOP.

* any error => nothing is changed for this document (all or nothing)
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  IF lt_work[] IS INITIAL.
    add_msg 'S' 'Nothing to change' '' ''.
    RETURN.
  ENDIF.

  IF iv_testrun IS NOT INITIAL.
    add_msg 'S' 'Test run: validation OK, nothing changed' '' ''.
    RETURN.
  ENDIF.

* ---- 3. change: FI_DOCUMENT_CHANGE selects ONE line per call (I_BUZEI);
*        ACCCHG has no item number. All lines share one LUW. -------------
  LOOP AT lt_work INTO DATA(ls_work).
    REFRESH lt_accchg.
    CLEAR ls_accchg.
    ls_accchg-fdname = 'ZUONR'.
    ls_accchg-oldval = ls_work-old.
    ls_accchg-newval = ls_work-new.
    APPEND ls_accchg TO lt_accchg.

    CALL FUNCTION 'FI_DOCUMENT_CHANGE'
      EXPORTING
        i_buzei              = ls_work-buzei
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
      CLEAR return.
      return-type       = 'E'.
      return-id         = sy-msgid.
      return-number     = sy-msgno.
      return-message_v1 = sy-msgv1.
      return-message_v2 = sy-msgv2.
      return-message_v3 = sy-msgv3.
      return-message_v4 = sy-msgv4.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO return-message.
      ELSE.
        return-message = |FI_DOCUMENT_CHANGE failed for item { ls_work-buzei }, sy-subrc { sy-subrc }|.
      ENDIF.
      APPEND return.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      RETURN.
    ENDIF.
  ENDLOOP.

* ---- 4. commit (one commit per document) ------------------------------
  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait = 'X'.

  add_msg 'S' 'Assignment changed' iv_belnr iv_gjahr.

ENDFUNCTION.
