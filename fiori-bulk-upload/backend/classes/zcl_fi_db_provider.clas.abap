CLASS zcl_fi_db_provider DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_fi_db_provider.
ENDCLASS.


CLASS zcl_fi_db_provider IMPLEMENTATION.

  METHOD zif_fi_db_provider~read_lines.
    DATA(lt_keys) = it_doc_keys.
    SORT lt_keys BY belnr gjahr.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING belnr gjahr.

    DATA(lv_from) = 1.
    WHILE lv_from <= lines( lt_keys ).
      DATA(lv_to) = lv_from + zif_fi_upl_types=>gc_doc_chunk - 1.
      DATA(lt_chunk) = VALUE zif_fi_db_provider=>tt_doc_key( FOR <k> IN lt_keys FROM lv_from TO lv_to ( <k> ) ).

      IF lt_chunk IS NOT INITIAL.   " FOR ALL ENTRIES with an empty table would select everything
        SELECT belnr, gjahr, docln, racct, blart, budat, zuonr, augbl
          FROM acdoca BYPASSING BUFFER
          FOR ALL ENTRIES IN @lt_chunk
          WHERE rldnr = @iv_rldnr
            AND rbukrs = @iv_bukrs
            AND gjahr = @lt_chunk-gjahr
            AND belnr = @lt_chunk-belnr
          INTO TABLE @DATA(lt_db).

        LOOP AT lt_db ASSIGNING FIELD-SYMBOL(<db>).
          INSERT VALUE #( belnr = <db>-belnr
                          gjahr = <db>-gjahr
                          buzei = <db>-docln+3(3)
                          racct = <db>-racct
                          blart = <db>-blart
                          budat = <db>-budat
                          zuonr = <db>-zuonr
                          augbl = <db>-augbl ) INTO TABLE rt_lines.
        ENDLOOP.
      ENDIF.
      lv_from = lv_to + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD zif_fi_db_provider~read_locks.
    DATA lt_enq TYPE STANDARD TABLE OF seqg3 WITH EMPTY KEY.
    CALL FUNCTION 'ENQUEUE_READ'
      EXPORTING
        gclient = sy-mandt
        gname   = 'BKPF'
      TABLES
        enq     = lt_enq
      EXCEPTIONS
        communication_failure = 1
        system_failure        = 2
        OTHERS                = 3.
    IF sy-subrc <> 0.
      RETURN.   " no lock information; Post still takes the real lock per document
    ENDIF.

    LOOP AT lt_enq ASSIGNING FIELD-SYMBOL(<e>).
      DATA(lv_garg) = CONV char32( <e>-garg ).   " MANDT(3) BUKRS(4) BELNR(10) GJAHR(4)
      IF lv_garg+3(4) <> iv_bukrs.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( belnr = lv_garg+7(10)
                      gjahr = lv_garg+17(4)
                      owner = <e>-guname ) INTO TABLE rt_locks.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
