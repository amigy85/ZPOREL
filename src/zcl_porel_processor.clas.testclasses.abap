"! Duplo do servico de e-mail.
CLASS ltd_email DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_email_service.
    DATA mv_calls     TYPE i.
    DATA mv_last_addr TYPE ad_smtpadr.
ENDCLASS.
CLASS ltd_email IMPLEMENTATION.
  METHOD zif_email_service~send.
    mv_calls = mv_calls + 1.
    READ TABLE it_recipients INDEX 1 INTO DATA(ls_r).
    mv_last_addr = ls_r-address.
    rs_result-status  = zif_email_const=>send_status-success.
    rs_result-send_id = 'TST'.
  ENDMETHOD.
ENDCLASS.

"! Duplo do controlo de idempotencia.
CLASS ltd_run DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_porel_run_control.
    DATA mv_already     TYPE abap_bool.
    DATA mv_records     TYPE i.
    DATA mv_last_status TYPE c LENGTH 1.
ENDCLASS.
CLASS ltd_run IMPLEMENTATION.
  METHOD zif_porel_run_control~already_sent.
    rv_yes = mv_already.
  ENDMETHOD.
  METHOD zif_porel_run_control~record.
    mv_records     = mv_records + 1.
    mv_last_status = iv_status.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_processor DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_email TYPE REF TO ltd_email.
    DATA mo_run   TYPE REF TO ltd_run.
    DATA mo_cut   TYPE REF TO zcl_porel_processor.

    METHODS setup.
    METHODS bundle_of
      IMPORTING iv_email      TYPE ad_smtpadr
      RETURNING VALUE(rt)     TYPE zif_porel_types=>tt_recipient_bundle.
    METHODS policy
      IMPORTING iv_send       TYPE abap_bool DEFAULT abap_true
                iv_force      TYPE abap_bool DEFAULT abap_false
                iv_test       TYPE abap_bool DEFAULT abap_false
                iv_test_email TYPE ad_smtpadr DEFAULT space
      RETURNING VALUE(rs)     TYPE zif_porel_types=>ty_run_policy.

    METHODS actionable_from_frgzu FOR TESTING.
    METHODS lines_join_email      FOR TESTING.
    METHODS lines_skip_no_email   FOR TESTING.
    METHODS dispatch_sends        FOR TESTING.
    METHODS dispatch_simulation   FOR TESTING.
    METHODS dispatch_skip_idem    FOR TESTING.
    METHODS dispatch_force        FOR TESTING.
    METHODS dispatch_test_redirect FOR TESTING.
ENDCLASS.


