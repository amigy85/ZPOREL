"! Testes da regra de liberacao (especificacao secao 9). Logica pura, sem BD.
CLASS ltc_strategy DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_porel_strategy.

    METHODS setup.

    " --- utilitarios ---
    "! Mascara CHAR8 com 'X' nas posicoes indicadas por digitos (ex.: '12').
    METHODS mask_of
      IMPORTING iv_digits      TYPE string
      RETURNING VALUE(rv_mask) TYPE zif_porel_types=>ty_mask.
    "! Codigos accionaveis, ordenados.
    METHODS actionables
      IMPORTING it_pending   TYPE zif_porel_types=>tt_pending_code
      RETURNING VALUE(rt)    TYPE zif_porel_types=>tt_frgco.
    "! Linha pendente de um codigo.
    METHODS pending_of
      IMPORTING it_pending    TYPE zif_porel_types=>tt_pending_code
                iv_frgco      TYPE frgco
      RETURNING VALUE(rs)     TYPE zif_porel_types=>ty_pending_code.

    " --- casos de teste (secao 9) ---
    METHODS single_level             FOR TESTING.
    METHODS sequential_three         FOR TESTING.
    METHODS parallel_three           FOR TESTING.
    METHODS mixed_prereq             FOR TESTING.
    METHODS all_released             FOR TESTING.
    METHODS empty_strategy           FOR TESTING.
    METHODS circular                 FOR TESTING.
    METHODS nomask_sequential        FOR TESTING.
    METHODS nomask_parallel          FOR TESTING.
    METHODS mask_to_empty_position   FOR TESTING.
ENDCLASS.


