class ZCL_AQO_OPTION definition
  public
  create private .

public section.
  type-pools ABAP .

  data MS_DB_ITEM type ZTAQO_OPTION read-only .

  class-methods CREATE
    importing
      !IV_PACKAGE_ID type CSEQUENCE
      !IV_OPTION_ID type CSEQUENCE
      !IR_DATA type ref to DATA optional
      !IO_DATA type ref to OBJECT optional
      !IV_REPAIR type ABAP_BOOL default ABAP_FALSE
    returning
      value(RO_OPT) type ref to ZCL_AQO_OPTION
    raising
      ZCX_AQO_EXCEPTION .
  methods GET_FIELD_VALUE
    importing
      !IV_NAME type CSEQUENCE
    returning
      value(RR_DATA) type ref to DATA
    raising
      ZCX_AQO_EXCEPTION .
  class-methods GET_MENU
    importing
      !IV_PACKAGE_ID type CSEQUENCE
      !IV_OPTION_ID type CSEQUENCE
    returning
      value(RO_MENU) type ref to ZCL_EUI_MENU .
protected section.

  data MT_FIELD_VALUE type ZCL_AQO_HELPER=>TT_FIELD_VALUE .

  methods DELETE
    importing
      !IV_TASK type CSEQUENCE optional
    returning
      value(RV_INFO) type STRING
    raising
      ZCX_AQO_EXCEPTION .
  methods LOCK
    importing
      !IV_UNLOCK type ABAP_BOOL default ABAP_FALSE
    returning
      value(RV_OK) type ABAP_BOOL .
  methods SAVE
    returning
      value(RV_INFO) type STRING
    raising
      ZCX_AQO_EXCEPTION .
  methods TRANSPORT
    importing
      !IV_TASK type CSEQUENCE optional
    returning
      value(RV_INFO) type STRING
    raising
      ZCX_AQO_EXCEPTION .
  methods ADD_HISTORY_VALUE
    importing
      !IV_VALUE type STRING
    changing
      !CS_FIELD_VALUE type ZCL_AQO_HELPER=>TS_FIELD_VALUE .
private section.

  methods GET_ABAP_VALUE
    importing
      !IR_DATA type ref to DATA
      !IO_DATA type ref to OBJECT
      !IV_NAME type CSEQUENCE
    returning
      value(RR_DATA) type ref to DATA .
ENDCLASS.



CLASS ZCL_AQO_OPTION IMPLEMENTATION.


METHOD add_history_value.
  DATA:
    ls_history_value TYPE zcl_aqo_helper=>ts_history_value,
    ls_history_prev  TYPE REF TO zcl_aqo_helper=>ts_history_value,
    lv_last_index    TYPE i.

  " Leave only text
  ls_history_value-h_value = iv_value.
  ls_history_value-changed = sy-datum.
  ls_history_value-login   = sy-uname.

  " Previous
  lv_last_index = lines( cs_field_value-value ).
  READ TABLE cs_field_value-value REFERENCE INTO ls_history_prev INDEX lv_last_index.

  " Compare with prev value
  IF sy-subrc <> 0 OR ls_history_value-h_value <> ls_history_prev->h_value.
    " Today ?
    IF sy-subrc = 0 AND ls_history_value-changed = ls_history_prev->changed.
      DELETE cs_field_value-value INDEX lv_last_index.
    ENDIF.

    " Insert new one
    INSERT ls_history_value INTO TABLE cs_field_value-value.
  ENDIF.

  " Delete obselete data
  lv_last_index = lines( cs_field_value-value ).
  lv_last_index = lv_last_index - ms_db_item-prev_value_cnt.
  DO lv_last_index TIMES.
    DELETE cs_field_value-value INDEX 1.
  ENDDO.
ENDMETHOD.


