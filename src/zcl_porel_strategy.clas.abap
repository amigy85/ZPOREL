"! <p class="shorttext synchronized">ZPOREL - regra de liberacao (logica pura)</p>
"! Determina, para uma PO, que codigos de liberacao estao pendentes e quais sao
"! accionaveis agora (pre-requisitos ja cumpridos). Logica pura (ADR-002): sem
"! SELECT, sem CALL FUNCTION, sem SY-DATUM. Recebe tudo por parametro; e a unica
"! forma de testar a serio a regra de negocio critica do relatorio.
CLASS zcl_porel_strategy DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! Devolve os codigos pendentes da PO, marcando os accionaveis.
    "! So entra no e-mail o que tiver IS_ACTIONABLE = abap_true.
    "! @parameter iv_frgzu  | Estado actual da liberacao (EKKO-FRGZU, CHAR8)
    "! @parameter it_codes  | Codigos da estrategia por posicao (T16FS)
    "! @parameter it_prereq | Mascara de pre-requisitos por codigo (T16FV normalizada)
    "! @parameter iv_mode   | Modo por omissao quando um codigo nao tem mascara (S/P)
    "! @parameter rt_pending | Codigos pendentes, com is_actionable e blocked_by
    METHODS get_pending_codes
      IMPORTING
        iv_frgzu          TYPE frgzu
        it_codes          TYPE zif_porel_types=>tt_strategy_code
        it_prereq         TYPE zif_porel_types=>tt_prereq
        iv_mode           TYPE c DEFAULT zif_porel_types=>c_mode-sequential
      RETURNING
        VALUE(rt_pending) TYPE zif_porel_types=>tt_pending_code.

    "! Devolve os codigos envolvidos em pre-requisitos circulares no customizing
    "! (vazio se nao houver). Usa apenas as mascaras explicitas de IT_PREREQ.
    "! @parameter it_codes  | Codigos da estrategia por posicao
    "! @parameter it_prereq | Mascara de pre-requisitos por codigo
    "! @parameter rt_cyclic | Codigos que participam num ciclo
    METHODS detect_circular
      IMPORTING
        it_codes         TYPE zif_porel_types=>tt_strategy_code
        it_prereq        TYPE zif_porel_types=>tt_prereq
      RETURNING
        VALUE(rt_cyclic) TYPE zif_porel_types=>tt_frgco.

  PRIVATE SECTION.

    CONSTANTS c_released TYPE c LENGTH 1 VALUE 'X'.
    CONSTANTS c_len      TYPE i VALUE 8.

    TYPES:
      BEGIN OF ty_edge,
        from TYPE frgco,
        to   TYPE frgco,
      END OF ty_edge,
      tt_edge TYPE STANDARD TABLE OF ty_edge WITH DEFAULT KEY.

    "! Posicao I (1..8) ja libertada em FRGZU?
    METHODS is_released
      IMPORTING
        iv_frgzu           TYPE frgzu
        iv_position        TYPE i
      RETURNING
        VALUE(rv_released) TYPE abap_bool.

    "! Codigo na posicao dada (inicial se a posicao nao tiver codigo).
    METHODS code_at_position
      IMPORTING
        it_codes        TYPE zif_porel_types=>tt_strategy_code
        iv_position     TYPE i
      RETURNING
        VALUE(rv_frgco) TYPE frgco.

    "! Mascara efectiva de pre-requisitos de um codigo: a explicita de IT_PREREQ
    "! se existir; senao a regra por omissao do modo (S = todas as posicoes
    "! anteriores com codigo; P = nenhuma).
    METHODS effective_mask
      IMPORTING
        it_codes       TYPE zif_porel_types=>tt_strategy_code
        it_prereq      TYPE zif_porel_types=>tt_prereq
        is_code        TYPE zif_porel_types=>ty_strategy_code
        iv_mode        TYPE c
      RETURNING
        VALUE(rv_mask) TYPE zif_porel_types=>ty_mask.

    "! Arestas do grafo de pre-requisitos (codigo -> codigo exigido antes).
    METHODS build_edges
      IMPORTING
        it_codes        TYPE zif_porel_types=>tt_strategy_code
        it_prereq       TYPE zif_porel_types=>tt_prereq
      RETURNING
        VALUE(rt_edges) TYPE tt_edge.

    "! Existe caminho de >= 1 aresta de IV_FROM ate IV_TARGET?
    METHODS is_reachable
      IMPORTING
        iv_from       TYPE frgco
        iv_target     TYPE frgco
        it_edges      TYPE tt_edge
      RETURNING
        VALUE(rv_yes) TYPE abap_bool.

ENDCLASS.


