"! <p class="shorttext synchronized">ZPOREL - leitura de POs e customizing</p>
"! Implementa ZIF_POREL_PO_READER. Concentra todo o acesso a base de dados
"! (EKKO/EKPO/LFA1 e T16FS/T16FV/T16FD). Sem regra de negocio: a decisao de
"! liberacao esta em ZCL_POREL_STRATEGY. Leituras em massa, zero SELECT em LOOP.
CLASS zcl_porel_po_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_porel_po_reader.

    "! Normaliza os indicadores FRGA1..8 da T16FV numa mascara CHAR8 de
    "! pre-requisitos: '+' (exigido antes) -> 'X'; 'X' (a propria posicao) e
    "! espaco -> espaco. Estatico e publico para teste unitario sem BD.
    "! @parameter iv_frga | FRGA1..8 concatenados (8 chars)
    "! @parameter rv_mask | Mascara de posicoes exigidas antes
    CLASS-METHODS normalize_prereq
      IMPORTING
        iv_frga        TYPE zif_porel_types=>ty_mask
      RETURNING
        VALUE(rv_mask) TYPE zif_porel_types=>ty_mask.

  PRIVATE SECTION.
    CONSTANTS c_len TYPE i VALUE 8.

    TYPES:
      BEGIN OF ty_key,
        frggr TYPE frggr,
        frgsx TYPE frgsx,
      END OF ty_key,
      tt_key TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY frggr frgsx,

      BEGIN OF ty_ekko,
        ebeln TYPE ekko-ebeln,
        bukrs TYPE ekko-bukrs,
        bstyp TYPE ekko-bstyp,
        bsart TYPE ekko-bsart,
        lifnr TYPE ekko-lifnr,
        ekorg TYPE ekko-ekorg,
        ekgrp TYPE ekko-ekgrp,
        waers TYPE ekko-waers,
        bedat TYPE ekko-bedat,
        aedat TYPE ekko-aedat,
        frggr TYPE ekko-frggr,
        frgsx TYPE ekko-frgsx,
        frgzu TYPE ekko-frgzu,
      END OF ty_ekko,
      tt_ekko TYPE STANDARD TABLE OF ty_ekko WITH DEFAULT KEY,

      BEGIN OF ty_val,
        ebeln TYPE ekko-ebeln,
        netwr TYPE ekpo-netwr,
      END OF ty_val,
      tt_val TYPE HASHED TABLE OF ty_val WITH UNIQUE KEY ebeln,

      BEGIN OF ty_name,
        lifnr TYPE lfa1-lifnr,
        name1 TYPE lfa1-name1,
      END OF ty_name,
      tt_name TYPE HASHED TABLE OF ty_name WITH UNIQUE KEY lifnr,

      BEGIN OF ty_t16fs,
        frggr TYPE t16fs-frggr,
        frgsx TYPE t16fs-frgsx,
        frgc1 TYPE t16fs-frgc1,
        frgc2 TYPE t16fs-frgc2,
        frgc3 TYPE t16fs-frgc3,
        frgc4 TYPE t16fs-frgc4,
        frgc5 TYPE t16fs-frgc5,
        frgc6 TYPE t16fs-frgc6,
        frgc7 TYPE t16fs-frgc7,
        frgc8 TYPE t16fs-frgc8,
      END OF ty_t16fs,
      tt_t16fs TYPE STANDARD TABLE OF ty_t16fs WITH DEFAULT KEY,

      BEGIN OF ty_t16fv,
        frggr TYPE t16fv-frggr,
        frgsx TYPE t16fv-frgsx,
        frgco TYPE t16fv-frgco,
        frga1 TYPE t16fv-frga1,
        frga2 TYPE t16fv-frga2,
        frga3 TYPE t16fv-frga3,
        frga4 TYPE t16fv-frga4,
        frga5 TYPE t16fv-frga5,
        frga6 TYPE t16fv-frga6,
        frga7 TYPE t16fv-frga7,
        frga8 TYPE t16fv-frga8,
      END OF ty_t16fv,
      tt_t16fv TYPE STANDARD TABLE OF ty_t16fv WITH DEFAULT KEY.

    METHODS distinct_keys
      IMPORTING
        it_pos         TYPE zif_porel_types=>tt_po
      RETURNING
        VALUE(rt_keys) TYPE tt_key.

    METHODS extract_codes
      IMPORTING
        is_row          TYPE ty_t16fs
      RETURNING
        VALUE(rt_codes) TYPE zif_porel_types=>tt_strategy_code.

    METHODS build_prereq
      IMPORTING
        it_t16fv         TYPE tt_t16fv
        iv_frggr         TYPE frggr
        iv_frgsx         TYPE frgsx
      RETURNING
        VALUE(rt_prereq) TYPE zif_porel_types=>tt_prereq.