METHOD create.
  DATA:
    lt_callstack      TYPE abap_callstack,
    ls_last_call      TYPE REF TO abap_callstack_line,
    lv_devclass       TYPE tdevc-devclass,
    lo_xslt_error     TYPE REF TO cx_xslt_runtime_error,
    lt_declared_field TYPE zcl_aqo_helper=>abap_attrname_tab,
    lv_in_editor      TYPE abap_bool,
    lv_changed        TYPE abap_bool,
    lv_message        TYPE string,
    lo_error          TYPE REF TO zcx_eui_exception.

  " Instead of contructor
  CREATE OBJECT ro_opt.

  " Key fields
  ro_opt->ms_db_item-package_id     = iv_package_id.
  ro_opt->ms_db_item-option_id      = iv_option_id.

  " No error in editor
  lv_in_editor = zcl_aqo_helper=>is_in_editor( ).

  " Load data
  SELECT SINGLE * INTO ro_opt->ms_db_item
  FROM ztaqo_option
  WHERE package_id = iv_package_id
    AND option_id  = iv_option_id.

  " First transform
  IF sy-subrc = 0. " AND ms_db_item-fields IS NOT INITIAL.
    TRY.
        CALL TRANSFORMATION id
         SOURCE XML ro_opt->ms_db_item-fields
         RESULT field_opt = ro_opt->mt_field_value.
      CATCH cx_xslt_runtime_error INTO lo_xslt_error.
        zcx_aqo_exception=>raise_sys_error( io_error = lo_xslt_error ).
    ENDTRY.
  ELSE.
    ro_opt->ms_db_item-prev_value_cnt = 5.

    " Check for new packages
    SELECT SINGLE devclass INTO lv_devclass
    FROM tdevc
    WHERE devclass = iv_package_id.

    " Oops
    IF lv_devclass IS INITIAL.
      MESSAGE s020(zaqo_message) WITH iv_package_id INTO sy-msgli.
      zcx_aqo_exception=>raise_sys_error( ).
    ENDIF.
  ENDIF.

**********************************************************************
  " Where-Used List
  CALL FUNCTION 'SYSTEM_CALLSTACK'
    EXPORTING
      max_level = 2
    IMPORTING
      callstack = lt_callstack.
  READ TABLE lt_callstack INDEX 2 REFERENCE INTO ls_last_call.
  IF sy-subrc = 0 AND lv_in_editor <> abap_true.
    ro_opt->ms_db_item-last_call = ls_last_call->*.
  ENDIF.

**********************************************************************
  " read current values and check them
  lcl_helper=>check_abap_declaration(
   EXPORTING
     io_option      = ro_opt
     io_data        = io_data
     ir_data        = ir_data
     iv_repair      = iv_repair
   CHANGING
     ct_field_value = ro_opt->mt_field_value
     cv_changed     = lv_changed ).

**********************************************************************
  " Read option from DB
