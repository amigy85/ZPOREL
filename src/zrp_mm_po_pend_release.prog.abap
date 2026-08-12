*&---------------------------------------------------------------------*
*& Report ZRP_MM_PO_PEND_RELEASE
*&---------------------------------------------------------------------*
*& Notificacao semanal de POs pendentes de liberacao (ZPOREL).
*& O report so monta o ecra de seleccao e delega em ZCL_POREL_PROCESSOR.
*&
*& NOTA: manter em SE38 (Goto -> Text Elements) os titulos de bloco
*&       B01/B02/B03 e os textos de seleccao (S_EBELN, ... , P_*).
*&---------------------------------------------------------------------*
REPORT zrp_mm_po_pend_release.

TABLES ekko.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  SELECT-OPTIONS:
    s_ebeln FOR ekko-ebeln,
    s_bsart FOR ekko-bsart,
    s_ekorg FOR ekko-ekorg,
    s_ekgrp FOR ekko-ekgrp,
    s_lifnr FOR ekko-lifnr,
    s_bedat FOR ekko-bedat,
    s_frggr FOR ekko-frggr.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS:
    p_send   AS CHECKBOX DEFAULT 'X',
    p_tmpl   TYPE zemail_template_id DEFAULT 'ZPO_PEND_RELEASE',
    p_langu  TYPE spras DEFAULT 'P',
    p_parmod TYPE c LENGTH 1 DEFAULT 'S',
    p_force  AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS:
    p_test   AS CHECKBOX,
    p_mailts TYPE ad_smtpadr.
SELECTION-SCREEN END OF BLOCK b3.


*&---------------------------------------------------------------------*
*& Classe local: montagem, execucao e apresentacao (SALV).
*&---------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_alv,
        ebeln     TYPE ekko-ebeln,
        bsart     TYPE ekko-bsart,
        name1     TYPE lfa1-name1,
        bedat     TYPE ekko-bedat,
        netwr     TYPE ekpo-netwr,
        waers     TYPE ekko-waers,
        frgco     TYPE frgco,
        frgco_txt TYPE t16fd-frgct,
        ekgrp     TYPE ekko-ekgrp,
        email     TYPE ad_smtpadr,
      END OF ty_alv,
      tt_alv TYPE STANDARD TABLE OF ty_alv WITH DEFAULT KEY.

    METHODS run
      IMPORTING
        is_filter   TYPE zif_porel_types=>ty_po_filter
        is_policy   TYPE zif_porel_types=>ty_run_policy
        iv_template TYPE zemail_template_id.

  PRIVATE SECTION.
    DATA mt_alv TYPE tt_alv.

    METHODS display.

    METHODS on_link_click
      FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA lt_results TYPE zif_porel_types=>tt_send_result.
    DATA lt_lines   TYPE zif_porel_types=>tt_notif_line.

    " logger BAL do framework ZEMAIL
    DATA(lo_logger) = NEW zcl_logger_bal(
      iv_object    = 'ZPOREL'
      iv_subobject = 'NOTIFY'
      iv_extnumber = |Run { sy-datum } { sy-uzeit } { sy-uname }| ).

    DATA(lo_builder) = NEW zcl_porel_notif_builder(
      iv_template_id = iv_template
      iv_langu       = is_policy-langu ).

    DATA(lo_proc) = NEW zcl_porel_processor(
      io_builder = lo_builder
      io_logger  = lo_logger ).

    TRY.
        lo_proc->notify(
          EXPORTING
            is_filter  = is_filter
            is_policy  = is_policy
          IMPORTING
            et_results = lt_results
            et_lines   = lt_lines ).
      CATCH zcx_porel INTO DATA(lx_porel).
        MESSAGE lx_porel->get_text( ) TYPE 'E'.
        RETURN.
    ENDTRY.

    mt_alv = VALUE #( FOR ls IN lt_lines
      ( ebeln     = ls-line-ebeln
        bsart     = ls-line-bsart
        name1     = ls-line-name1
        bedat     = ls-line-bedat
        netwr     = ls-line-netwr
        waers     = ls-line-waers
        frgco     = ls-line-frgco
        frgco_txt = ls-line-frgco_txt
        ekgrp     = ls-line-ekgrp
        email     = ls-recipient-email ) ).

    IF sy-batch = abap_true.
      " background: resumo no spool
      LOOP AT lt_results INTO DATA(ls_r).
        WRITE: / ls_r-status, ls_r-email, ls_r-po_count, ls_r-message.
      ENDLOOP.
      WRITE: / |{ lines( lt_lines ) } linha(s) para { lines( lt_results ) } envio(s).|.
    ELSE.
      display( ).
    ENDIF.
  ENDMETHOD.


  METHOD display.
    DATA lo_alv TYPE REF TO cl_salv_table.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = mt_alv ).
      CATCH cx_salv_msg.
        RETURN.
    ENDTRY.

    lo_alv->get_functions( )->set_all( ).
    lo_alv->get_columns( )->set_optimize( abap_true ).

    " hotspot no EBELN -> ME23N
    TRY.
        DATA(lo_col) = CAST cl_salv_column_table(
          lo_alv->get_columns( )->get_column( 'EBELN' ) ).
        lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).
      CATCH cx_salv_not_found.
    ENDTRY.

    SET HANDLER on_link_click FOR lo_alv->get_event( ).

    lo_alv->display( ).
  ENDMETHOD.


  METHOD on_link_click.
    READ TABLE mt_alv INDEX row INTO DATA(ls).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SET PARAMETER ID 'BES' FIELD ls-ebeln.
    CALL TRANSACTION 'ME23N'.                             "#EC CI_CALLTA
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Ecra de seleccao / execucao
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF p_test = abap_true AND p_mailts IS INITIAL.
    MESSAGE e398(00) WITH 'Em modo teste, indique o e-mail de teste (P_MAILTS).'.
  ENDIF.

START-OF-SELECTION.
  DATA(ls_filter) = VALUE zif_porel_types=>ty_po_filter(
    ebeln = s_ebeln[]
    bsart = s_bsart[]
    ekorg = s_ekorg[]
    ekgrp = s_ekgrp[]
    lifnr = s_lifnr[]
    bedat = s_bedat[]
    frggr = s_frggr[] ).

  DATA(ls_policy) = VALUE zif_porel_types=>ty_run_policy(
    send       = p_send
    force      = p_force
    test_mode  = p_test
    test_email = p_mailts
    mode       = p_parmod
    langu      = p_langu ).

  DATA(go_app) = NEW lcl_app( ).
  go_app->run(
    is_filter   = ls_filter
    is_policy   = ls_policy
    iv_template = p_tmpl ).
