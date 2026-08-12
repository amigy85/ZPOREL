"! <p class="shorttext synchronized">ZPOREL - responsaveis via T16FW standard</p>
"! Implementa ZIF_POREL_RESP_PROV lendo a atribuicao standard de agentes ao
"! codigo de liberacao (T16FW). Fase 0 (ADR-003/D9): nos grupos PO todos os
"! agentes sao utilizadores (OTYPE = 'US') e WERKS e vazio. Agentes que nao
"! sejam utilizador (posicao/unidade organizacional) sao ignorados - nao
"! existem para POs nesta instalacao; a expansao organizacional fica fora de
"! ambito. Um codigo sem responsavel nao e erro (o chamador avisa no BAL).
CLASS zcl_porel_resp_prov_t16fw DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_porel_resp_prov.

  PRIVATE SECTION.
    CONSTANTS c_otype_user TYPE t16fw-otype VALUE 'US'.

    TYPES:
      BEGIN OF ty_t16fw,
        frggr TYPE t16fw-frggr,
        frgco TYPE t16fw-frgco,
        otype TYPE t16fw-otype,
        objid TYPE t16fw-objid,
      END OF ty_t16fw,
      tt_t16fw TYPE STANDARD TABLE OF ty_t16fw WITH DEFAULT KEY.

ENDCLASS.


CLASS zcl_porel_resp_prov_t16fw IMPLEMENTATION.

  METHOD zif_porel_resp_prov~get_responsibles.
    IF it_codes IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_t16fw TYPE tt_t16fw.
    SELECT frggr, frgco, otype, objid
      FROM t16fw
      FOR ALL ENTRIES IN @it_codes
      WHERE frggr = @it_codes-frggr
        AND frgco = @it_codes-frgco
      INTO TABLE @lt_t16fw.

    DATA ls_resp TYPE zif_porel_types=>ty_responsible.
    LOOP AT lt_t16fw INTO DATA(ls_w).
      IF ls_w-otype <> c_otype_user.
        CONTINUE.                           " so utilizadores (ver ABAP Doc)
      ENDIF.
      CLEAR ls_resp.
      ls_resp-frggr = ls_w-frggr.
      ls_resp-frgco = ls_w-frgco.
      ls_resp-bname = ls_w-objid.
      APPEND ls_resp TO rt_resp.
    ENDLOOP.

    " a mesma pessoa pode surgir em varios WERKS do mesmo codigo: deduplica
    SORT rt_resp BY frggr frgco bname.
    DELETE ADJACENT DUPLICATES FROM rt_resp COMPARING frggr frgco bname.
  ENDMETHOD.

ENDCLASS.
