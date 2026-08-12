"! Testa a regra D6 de escolha de e-mail (pick_email). As leituras USR21/ADR6
"! sao validadas por execucao no sistema (testes nao tocam a BD).
CLASS ltc_resolver DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS default_wins_over_consnumber FOR TESTING.
    METHODS no_default_lowest_cons       FOR TESTING.
    METHODS empty_returns_empty          FOR TESTING.
    METHODS single_candidate             FOR TESTING.
ENDCLASS.


CLASS ltc_resolver IMPLEMENTATION.

  METHOD default_wins_over_consnumber.
    " caso real DGO_LS: cons 1 sem flag, cons 2 marcado -> ganha o marcado,
    " mesmo nao sendo o menor CONSNUMBER.
    DATA(lt) = VALUE zcl_porel_mail_resolver=>tt_addr_cand(
      ( consnumber = 1 flgdefault = ''  smtp_addr = 'Manuel.Balawe@hcb.co.mz' )
      ( consnumber = 2 flgdefault = 'X' smtp_addr = 'luis.simone@hcb.co.mz' )
      ( consnumber = 3 flgdefault = ''  smtp_addr = 'Joao.Chambene@hcb.co.mz' ) ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_mail_resolver=>pick_email( lt )
      exp = 'luis.simone@hcb.co.mz'
      msg = 'FLGDEFAULT ganha, nao o menor CONSNUMBER' ).
  ENDMETHOD.

  METHOD no_default_lowest_cons.
    " sem nenhum marcado -> menor CONSNUMBER
    DATA(lt) = VALUE zcl_porel_mail_resolver=>tt_addr_cand(
      ( consnumber = 3 flgdefault = '' smtp_addr = 'c@hcb.co.mz' )
      ( consnumber = 1 flgdefault = '' smtp_addr = 'a@hcb.co.mz' )
      ( consnumber = 2 flgdefault = '' smtp_addr = 'b@hcb.co.mz' ) ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_mail_resolver=>pick_email( lt )
      exp = 'a@hcb.co.mz'
      msg = 'Sem default, cai para o menor CONSNUMBER' ).
  ENDMETHOD.

  METHOD empty_returns_empty.
    cl_abap_unit_assert=>assert_initial(
      act = zcl_porel_mail_resolver=>pick_email( VALUE #( ) )
      msg = 'Sem candidatos -> vazio' ).
  ENDMETHOD.

  METHOD single_candidate.
    DATA(lt) = VALUE zcl_porel_mail_resolver=>tt_addr_cand(
      ( consnumber = 1 flgdefault = '' smtp_addr = 'x@hcb.co.mz' ) ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_mail_resolver=>pick_email( lt )
      exp = 'x@hcb.co.mz'
      msg = 'Candidato unico e escolhido' ).
  ENDMETHOD.

ENDCLASS.
