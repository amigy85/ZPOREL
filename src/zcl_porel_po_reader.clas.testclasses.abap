"! Testa a logica pura do reader: normalizacao dos pre-requisitos T16FV (D5).
"! As leituras SQL sao validadas por execucao no sistema (testes nao tocam a BD).
CLASS ltc_reader DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS plus_becomes_x       FOR TESTING.
    METHODS own_position_ignored FOR TESTING.
    METHODS all_space_empty      FOR TESTING.
    METHODS real_case_three      FOR TESTING.
ENDCLASS.


CLASS ltc_reader IMPLEMENTATION.

  METHOD plus_becomes_x.
    " '+' exige, 'X' (posicao propria) e ignorado
    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_po_reader=>normalize_prereq( '++X' )
      exp = 'XX'
      msg = '+ vira X; a propria posicao (X) nao entra na mascara' ).
  ENDMETHOD.

  METHOD own_position_ignored.
    " so a propria posicao marcada: sem pre-requisitos
    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_po_reader=>normalize_prereq( 'X' )
      exp = space
      msg = 'Sem + a mascara e vazia' ).
  ENDMETHOD.

  METHOD all_space_empty.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_po_reader=>normalize_prereq( space )
      exp = space
      msg = 'Tudo espaco -> mascara vazia' ).
  ENDMETHOD.

  METHOD real_case_three.
    " caso real (PT/B3, codigo PC): FRGA = '+++X' -> exige posicoes 1,2,3
    cl_abap_unit_assert=>assert_equals(
      act = zcl_porel_po_reader=>normalize_prereq( '+++X' )
      exp = 'XXX'
      msg = 'Tres pre-requisitos posicionais' ).
  ENDMETHOD.

ENDCLASS.