**********************************************************************
  DATA:
    lr_data          TYPE REF TO data,
    lr_table         TYPE REF TO data,
    lo_type          TYPE REF TO cl_abap_datadescr,
    lv_ok            TYPE abap_bool,
    ls_field_desc    TYPE zcl_eui_type=>ts_field_desc,
    ls_history_value TYPE REF TO zcl_aqo_helper=>ts_history_value,
    lv_last_index    TYPE i,
    lr_prev          TYPE REF TO data.
  FIELD-SYMBOLS:
    <lv_value>       TYPE any,
    <lt_value>       TYPE STANDARD TABLE,
    <lt_any_tab>     TYPE ANY TABLE,
    <ls_value>       TYPE any,
    <ls_field_value> LIKE LINE OF mt_field_value,
    <ls_prev>        TYPE any.

  LOOP AT ro_opt->mt_field_value ASSIGNING <ls_field_value>.
    " Destination
    lr_data = ro_opt->get_abap_value(
       io_data = io_data
       ir_data = ir_data
       iv_name = <ls_field_value>-name ).
    ASSIGN lr_data->* TO <lv_value>.
    CHECK sy-subrc = 0.

    " For tables only
    IF iv_repair = abap_true AND <ls_field_value>-sys_type = cl_abap_typedescr=>typekind_table.
      ls_field_desc = <ls_field_value>-field_desc.

      " Create standard table
      ls_field_desc-table_kind = cl_abap_tabledescr=>tablekind_std.
      CLEAR ls_field_desc-unique.

      " Assign it
      TRY.
          lo_type = zcl_eui_type=>create_type_descr( is_field_desc = ls_field_desc ).
        CATCH zcx_eui_exception INTO lo_error.
          zcx_aqo_exception=>raise_sys_error( io_error = lo_error ).
      ENDTRY.
      CREATE DATA lr_table TYPE HANDLE lo_type.
      ASSIGN:
        lr_data->*  TO <lt_any_tab>,
        lr_table->* TO <lt_value>,
        lr_table->* TO <lv_value>.
    ENDIF.

    " №1
    lv_last_index = lines( <ls_field_value>-value ).
    READ TABLE <ls_field_value>-value REFERENCE INTO ls_history_value INDEX lv_last_index.

    IF sy-subrc <> 0.
      lv_ok = abap_false.
    ELSE.
      zcl_eui_conv=>from_json(
       EXPORTING
         iv_json = ls_history_value->h_value
       IMPORTING
         ev_ok   = lv_ok
         ex_data = <lv_value> ).
    ENDIF.

    IF iv_repair = abap_true AND <ls_field_value>-sys_type = cl_abap_typedescr=>typekind_table.
      " Safe copy of existing data
      CREATE DATA lr_prev LIKE LINE OF <lt_any_tab>.
      ASSIGN lr_prev->* TO <ls_prev>.

      " No errors for duplications
      CLEAR <lt_any_tab>.
      LOOP AT <lt_value> ASSIGNING <ls_value>.
        MOVE-CORRESPONDING <ls_value> TO <ls_prev>.
        INSERT <ls_prev> INTO TABLE <lt_any_tab>.
      ENDLOOP.

      IF lines( <lt_value> ) <> lines( <lt_any_tab> ).
        lv_ok = abap_false.
      ENDIF.
    ENDIF.

*    " Cannot read options
*    CHECK lv_ok <> abap_true.
*    APPEND <ls_field_value>-name TO rt_empty_field.
  ENDLOOP.

**********************************************************************
  " Call save for user
  CHECK lv_in_editor <> abap_true.

  IF lt_declared_field IS NOT INITIAL OR lv_changed = abap_true.
    " Or something like that SY-SYSID <> 'DEV'
    IF zcl_aqo_helper=>is_dev_mandt( ) <> abap_true.
      MESSAGE s006(zaqo_message) WITH iv_package_id iv_option_id.
      zcx_aqo_exception=>raise_sys_error( ).
    ENDIF.

    lv_message = ro_opt->save( ).
    IF lv_message IS NOT INITIAL.
      MESSAGE lv_message TYPE 'S'.
    ENDIF.
  ELSE.
    zcl_aqo_option=>get_menu(
      iv_package_id = iv_package_id
      iv_option_id  = iv_option_id ).
  ENDIF.
ENDMETHOD.


METHOD delete.
  DATA lv_text TYPE string.

  " Own dialogs iv_confirm = abap_true.
  IF zcl_aqo_helper=>is_in_editor( iv_is_sapui5 = abap_true ) <> abap_true AND
    " Cancelled
   zcl_eui_screen=>confirm(
         iv_title    = 'Delete'(del)
         iv_question = 'Operation irreversible. Continue?'(irr)
         IV_ICON_1   = 'ICON_DELETE' ) <> abap_true.
    MESSAGE s130(ed) WITH 'Delete'(del) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF zcl_aqo_helper=>is_dev_mandt( ) <> abap_true.
    MESSAGE s011(zaqo_message) INTO sy-msgli.
    zcx_aqo_exception=>raise_sys_error( ).
  ENDIF.

  " Put to request
  IF iv_task IS NOT INITIAL.
    rv_info = transport( iv_task ).
  ENDIF.

  DELETE
  FROM ztaqo_option
   WHERE package_id = ms_db_item-package_id
     AND option_id  = ms_db_item-option_id.

  " Show info
  MESSAGE s010(zaqo_message) WITH ms_db_item-package_id ms_db_item-option_id INTO lv_text.
  CONCATENATE lv_text ` ` rv_info INTO rv_info.
ENDMETHOD.