ENDCLASS.


CLASS zcl_porel_po_reader IMPLEMENTATION.

  METHOD zif_porel_po_reader~read_pending_pos.
    DATA lt_ekko TYPE tt_ekko.

    SELECT ebeln, bukrs, bstyp, bsart, lifnr, ekorg, ekgrp, waers, bedat, aedat,
           frggr, frgsx, frgzu
      FROM ekko
      INTO TABLE @lt_ekko
      WHERE bstyp = 'F'
        AND loekz = @space
        AND frggr <> @space
        AND frgsx <> @space
        AND frgrl = 'X'
        AND ebeln IN @is_filter-ebeln
        AND bsart IN @is_filter-bsart
        AND ekorg IN @is_filter-ekorg
        AND ekgrp IN @is_filter-ekgrp
        AND lifnr IN @is_filter-lifnr
        AND bedat IN @is_filter-bedat
        AND frggr IN @is_filter-frggr.
    IF lt_ekko IS INITIAL.
      RETURN.
    ENDIF.

    " valor: soma dos itens activos (exclui POs sem qualquer item activo)
    SELECT ebeln, netwr
      FROM ekpo
      FOR ALL ENTRIES IN @lt_ekko
      WHERE ebeln = @lt_ekko-ebeln
        AND loekz = @space
      INTO TABLE @DATA(lt_items).

    DATA lt_val TYPE tt_val.
    DATA ls_val TYPE ty_val.
    LOOP AT lt_items INTO DATA(ls_item).
      ls_val-ebeln = ls_item-ebeln.
      ls_val-netwr = ls_item-netwr.
      COLLECT ls_val INTO lt_val.
    ENDLOOP.

    " nome do fornecedor
    SELECT lifnr, name1
      FROM lfa1
      FOR ALL ENTRIES IN @lt_ekko
      WHERE lifnr = @lt_ekko-lifnr
      INTO TABLE @DATA(lt_lfa1).

    DATA lt_name TYPE tt_name.
    DATA ls_name TYPE ty_name.
    LOOP AT lt_lfa1 INTO DATA(ls_l).
      ls_name-lifnr = ls_l-lifnr.
      ls_name-name1 = ls_l-name1.
      INSERT ls_name INTO TABLE lt_name.
    ENDLOOP.

    DATA ls_po TYPE zif_porel_types=>ty_po.
    LOOP AT lt_ekko INTO DATA(ls_ekko).
      READ TABLE lt_val WITH TABLE KEY ebeln = ls_ekko-ebeln INTO ls_val.
      IF sy-subrc <> 0.
        CONTINUE.                        " todos os itens eliminados: descarta
      ENDIF.
      CLEAR ls_po.
      MOVE-CORRESPONDING ls_ekko TO ls_po.
      ls_po-netwr = ls_val-netwr.
      READ TABLE lt_name WITH TABLE KEY lifnr = ls_ekko-lifnr INTO ls_name.
      IF sy-subrc = 0.
        ls_po-name1 = ls_name-name1.
      ENDIF.
      APPEND ls_po TO rt_pos.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_porel_po_reader~read_strategies.
    DATA(lt_keys) = distinct_keys( it_pos ).
    IF lt_keys IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_t16fs TYPE tt_t16fs.
    SELECT frggr, frgsx, frgc1, frgc2, frgc3, frgc4, frgc5, frgc6, frgc7, frgc8
      FROM t16fs
      FOR ALL ENTRIES IN @lt_keys
      WHERE frggr = @lt_keys-frggr
        AND frgsx = @lt_keys-frgsx
      INTO TABLE @lt_t16fs.

    DATA lt_t16fv TYPE tt_t16fv.
    SELECT frggr, frgsx, frgco, frga1, frga2, frga3, frga4, frga5, frga6, frga7, frga8
      FROM t16fv
      FOR ALL ENTRIES IN @lt_keys
      WHERE frggr = @lt_keys-frggr
        AND frgsx = @lt_keys-frgsx
      INTO TABLE @lt_t16fv.

    DATA ls_strat TYPE zif_porel_types=>ty_strategy.
    LOOP AT lt_t16fs INTO DATA(ls_fs).
      CLEAR ls_strat.
      ls_strat-frggr  = ls_fs-frggr.
      ls_strat-frgsx  = ls_fs-frgsx.
      ls_strat-codes  = extract_codes( ls_fs ).
      ls_strat-prereq = build_prereq( it_t16fv = lt_t16fv
                                      iv_frggr = ls_fs-frggr
                                      iv_frgsx = ls_fs-frgsx ).
      INSERT ls_strat INTO TABLE rt_strategies.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_porel_po_reader~read_code_texts.
    IF it_codes IS INITIAL.
      RETURN.
    ENDIF.

    SELECT frggr, frgco, frgct
      FROM t16fd
      FOR ALL ENTRIES IN @it_codes
      WHERE frggr = @it_codes-frggr
        AND frgco = @it_codes-frgco
        AND spras = @iv_langu
      INTO TABLE @DATA(lt_txt).

    DATA ls_txt TYPE zif_porel_types=>ty_code_text.
    LOOP AT lt_txt INTO DATA(ls_t).
      CLEAR ls_txt.
      ls_txt-frggr = ls_t-frggr.
      ls_txt-frgco = ls_t-frgco.
      ls_txt-text  = ls_t-frgct.
      INSERT ls_txt INTO TABLE rt_texts.
    ENDLOOP.
  ENDMETHOD.


  METHOD distinct_keys.
    DATA ls_key TYPE ty_key.
    LOOP AT it_pos INTO DATA(ls_po).
      ls_key-frggr = ls_po-frggr.
      ls_key-frgsx = ls_po-frgsx.
      INSERT ls_key INTO TABLE rt_keys.       " sorted unique: duplicados ignorados
    ENDLOOP.
  ENDMETHOD.


  METHOD extract_codes.
    IF is_row-frgc1 IS NOT INITIAL.
      APPEND VALUE #( position = 1 frgco = is_row-frgc1 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc2 IS NOT INITIAL.
      APPEND VALUE #( position = 2 frgco = is_row-frgc2 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc3 IS NOT INITIAL.
      APPEND VALUE #( position = 3 frgco = is_row-frgc3 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc4 IS NOT INITIAL.
      APPEND VALUE #( position = 4 frgco = is_row-frgc4 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc5 IS NOT INITIAL.
      APPEND VALUE #( position = 5 frgco = is_row-frgc5 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc6 IS NOT INITIAL.
      APPEND VALUE #( position = 6 frgco = is_row-frgc6 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc7 IS NOT INITIAL.
      APPEND VALUE #( position = 7 frgco = is_row-frgc7 ) TO rt_codes.
    ENDIF.
    IF is_row-frgc8 IS NOT INITIAL.
      APPEND VALUE #( position = 8 frgco = is_row-frgc8 ) TO rt_codes.
    ENDIF.
  ENDMETHOD.


  METHOD build_prereq.
    DATA ls_pr   TYPE zif_porel_types=>ty_prereq.
    DATA lv_frga TYPE zif_porel_types=>ty_mask.

    LOOP AT it_t16fv INTO DATA(ls_fv) WHERE frggr = iv_frggr AND frgsx = iv_frgsx.
      CLEAR lv_frga.
      lv_frga+0(1) = ls_fv-frga1.
      lv_frga+1(1) = ls_fv-frga2.
      lv_frga+2(1) = ls_fv-frga3.
      lv_frga+3(1) = ls_fv-frga4.
      lv_frga+4(1) = ls_fv-frga5.
      lv_frga+5(1) = ls_fv-frga6.
      lv_frga+6(1) = ls_fv-frga7.
      lv_frga+7(1) = ls_fv-frga8.

      CLEAR ls_pr.
      ls_pr-frgco = ls_fv-frgco.
      ls_pr-mask  = normalize_prereq( lv_frga ).
      INSERT ls_pr INTO TABLE rt_prereq.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalize_prereq.
    DATA lv_off TYPE i.
    DO c_len TIMES.
      lv_off = sy-index - 1.
      IF iv_frga+lv_off(1) = '+'.
        rv_mask+lv_off(1) = 'X'.
      ENDIF.
    ENDDO.
  ENDMETHOD.

ENDCLASS.
