CLASS zcl_fi_t01_probe DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
ENDCLASS.

CLASS zcl_fi_t01_probe IMPLEMENTATION.
  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = VALUE #( kind = if_apj_dt_exec_object=>parameter
      datatype = 'C' length = 4 changeable_ind = abap_true
      ( selname = 'CA' param_text = 'Allowed company' )
      ( selname = 'CD' param_text = 'Denied company' )
      ( selname = 'AA' param_text = 'Allowed business area' )
      ( selname = 'AD' param_text = 'Denied business area' ) ).
  ENDMETHOD.

  METHOD if_apj_rt_exec_object~execute.
    DATA: ca TYPE bukrs, cd TYPE bukrs, aa TYPE gsber, ad TYPE gsber,
          evidence TYPE string_table.
    IF sy-batch IS INITIAL OR lines( it_parameters ) <> 4.
      MESSAGE 'Not checked: expected a background job and four fixture values' TYPE 'E'.
    ENDIF.
    LOOP AT it_parameters INTO DATA(p).
      IF p-low IS INITIAL OR strlen( p-low ) > 4 OR p-high IS NOT INITIAL.
        MESSAGE 'Not checked: enter one nonblank fixture code per field' TYPE 'E'.
      ENDIF.
      CASE p-selname.
        WHEN 'CA'. ca = p-low.
        WHEN 'CD'. cd = p-low.
        WHEN 'AA'. aa = p-low.
        WHEN 'AD'. ad = p-low.
        WHEN OTHERS. MESSAGE 'Not checked: unknown fixture parameter' TYPE 'E'.
      ENDCASE.
    ENDLOOP.
    IF ca IS INITIAL OR cd IS INITIAL OR aa IS INITIAL OR ad IS INITIAL
        OR ca = cd OR aa = ad.
      MESSAGE 'Not checked: supply distinct allowed and denied fixtures' TYPE 'E'.
    ENDIF.

    APPEND |System { sy-sysid } / client { sy-mandt } / background user { sy-uname }| TO evidence.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'ACTVT' FIELD '02' ID 'BUKRS' FIELD ca.
    DATA(rc_ca) = sy-subrc.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK' ID 'ACTVT' FIELD '02' ID 'BUKRS' FIELD cd.
    DATA(rc_cd) = sy-subrc.
    AUTHORITY-CHECK OBJECT 'F_BKPF_GSB' ID 'ACTVT' FIELD '02' ID 'GSBER' FIELD aa.
    DATA(rc_aa) = sy-subrc.
    AUTHORITY-CHECK OBJECT 'F_BKPF_GSB' ID 'ACTVT' FIELD '02' ID 'GSBER' FIELD ad.
    DATA(rc_ad) = sy-subrc.
    APPEND |Allowed company { ca }: expected 0, observed { rc_ca }| TO evidence.
    APPEND |Denied company { cd }: expected 4, observed { rc_cd }| TO evidence.
    APPEND |Allowed area { aa }: expected 0, observed { rc_aa }| TO evidence.
    APPEND |Denied area { ad }: expected 4, observed { rc_ad }| TO evidence.
    TRY.
        DATA(log) = cl_bali_log=>create_with_header( header =
          cl_bali_header_setter=>create( object = 'ZFI_T01' subobject = 'IDENTITY' ) ).
        LOOP AT evidence INTO DATA(line).
          log->add_item( item = cl_bali_free_text_setter=>create(
            severity = if_bali_constants=>c_severity_information text = CONV #( line ) ) ).
        ENDLOOP.
        cl_bali_log_db=>get_instance( )->save_log_2nd_db_connection(
          log = log assign_to_current_appl_job = abap_true ).
      CATCH cx_bali_runtime.
        MESSAGE 'Not checked: could not save the log for this job' TYPE 'E'.
    ENDTRY.
    IF rc_ca <> 0 OR rc_cd <> 4 OR rc_aa <> 0 OR rc_ad <> 4.
      MESSAGE 'Permissions differ from the expected fixture. Review the job log.' TYPE 'E'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
