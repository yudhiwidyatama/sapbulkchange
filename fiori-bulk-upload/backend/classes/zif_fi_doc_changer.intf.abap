" The only component that changes FI documents (FI_DOCUMENT_CHANGE).
INTERFACE zif_fi_doc_changer PUBLIC.

  TYPES: BEGIN OF ty_change,
           buzei   TYPE buzei,
           source  TYPE c LENGTH 6,
           old_val TYPE dzuonr,
           new_val TYPE dzuonr,
         END OF ty_change,
         tt_change TYPE STANDARD TABLE OF ty_change WITH EMPTY KEY.

  TYPES: BEGIN OF ty_result,
           success TYPE abap_bool,
           message TYPE string,
         END OF ty_result.

  " One document = one LUW: lock, change every line, commit (or roll back all), unlock.
  METHODS change_document
    IMPORTING iv_bukrs         TYPE bukrs
              iv_belnr         TYPE belnr_d
              iv_gjahr         TYPE gjahr
              it_changes       TYPE tt_change
    RETURNING VALUE(rs_result) TYPE ty_result.

ENDINTERFACE.