CLASS ltc_processor IMPLEMENTATION.

  METHOD setup.
    mo_email = NEW #( ).
    mo_run   = NEW #( ).
    mo_cut   = NEW zcl_porel_processor(
      io_builder     = NEW zcl_porel_notif_builder( io_email_service = mo_email )
      io_run_control = mo_run ).
  ENDMETHOD.

  METHOD bundle_of.
    rt = VALUE #( ( recipient = VALUE #( email = iv_email disp_name = 'R' )
                    lines     = VALUE #( ( ebeln = '0000000001' netwr = 100 waers = 'EUR' ) ) ) ).
  ENDMETHOD.

  METHOD policy.
    rs = VALUE #( send = iv_send force = iv_force test_mode = iv_test
                  test_email = iv_test_email mode = 'S' langu = 'P' ).
  ENDMETHOD.


  METHOD actionable_from_frgzu.
    " PC/B3 (RD->SJ, SJ exige pos1); FRGZU com pos1 libertada -> SJ accionavel
    DATA(lt_pos) = VALUE zif_porel_types=>tt_po(
      ( ebeln = '0000000001' frggr = 'PC' frgsx = 'B3' frgzu = 'X' ) ).
    DATA(lt_strat) = VALUE zif_porel_types=>tt_strategy(
      ( frggr = 'PC' frgsx = 'B3'
        codes  = VALUE #( ( position = 1 frgco = 'RD' ) ( position = 2 frgco = 'SJ' ) )
        prereq = VALUE #( ( frgco = 'SJ' mask = 'X' ) ) ) ).

    DATA(lt_act) = mo_cut->compute_actionable(
      it_pos = lt_pos it_strategies = lt_strat iv_mode = 'S' ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_act ) exp = 1 msg = 'Uma etapa accionavel' ).
    READ TABLE lt_act INDEX 1 INTO DATA(ls_a).
    cl_abap_unit_assert=>assert_equals( act = ls_a-frgco exp = 'SJ' msg = 'A etapa accionavel e SJ' ).
  ENDMETHOD.

  METHOD lines_join_email.
    DATA(lt_lines) = mo_cut->build_notif_lines(
      it_actionable   = VALUE #( ( po = VALUE #( ebeln = '0000000001' frggr = 'PC' ekgrp = 'MPM' ) frgco = 'SJ' ) )
      it_responsibles = VALUE #( ( frggr = 'PC' frgco = 'SJ' bname = 'U1' ) )
      it_mails        = VALUE #( ( bname = 'U1' email = 'u1@hcb.co.mz' disp_name = 'User One' ) )
      it_texts        = VALUE #( ( frggr = 'PC' frgco = 'SJ' text = 'Assinatura' ) )
      iv_langu        = 'P' ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_lines ) exp = 1 msg = 'Uma linha' ).
    READ TABLE lt_lines INDEX 1 INTO DATA(ls).
    cl_abap_unit_assert=>assert_equals( act = ls-recipient-email exp = 'u1@hcb.co.mz' msg = 'E-mail resolvido' ).
    cl_abap_unit_assert=>assert_equals( act = ls-line-frgco_txt exp = 'Assinatura' msg = 'Texto da etapa' ).
  ENDMETHOD.

  METHOD lines_skip_no_email.
    " responsavel sem e-mail -> nenhuma linha (aviso; sem logger no teste)
    DATA(lt_lines) = mo_cut->build_notif_lines(
      it_actionable   = VALUE #( ( po = VALUE #( ebeln = '0000000001' frggr = 'PC' ) frgco = 'SJ' ) )
      it_responsibles = VALUE #( ( frggr = 'PC' frgco = 'SJ' bname = 'U1' ) )
      it_mails        = VALUE #( )
      it_texts        = VALUE #( )
      iv_langu        = 'P' ).

    cl_abap_unit_assert=>assert_initial( act = lt_lines msg = 'Sem e-mail nao gera linha' ).
  ENDMETHOD.

  METHOD dispatch_sends.
    DATA(lt) = mo_cut->dispatch(
      it_bundles = bundle_of( 'r@hcb.co.mz' ) is_policy = policy( ) iv_run_date = '20260811' ).

    cl_abap_unit_assert=>assert_equals( act = mo_email->mv_calls exp = 1 msg = 'Envia uma vez' ).
    cl_abap_unit_assert=>assert_equals( act = mo_run->mv_records exp = 1 msg = 'Regista o envio' ).
    cl_abap_unit_assert=>assert_equals( act = mo_run->mv_last_status exp = 'S' msg = 'Estado S' ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt ) exp = 1 msg = 'Um resultado' ).
  ENDMETHOD.

  METHOD dispatch_simulation.
    mo_cut->dispatch(
      it_bundles = bundle_of( 'r@hcb.co.mz' ) is_policy = policy( iv_send = abap_false ) iv_run_date = '20260811' ).

    cl_abap_unit_assert=>assert_equals( act = mo_email->mv_calls exp = 0 msg = 'Simulacao nao envia' ).
    cl_abap_unit_assert=>assert_equals( act = mo_run->mv_records exp = 0 msg = 'Simulacao nao regista' ).
  ENDMETHOD.

  METHOD dispatch_skip_idem.
    mo_run->mv_already = abap_true.
    mo_cut->dispatch(
      it_bundles = bundle_of( 'r@hcb.co.mz' ) is_policy = policy( ) iv_run_date = '20260811' ).

    cl_abap_unit_assert=>assert_equals( act = mo_email->mv_calls exp = 0 msg = 'Ja enviado -> nao reenvia' ).
    cl_abap_unit_assert=>assert_equals( act = mo_run->mv_last_status exp = 'K' msg = 'Regista salto (K)' ).
  ENDMETHOD.

  METHOD dispatch_force.
    mo_run->mv_already = abap_true.
    mo_cut->dispatch(
      it_bundles = bundle_of( 'r@hcb.co.mz' ) is_policy = policy( iv_force = abap_true ) iv_run_date = '20260811' ).

    cl_abap_unit_assert=>assert_equals( act = mo_email->mv_calls exp = 1 msg = 'P_FORCE ignora a idempotencia' ).
  ENDMETHOD.

  METHOD dispatch_test_redirect.
    mo_cut->dispatch(
      it_bundles = bundle_of( 'real@hcb.co.mz' )
      is_policy  = policy( iv_test = abap_true iv_test_email = 'teste@hcb.co.mz' )
      iv_run_date = '20260811' ).

    cl_abap_unit_assert=>assert_equals(
      act = mo_email->mv_last_addr exp = 'teste@hcb.co.mz' msg = 'Modo teste redirecciona' ).
  ENDMETHOD.

ENDCLASS.
