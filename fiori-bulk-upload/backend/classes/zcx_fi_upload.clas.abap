CLASS zcx_fi_upload DEFINITION PUBLIC FINAL INHERITING FROM cx_static_check CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    METHODS constructor
      IMPORTING msgno    TYPE symsgno
                msgv1    TYPE csequence OPTIONAL
                msgv2    TYPE csequence OPTIONAL
                msgv3    TYPE csequence OPTIONAL
                msgv4    TYPE csequence OPTIONAL
                previous TYPE REF TO cx_root OPTIONAL.

ENDCLASS.


CLASS zcx_fi_upload IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    if_t100_message~t100key = VALUE #( msgid = zif_fi_upl_types=>gc_msgid
                                       msgno = msgno
                                       attr1 = 'IF_T100_DYN_MSG~MSGV1'
                                       attr2 = 'IF_T100_DYN_MSG~MSGV2'
                                       attr3 = 'IF_T100_DYN_MSG~MSGV3'
                                       attr4 = 'IF_T100_DYN_MSG~MSGV4' ).
    if_t100_dyn_msg~msgty = 'E'.
    if_t100_dyn_msg~msgv1 = msgv1.
    if_t100_dyn_msg~msgv2 = msgv2.
    if_t100_dyn_msg~msgv3 = msgv3.
    if_t100_dyn_msg~msgv4 = msgv4.
  ENDMETHOD.

ENDCLASS.