CLASS zcl_porel_strategy IMPLEMENTATION.

  METHOD get_pending_codes.
    DATA lv_pos     TYPE i.
    DATA lv_j       TYPE i.
    DATA lv_joff    TYPE i.
    DATA ls_pending TYPE zif_porel_types=>ty_pending_code.

    LOOP AT it_codes INTO DATA(ls_code).
      lv_pos = ls_code-position.
      IF lv_pos < 1 OR lv_pos > c_len.
        CONTINUE.                            " posicao invalida: ignora
      ENDIF.

      IF is_released( iv_frgzu = iv_frgzu iv_position = lv_pos ) = abap_true.
        CONTINUE.                            " ja libertado: nao esta pendente
      ENDIF.

      DATA(lv_mask) = effective_mask(
        it_codes  = it_codes
        it_prereq = it_prereq
        is_code   = ls_code
        iv_mode   = iv_mode ).

      CLEAR ls_pending.
      ls_pending-frgco         = ls_code-frgco.
      ls_pending-position      = lv_pos.
      ls_pending-is_actionable = abap_true.

      DO c_len TIMES.
        lv_j    = sy-index.
        lv_joff = lv_j - 1.
        IF lv_mask+lv_joff(1) <> c_released.
          CONTINUE.                          " posicao nao exigida
        ENDIF.

        " so bloqueia se a posicao exigida tiver codigo e nao estiver libertada;
        " mascara a apontar para posicao sem codigo e ignorada (aviso: caller)
        DATA(lv_req) = code_at_position( it_codes = it_codes iv_position = lv_j ).
        IF lv_req IS INITIAL.
          CONTINUE.
        ENDIF.
        IF is_released( iv_frgzu = iv_frgzu iv_position = lv_j ) = abap_false.
          ls_pending-is_actionable = abap_false.
          IF ls_pending-blocked_by IS INITIAL.
            ls_pending-blocked_by = lv_req.
          ELSE.
            ls_pending-blocked_by = |{ ls_pending-blocked_by } { lv_req }|.
          ENDIF.
        ENDIF.
      ENDDO.

      APPEND ls_pending TO rt_pending.
    ENDLOOP.
  ENDMETHOD.


  METHOD effective_mask.
    DATA lv_off TYPE i.

    READ TABLE it_prereq WITH TABLE KEY frgco = is_code-frgco INTO DATA(ls_prereq).
    IF sy-subrc = 0 AND ls_prereq-mask IS NOT INITIAL.
      rv_mask = ls_prereq-mask.               " mascara explicita (T16FV)
      RETURN.
    ENDIF.

    IF iv_mode = zif_porel_types=>c_mode-parallel.
      RETURN.                                 " sem pre-requisito: tudo accionavel
    ENDIF.

    " modo sequencial por omissao: exige todas as posicoes anteriores com codigo
    LOOP AT it_codes INTO DATA(ls_c) WHERE position < is_code-position.
      IF ls_c-position < 1 OR ls_c-position > c_len.
        CONTINUE.
      ENDIF.
      lv_off = ls_c-position - 1.
      rv_mask+lv_off(1) = c_released.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_released.
    DATA lv_off TYPE i.
    rv_released = abap_false.
    IF iv_position < 1 OR iv_position > c_len.
      RETURN.
    ENDIF.
    lv_off = iv_position - 1.
    IF iv_frgzu+lv_off(1) = c_released.
      rv_released = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD code_at_position.
    READ TABLE it_codes WITH KEY position = iv_position INTO DATA(ls_c).
    IF sy-subrc = 0.
      rv_frgco = ls_c-frgco.
    ENDIF.
  ENDMETHOD.


  METHOD detect_circular.
    DATA(lt_edges) = build_edges( it_codes = it_codes it_prereq = it_prereq ).

    LOOP AT it_codes INTO DATA(ls_code).
      IF is_reachable( iv_from   = ls_code-frgco
                       iv_target = ls_code-frgco
                       it_edges  = lt_edges ) = abap_true.
        APPEND ls_code-frgco TO rt_cyclic.
      ENDIF.
    ENDLOOP.

    SORT rt_cyclic.
    DELETE ADJACENT DUPLICATES FROM rt_cyclic.
  ENDMETHOD.


  METHOD build_edges.
    DATA lv_j    TYPE i.
    DATA lv_joff TYPE i.

    LOOP AT it_codes INTO DATA(ls_code).
      READ TABLE it_prereq WITH TABLE KEY frgco = ls_code-frgco INTO DATA(ls_prereq).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DO c_len TIMES.
        lv_j    = sy-index.
        lv_joff = lv_j - 1.
        IF ls_prereq-mask+lv_joff(1) <> c_released.
          CONTINUE.
        ENDIF.
        DATA(lv_req) = code_at_position( it_codes = it_codes iv_position = lv_j ).
        IF lv_req IS NOT INITIAL AND lv_req <> ls_code-frgco.
          APPEND VALUE ty_edge( from = ls_code-frgco to = lv_req ) TO rt_edges.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_reachable.
    DATA lt_stack TYPE zif_porel_types=>tt_frgco.
    DATA lt_seen  TYPE zif_porel_types=>tt_frgco.
    DATA lv_node  TYPE frgco.

    rv_yes = abap_false.

    LOOP AT it_edges INTO DATA(ls_e) WHERE from = iv_from.
      APPEND ls_e-to TO lt_stack.
    ENDLOOP.

    WHILE lt_stack IS NOT INITIAL.
      READ TABLE lt_stack INDEX 1 INTO lv_node.
      DELETE lt_stack INDEX 1.

      IF lv_node = iv_target.
        rv_yes = abap_true.
        RETURN.
      ENDIF.

      READ TABLE lt_seen TRANSPORTING NO FIELDS WITH KEY table_line = lv_node.
      IF sy-subrc = 0.
        CONTINUE.                             " ja visitado
      ENDIF.
      APPEND lv_node TO lt_seen.

      LOOP AT it_edges INTO ls_e WHERE from = lv_node.
        APPEND ls_e-to TO lt_stack.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
