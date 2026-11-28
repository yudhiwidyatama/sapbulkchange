CLASS zcl_fi_run_store DEFINITION PUBLIC FINAL CREATE PRIVATE.
  PUBLIC SECTION.
    CLASS-METHODS create_run
      IMPORTING company TYPE bukrs
      RETURNING VALUE(run_id) TYPE sysuuid_x16
      RAISING cx_uuid_error.
    CLASS-METHODS seal_workbook
      IMPORTING run_id TYPE sysuuid_x16 revision TYPE i workbook TYPE xstring
      RETURNING VALUE(ok) TYPE abap_bool.
    CLASS-METHODS claim_validation
      IMPORTING run_id TYPE sysuuid_x16 revision TYPE i
      RETURNING VALUE(ok) TYPE abap_bool.
    CLASS-METHODS read_for_validation
      IMPORTING run_id TYPE sysuuid_x16 revision TYPE i
      EXPORTING workbook TYPE xstring company TYPE bukrs.
    CLASS-METHODS finish_validation
      IMPORTING run_id TYPE sysuuid_x16 revision TYPE i valid TYPE abap_bool
      RETURNING VALUE(ok) TYPE abap_bool.
    " No transition to an apply state until the security matrix and writer are approved.
  PRIVATE SECTION.
    CLASS-METHODS transition
      IMPORTING run_id TYPE sysuuid_x16 revision TYPE i from_phase TYPE string to_phase TYPE string
      RETURNING VALUE(ok) TYPE abap_bool.
ENDCLASS.

CLASS zcl_fi_run_store IMPLEMENTATION.
  METHOD create_run.
    IF company IS INITIAL OR sy-uname IS INITIAL. RETURN. ENDIF.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'BUKRS' FIELD company ID 'ACTVT' FIELD '02'.
    IF sy-subrc <> 0. RETURN. ENDIF.
    DATA record TYPE zfi_astra_run.
    record-client = sy-mandt.
    record-run_id = cl_system_uuid=>create_uuid_x16_static( ).
    record-requester = sy-uname.
    record-company_code = company.
    record-phase = 'NEW'.
    record-revision = 1.
    GET TIME STAMP FIELD record-created_at.
    INSERT zfi_astra_run FROM @record.
    IF sy-subrc = 0. run_id = record-run_id. ENDIF.
  ENDMETHOD.

  METHOD seal_workbook.
    IF zcl_fi_upload_guard=>accepts_workbook_size( workbook ) = abap_false. RETURN. ENDIF.
    DATA(next_revision) = revision + 1.
    UPDATE zfi_astra_run SET workbook = @workbook, phase = 'VALIDATE_QUEUED', revision = @next_revision
      WHERE run_id = @run_id AND requester = @sy-uname AND phase = 'NEW' AND revision = @revision.
    ok = xsdbool( sy-dbcnt = 1 ).
  ENDMETHOD.

  METHOD transition.
    DATA(next_revision) = revision + 1.
    UPDATE zfi_astra_run SET phase = @to_phase, revision = @next_revision
      WHERE run_id = @run_id AND requester = @sy-uname AND phase = @from_phase AND revision = @revision.
    ok = xsdbool( sy-dbcnt = 1 ).
  ENDMETHOD.

  METHOD claim_validation.
    IF sy-batch <> abap_true. RETURN. ENDIF.
    ok = transition( run_id = run_id revision = revision from_phase = `VALIDATE_QUEUED` to_phase = `VALIDATING` ).
  ENDMETHOD.

  METHOD read_for_validation.
    CLEAR: workbook, company.
    IF sy-batch <> abap_true. RETURN. ENDIF.
    SELECT SINGLE client, requester, company_code, workbook FROM zfi_astra_run
      WHERE run_id = @run_id AND requester = @sy-uname AND revision = @revision AND phase = 'VALIDATING'
      INTO @DATA(row_data).
    IF sy-subrc <> 0. RETURN. ENDIF.
    IF zcl_fi_upload_guard=>is_request_owner( stored_client = row_data-client stored_requester = row_data-requester ) = abap_false. RETURN. ENDIF.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'BUKRS' FIELD row_data-company_code ID 'ACTVT' FIELD '02'.
    IF sy-subrc <> 0. RETURN. ENDIF.
    workbook = row_data-workbook. company = row_data-company_code.
  ENDMETHOD.

  METHOD finish_validation.
    IF sy-batch <> abap_true. RETURN. ENDIF.
    ok = transition( run_id = run_id revision = revision from_phase = `VALIDATING`
      to_phase = COND string( WHEN valid = abap_true THEN `READY` ELSE `FAILED` ) ).
  ENDMETHOD.
ENDCLASS.
