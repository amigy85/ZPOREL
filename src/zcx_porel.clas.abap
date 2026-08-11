"! <p class="shorttext synchronized">ZPOREL - excepcao</p>
"! Excepcao unica do ZPOREL, baseada em classe com IF_T100_MESSAGE. Reservada a
"! erros nao recuperaveis; customizing incompleto e tratado como aviso no BAL,
"! nunca como excepcao (ver especificacao secao 4).
CLASS zcx_porel DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_t100_message.

    CONSTANTS:
      "! Estrategia de liberacao nao encontrada no customizing (ZPOREL 001)
      BEGIN OF strategy_not_found,
        msgid TYPE symsgid VALUE 'ZPOREL',
        msgno TYPE symsgno VALUE '001',
        attr1 TYPE scx_attrname VALUE 'MV_FRGGR',
        attr2 TYPE scx_attrname VALUE 'MV_FRGSX',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF strategy_not_found,
      "! Pre-requisitos circulares na estrategia (ZPOREL 010)
      BEGIN OF circular_prerequisites,
        msgid TYPE symsgid VALUE 'ZPOREL',
        msgno TYPE symsgno VALUE '010',
        attr1 TYPE scx_attrname VALUE 'MV_FRGGR',
        attr2 TYPE scx_attrname VALUE 'MV_FRGSX',
        attr3 TYPE scx_attrname VALUE '',
        attr4 TYPE scx_attrname VALUE '',
      END OF circular_prerequisites.

    DATA mv_frggr TYPE frggr READ-ONLY.
    DATA mv_frgsx TYPE frgsx READ-ONLY.

    "! @parameter textid   | Chave de texto T100 (uma das constantes acima)
    "! @parameter previous | Excepcao anterior encadeada
    "! @parameter iv_frggr | Grupo de liberacao para o texto
    "! @parameter iv_frgsx | Estrategia de liberacao para o texto
    METHODS constructor
      IMPORTING
        textid   LIKE if_t100_message=>t100key OPTIONAL
        previous LIKE previous OPTIONAL
        iv_frggr TYPE frggr OPTIONAL
        iv_frgsx TYPE frgsx OPTIONAL.

ENDCLASS.


CLASS zcx_porel IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).

    mv_frggr = iv_frggr.
    mv_frgsx = iv_frgsx.

    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
