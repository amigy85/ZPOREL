"! Duplo do servico de e-mail: regista a chamada e captura os placeholders.
CLASS ltd_email DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_email_service.
    DATA mv_calls      TYPE i.
    DATA mv_last_addr  TYPE ad_smtpadr.
    DATA mt_last_vals  TYPE zemail_t_placeholder.
ENDCLASS.

CLASS ltd_email IMPLEMENTATION.
  METHOD zif_email_service~send.
    mv_calls = mv_calls + 1.
    READ TABLE it_recipients INDEX 1 INTO DATA(ls_r).
    mv_last_addr  = ls_r-address.
    mt_last_vals  = it_values.
    rs_result-status  = zif_email_const=>send_status-success.
    rs_result-send_id = 'TST'.
  ENDMETHOD.
ENDCLASS.


"! Testa agregacao, moeda predominante e o envio/formatacao (via duplo).
CLASS ltc_builder DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_dbl TYPE REF TO ltd_email.
    DATA mo_cut TYPE REF TO zcl_porel_notif_builder.

    METHODS setup.
    METHODS val_of
      IMPORTING it_vals    TYPE zemail_t_placeholder
                iv_name    TYPE string
      RETURNING VALUE(rv)  TYPE string.

    METHODS aggregate_by_email FOR TESTING.
    METHODS currency_single    FOR TESTING.
    METHODS currency_mixed     FOR TESTING.
    METHODS send_and_format    FOR TESTING.
ENDCLASS.


CLASS ltc_builder IMPLEMENTATION.

  METHOD setup.
    mo_dbl = NEW #( ).
    mo_cut = NEW #( io_email_service = mo_dbl ).
  ENDMETHOD.

  METHOD val_of.
    READ TABLE it_vals INTO DATA(ls) WITH KEY name = iv_name.
    IF sy-subrc = 0.
      rv = ls-value.
    ENDIF.
  ENDMETHOD.

  METHOD aggregate_by_email.
    DATA(lt_lines) = VALUE zif_porel_types=>tt_notif_line(
      ( recipient = VALUE #( email = 'a@hcb.co.mz' )
        line      = VALUE #( ebeln = '0000000001' netwr = 100 waers = 'EUR' ) )
      ( recipient = VALUE #( email = 'a@hcb.co.mz' )
        line      = VALUE #( ebeln = '0000000002' netwr = 300 waers = 'EUR' ) )
      ( recipient = VALUE #( email = 'b@hcb.co.mz' )
        line      = VALUE #( ebeln = '0000000003' netwr = 50  waers = 'EUR' ) ) ).

    DATA(lt_b) = mo_cut->aggregate( lt_lines ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_b ) exp = 2 msg = 'Dois destinatarios distintos -> dois pacotes' ).

    READ TABLE lt_b INTO DATA(ls_a) WITH KEY recipient-email = 'a@hcb.co.mz'.
    cl_abap_unit_assert=>assert_equals(
      act = lines( ls_a-lines ) exp = 2 msg = 'a@ tem 2 POs num so e-mail' ).
    " ordenado por valor descendente
    READ TABLE ls_a-lines INDEX 1 INTO DATA(ls_top).
    cl_abap_unit_assert=>assert_equals(
      act = ls_top-netwr exp = 300 msg = 'Linhas ordenadas por valor desc' ).
  ENDMETHOD.

  METHOD currency_single.
    DATA(lt) = VALUE zif_porel_types=>tt_po_line(
      ( waers = 'EUR' ) ( waers = 'EUR' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->predominant_currency( lt ) exp = 'EUR'
      msg = 'Moeda unica' ).
  ENDMETHOD.

  METHOD currency_mixed.
    DATA(lt) = VALUE zif_porel_types=>tt_po_line(
      ( waers = 'EUR' ) ( waers = 'MZN' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->predominant_currency( lt ) exp = '-'
      msg = 'Moedas mistas -> traco' ).
  ENDMETHOD.

  METHOD send_and_format.
    DATA(ls_bundle) = VALUE zif_porel_types=>ty_recipient_bundle(
      recipient = VALUE #( email = 'fulano@hcb.co.mz' disp_name = 'Fulano de Tal' )
      lines     = VALUE #(
        ( ebeln = '0000000001' bsart = 'NB' netwr = 100 waers = 'EUR' bedat = '20260801'
          frgco = 'GA' ekgrp = 'MPM' )
        ( ebeln = '0000000002' bsart = 'NB' netwr = 300 waers = 'EUR' bedat = '20260802'
          frgco = 'RD' ekgrp = 'MPM' ) ) ).

    DATA(ls_res) = mo_cut->send_bundle(
      is_bundle    = ls_bundle
      iv_exec_date = '20260811'
      iv_iso_week  = '2026-W33' ).

    " envio
    cl_abap_unit_assert=>assert_equals( act = mo_dbl->mv_calls exp = 1 msg = 'Envia uma vez' ).
    cl_abap_unit_assert=>assert_equals(
      act = mo_dbl->mv_last_addr exp = 'fulano@hcb.co.mz' msg = 'Destinatario correcto' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_res-status exp = zif_email_const=>send_status-success msg = 'Estado sucesso' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_res-po_count exp = 2 msg = 'Duas POs' ).

    " placeholders / formatacao
    cl_abap_unit_assert=>assert_equals(
      act = val_of( it_vals = mo_dbl->mt_last_vals iv_name = 'DATA' ) exp = '11.08.2026'
      msg = 'Data formatada DD.MM.AAAA' ).
    cl_abap_unit_assert=>assert_equals(
      act = val_of( it_vals = mo_dbl->mt_last_vals iv_name = 'MOEDA' ) exp = 'EUR'
      msg = 'Moeda predominante' ).
    cl_abap_unit_assert=>assert_equals(
      act = val_of( it_vals = mo_dbl->mt_last_vals iv_name = 'TOTAL_PO' ) exp = '2'
      msg = 'Total de POs' ).
    cl_abap_unit_assert=>assert_equals(
      act = val_of( it_vals = mo_dbl->mt_last_vals iv_name = 'NOME_RESPONSAVEL' ) exp = 'Fulano de Tal'
      msg = 'Nome de apresentacao' ).

    DATA(lv_rows) = val_of( it_vals = mo_dbl->mt_last_vals iv_name = 'LINHAS_POS' ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_rows CS '<tr>' ) msg = 'Linhas de tabela geradas em HTML' ).
  ENDMETHOD.

ENDCLASS.