METHOD get_abap_value.
  DATA:
    lv_name    TYPE string.
  FIELD-SYMBOLS:
    <ls_data>  TYPE any,
    <lv_value> TYPE any.

  " Get data
  IF io_data IS NOT INITIAL.
    CONCATENATE 'IO_DATA->' iv_name INTO lv_name.
    ASSIGN (lv_name) TO <lv_value>.
  ELSE.
    ASSIGN ir_data->* TO <ls_data>.
    ASSIGN COMPONENT iv_name OF STRUCTURE <ls_data> TO <lv_value>.
  ENDIF.

  " Return as reference
  CHECK <lv_value> IS ASSIGNED.
  GET REFERENCE OF <lv_value> INTO rr_data.
ENDMETHOD.


METHOD get_field_value.
  DATA:
    lv_last_index   TYPE i,
    ls_history_prev TYPE REF TO zcl_aqo_helper=>ts_history_value,
    lo_type         TYPE REF TO cl_abap_datadescr,
    lr_value        TYPE REF TO data,
    lv_ok           TYPE abap_bool,
    lo_error        TYPE REF TO zcx_eui_exception.
  FIELD-SYMBOLS:
    <ls_field_value> LIKE LINE OF mt_field_value,
    <lv_value>       TYPE any.

  " Read current
  READ TABLE mt_field_value ASSIGNING <ls_field_value>
   WITH TABLE KEY name = iv_name.
  IF sy-subrc <> 0.
    MESSAGE s030(zaqo_message) WITH iv_name INTO sy-msgli.
    zcx_aqo_exception=>raise_sys_error( ).
  ENDIF.

  " Last one
  lv_last_index = lines( <ls_field_value>-value ).
  READ TABLE <ls_field_value>-value REFERENCE INTO ls_history_prev INDEX lv_last_index.
  IF sy-subrc <> 0.
    MESSAGE s031(zaqo_message) WITH iv_name INTO sy-msgli.
    zcx_aqo_exception=>raise_sys_error( ).
  ENDIF.

  " Create type
  TRY.
      lo_type = zcl_eui_type=>create_type_descr( is_field_desc = <ls_field_value>-field_desc ).
    CATCH zcx_eui_exception INTO lo_error.
      zcx_aqo_exception=>raise_sys_error( io_error = lo_error ).
  ENDTRY.
  CREATE DATA lr_value TYPE HANDLE lo_type.
  ASSIGN lr_value->* TO <lv_value>.

  " Convert from JSON
  zcl_eui_conv=>from_json(
   EXPORTING
     iv_json = ls_history_prev->h_value
   IMPORTING
     ex_data = <lv_value>
     ev_ok   = lv_ok ).
  IF lv_ok <> abap_true.
    MESSAGE s033(zaqo_message) WITH iv_name INTO sy-msgli.
    zcx_aqo_exception=>raise_sys_error( ).
  ENDIF.

  " Return it
  GET REFERENCE OF <lv_value> INTO rr_data.
ENDMETHOD.


METHOD get_menu.
  ro_menu = lcl_unq_menu=>get_eui_menu(
   iv_package_id = iv_package_id
   iv_option_id  = iv_option_id ).
ENDMETHOD.


METHOD lock.
  " Locks
  IF iv_unlock = abap_true.
    CALL FUNCTION 'DEQUEUE_EZTAQO_OPTION'
      EXPORTING
        package_id = ms_db_item-package_id
        option_id  = ms_db_item-option_id
        _scope     = '1'
      EXCEPTIONS
        OTHERS     = 3.
  ELSE.
    CALL FUNCTION 'ENQUEUE_EZTAQO_OPTION'
      EXPORTING
        package_id     = ms_db_item-package_id
        option_id      = ms_db_item-option_id
        _scope         = '1'
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
  ENDIF.

  " Show message in caller
  CHECK sy-subrc = 0.

  " Ok locked
  rv_ok = abap_true.
ENDMETHOD.


