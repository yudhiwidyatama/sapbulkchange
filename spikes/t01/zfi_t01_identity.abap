REPORT zfi_t01_identity LINE-SIZE 255 NO STANDARD PAGE HEADING.

" QA probe only. Explicit fixture values, never document keys or user input
" for the effective principal. No FI/DB calls or impersonation.
PARAMETERS: p_ca TYPE bukrs OBLIGATORY, p_cd TYPE bukrs OBLIGATORY,
            p_aa TYPE gsber OBLIGATORY, p_ad TYPE gsber OBLIGATORY.

AT SELECTION-SCREEN.
  IF p_ca = p_cd OR p_aa = p_ad.
    MESSAGE 'Allowed and denied fixture values must differ' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  DATA(mode) = COND string( WHEN sy-batch = 'X' THEN 'BATCH' ELSE 'DIALOG' ).
  WRITE: / |T01\|system\|{ sy-sysid }\|{ sy-mandt }|,
         / |T01\|actor\|{ sy-uname }\|{ mode }|.
  AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'BUKRS' FIELD p_ca ID 'ACTVT' FIELD '02'.
  DATA(rc) = sy-subrc.
  WRITE / |T01\|company+\|{ p_ca }\|{ rc }|.
  AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'BUKRS' FIELD p_cd ID 'ACTVT' FIELD '02'.
  rc = sy-subrc.
  WRITE / |T01\|company-\|{ p_cd }\|{ rc }|.
  AUTHORITY-CHECK OBJECT 'F_BKPF_GSB' ID 'GSBER' FIELD p_aa ID 'ACTVT' FIELD '02'.
  rc = sy-subrc.
  WRITE / |T01\|area+\|{ p_aa }\|{ rc }|.
  AUTHORITY-CHECK OBJECT 'F_BKPF_GSB' ID 'GSBER' FIELD p_ad ID 'ACTVT' FIELD '02'.
  rc = sy-subrc.
  WRITE / |T01\|area-\|{ p_ad }\|{ rc }|.