CLASS ltc_strategy IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD mask_of.
    DATA lv_off TYPE i.
    DATA lv_i   TYPE i.
    DATA lv_pos TYPE i.
    DO strlen( iv_digits ) TIMES.
      lv_i  = sy-index - 1.
      lv_pos = CONV i( iv_digits+lv_i(1) ).
      lv_off = lv_pos - 1.
      IF lv_off >= 0 AND lv_off < 8.
        rv_mask+lv_off(1) = 'X'.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD actionables.
    LOOP AT it_pending INTO DATA(ls) WHERE is_actionable = abap_true.
      APPEND ls-frgco TO rt.
    ENDLOOP.
    SORT rt.
  ENDMETHOD.

  METHOD pending_of.
    READ TABLE it_pending WITH KEY frgco = iv_frgco INTO rs.
  ENDMETHOD.


  METHOD single_level.
    " Estrategia de 1 nivel, FRGZU vazio -> 1 codigo accionavel.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = space
      it_codes  = VALUE #( ( position = 1 frgco = 'AA' ) )
      it_prereq = VALUE #( ) ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt ) exp = VALUE zif_porel_types=>tt_frgco( ( 'AA' ) )
      msg = 'Nivel unico com FRGZU vazio deve ser accionavel' ).
  ENDMETHOD.

  METHOD sequential_three.
    " 3 niveis sequenciais, FRGZU = pos1 libertada -> so nivel 2 accionavel;
    " nivel 3 pendente mas bloqueado pelo 2.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = mask_of( '1' )
      it_codes  = VALUE #( ( position = 1 frgco = 'C1' )
                           ( position = 2 frgco = 'C2' )
                           ( position = 3 frgco = 'C3' ) )
      it_prereq = VALUE #( ( frgco = 'C2' mask = mask_of( '1' ) )
                           ( frgco = 'C3' mask = mask_of( '12' ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt ) exp = VALUE zif_porel_types=>tt_frgco( ( 'C2' ) )
      msg = 'Sequencial: so o nivel 2 e accionavel' ).
    cl_abap_unit_assert=>assert_equals(
      act = pending_of( it_pending = lt iv_frgco = 'C3' )-blocked_by exp = 'C2'
      msg = 'Nivel 3 bloqueado pelo 2' ).
  ENDMETHOD.

  METHOD parallel_three.
    " 3 niveis paralelos (sem pre-requisitos), FRGZU vazio, modo P -> 3 accionaveis.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = space
      it_codes  = VALUE #( ( position = 1 frgco = 'P1' )
                           ( position = 2 frgco = 'P2' )
                           ( position = 3 frgco = 'P3' ) )
      it_prereq = VALUE #( )
      iv_mode   = zif_porel_types=>c_mode-parallel ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt )
      exp = VALUE zif_porel_types=>tt_frgco( ( 'P1' ) ( 'P2' ) ( 'P3' ) )
      msg = 'Paralelo sem pre-requisitos: todos accionaveis' ).
  ENDMETHOD.

  METHOD mixed_prereq.
    " Niveis 1 e 2 sem dependencia, nivel 3 depende de ambos; so o 1 libertado
    " -> 2 accionavel, 3 bloqueado.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = mask_of( '1' )
      it_codes  = VALUE #( ( position = 1 frgco = 'M1' )
                           ( position = 2 frgco = 'M2' )
                           ( position = 3 frgco = 'M3' ) )
      it_prereq = VALUE #( ( frgco = 'M3' mask = mask_of( '12' ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt ) exp = VALUE zif_porel_types=>tt_frgco( ( 'M2' ) )
      msg = 'Misto: 2 accionavel, 3 bloqueado' ).
    cl_abap_unit_assert=>assert_false(
      act = pending_of( it_pending = lt iv_frgco = 'M3' )-is_actionable
      msg = 'Nivel 3 nao accionavel' ).
  ENDMETHOD.

  METHOD all_released.
    " FRGZU com tudo libertado -> nada pendente.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = mask_of( '12' )
      it_codes  = VALUE #( ( position = 1 frgco = 'A1' )
                           ( position = 2 frgco = 'A2' ) )
      it_prereq = VALUE #( ) ).

    cl_abap_unit_assert=>assert_initial(
      act = lt msg = 'Tudo libertado: nenhum pendente' ).
  ENDMETHOD.

  METHOD empty_strategy.
    " Estrategia inexistente (sem codigos) -> vazio, sem dump.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = space
      it_codes  = VALUE #( )
      it_prereq = VALUE #( ) ).

    cl_abap_unit_assert=>assert_initial(
      act = lt msg = 'Sem codigos: resultado vazio' ).
  ENDMETHOD.

  METHOD circular.
    " Pre-requisitos circulares (A exige B, B exige A) -> nenhum accionavel,
    " e detect_circular devolve ambos.
    DATA(lt_codes) = VALUE zif_porel_types=>tt_strategy_code(
      ( position = 1 frgco = 'CA' ) ( position = 2 frgco = 'CB' ) ).
    DATA(lt_prereq) = VALUE zif_porel_types=>tt_prereq(
      ( frgco = 'CA' mask = mask_of( '2' ) )
      ( frgco = 'CB' mask = mask_of( '1' ) ) ).

    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu = space it_codes = lt_codes it_prereq = lt_prereq ).
    cl_abap_unit_assert=>assert_initial(
      act = actionables( lt ) msg = 'Ciclo: nenhum accionavel' ).

    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->detect_circular( it_codes = lt_codes it_prereq = lt_prereq )
      exp = VALUE zif_porel_types=>tt_frgco( ( 'CA' ) ( 'CB' ) )
      msg = 'detect_circular deve apanhar os dois codigos' ).
  ENDMETHOD.

  METHOD nomask_sequential.
    " Sem mascara, modo S: FRGZU = pos1 libertada, 3 niveis -> so nivel 2.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = mask_of( '1' )
      it_codes  = VALUE #( ( position = 1 frgco = 'S1' )
                           ( position = 2 frgco = 'S2' )
                           ( position = 3 frgco = 'S3' ) )
      it_prereq = VALUE #( )
      iv_mode   = zif_porel_types=>c_mode-sequential ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt ) exp = VALUE zif_porel_types=>tt_frgco( ( 'S2' ) )
      msg = 'Sem mascara, modo S: so o proximo por libertar' ).
  ENDMETHOD.

  METHOD nomask_parallel.
    " Sem mascara, modo P: os mesmos dados -> niveis 2 e 3 accionaveis.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = mask_of( '1' )
      it_codes  = VALUE #( ( position = 1 frgco = 'S1' )
                           ( position = 2 frgco = 'S2' )
                           ( position = 3 frgco = 'S3' ) )
      it_prereq = VALUE #( )
      iv_mode   = zif_porel_types=>c_mode-parallel ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt )
      exp = VALUE zif_porel_types=>tt_frgco( ( 'S2' ) ( 'S3' ) )
      msg = 'Sem mascara, modo P: todos os pendentes accionaveis' ).
  ENDMETHOD.

  METHOD mask_to_empty_position.
    " Mascara aponta para posicao sem codigo -> posicao ignorada, sem bloquear.
    DATA(lt) = mo_cut->get_pending_codes(
      iv_frgzu  = space
      it_codes  = VALUE #( ( position = 1 frgco = 'E1' ) )
      it_prereq = VALUE #( ( frgco = 'E1' mask = mask_of( '3' ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = actionables( lt ) exp = VALUE zif_porel_types=>tt_frgco( ( 'E1' ) )
      msg = 'Pre-requisito para posicao sem codigo e ignorado' ).
  ENDMETHOD.

ENDCLASS.