METHOD save.
  DATA:
    lv_text       TYPE text255,
    lv_program    TYPE string,
    lv_is_class   TYPE abap_bool,
    lv_in_editor  TYPE abap_bool,
    lv_error_text TYPE text255,
    lv_is_dev     TYPE abap_bool.

  " Is dev ?
  lv_is_dev = zcl_aqo_helper=>is_dev_mandt( ).

  " Own dialogs (iv_confirm = abap_true)
  IF zcl_aqo_helper=>is_in_editor( iv_is_sapui5 = abap_true ) <> abap_true.
    " Overrite message
    MESSAGE s019(zaqo_message) WITH ms_db_item-package_id ms_db_item-option_id INTO lv_text.

    " Cancelled
    IF zcl_eui_screen=>confirm(
         iv_title    = 'Save'(sav)
         iv_question = lv_text
         iv_icon_1   = 'ICON_SYSTEM_SAVE' ) <> abap_true.
      MESSAGE s130(ed) WITH 'Save'(sav) DISPLAY LIKE 'E'.
      zcx_aqo_exception=>raise_sys_error( ).
    ENDIF.
  ENDIF.

  " Class or program
  zcl_aqo_helper=>get_last_call_info(
   EXPORTING
     is_last_call = ms_db_item-last_call
   IMPORTING
     ev_name      = lv_program
     ev_is_class  = lv_is_class ).

  lv_in_editor = zcl_aqo_helper=>is_in_editor( ).
  TRY.
      IF lv_is_class <> abap_true.
        PERFORM before_option_save IN PROGRAM (lv_program) IF FOUND
         USING
           me             " IO_OPTION
           lv_in_editor   " IV_IN_EDITOR
         CHANGING
           lv_error_text. " CV_ERROR_TEXT.
      ELSE.
        CALL METHOD (lv_program)=>('ZIF_AQO_EXT~BEFORE_OPTION_SAVE')
          EXPORTING
            io_option     = me
            iv_in_editor  = lv_in_editor
          CHANGING
            cv_error_text = lv_error_text.
      ENDIF.
    CATCH cx_root.
      CLEAR lv_error_text.
  ENDTRY.

  " Show an error
  IF lv_error_text IS NOT INITIAL.
    zcx_aqo_exception=>raise_sys_error( iv_message = lv_error_text ).
  ENDIF.

  " Always put in request in DEV
  rv_info = transport( ).

  " Technical info
  IF ms_db_item-created_date IS INITIAL.
    ms_db_item-created_date = sy-datum.
  ENDIF.

  IF ms_db_item-created_uname IS INITIAL.
    ms_db_item-created_uname = sy-uname.

    " Login could be deletes afterwards
    SELECT SINGLE name_textc INTO ms_db_item-created_name_txt
    FROM user_addr
    WHERE bname = sy-uname " ##WARN_OK  backward compatibility
    .
  ENDIF.

  " First transform (Data already set to mt_field_value)
  CALL TRANSFORMATION id
   SOURCE field_opt = mt_field_value
   RESULT XML ms_db_item-fields.

  " Save data
  MODIFY ztaqo_option FROM ms_db_item.
  COMMIT WORK AND WAIT.

  " Add previous messages text
  IF lv_in_editor = abap_true AND lv_is_dev <> abap_true.
    CONCATENATE `The option was saved. Please copy or export it to DEV system! ` rv_info INTO rv_info.
  ELSE.
    CONCATENATE ms_db_item-package_id ` - ` ms_db_item-option_id INTO lv_text.
    MESSAGE s516(ed) WITH lv_text INTO lv_text.
    CONCATENATE lv_text `! ` rv_info INTO rv_info.
  ENDIF.
ENDMETHOD.


METHOD transport.
  DATA:
    lv_task TYPE e070-trkorr.

  " No need to transport
  IF ms_db_item-package_id CP '$*'.
    rv_info = `No need to transport temporary options`.
    RETURN.
  ENDIF.

  lv_task = iv_task.
  zcl_aqo_helper=>check_in_request(
   EXPORTING
     iv_table_name = 'ZTAQO_OPTION'
     iv_key1       = ms_db_item-package_id
     iv_key2       = ms_db_item-option_id
   CHANGING
     cv_task       = lv_task
     cv_ok_message = rv_info ).
ENDMETHOD.
ENDCLASS.
