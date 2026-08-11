"! <p class="shorttext synchronized">ZPOREL - leitura de POs e customizing</p>
"! Toda a leitura de base de dados de POs e do customizing de liberacao esta
"! atras desta interface (regra da dependencia: o processor nao conhece SQL).
INTERFACE zif_porel_po_reader
  PUBLIC.

  "! Le as POs pendentes de liberacao (EKKO/EKPO/LFA1) segundo o filtro.
  "! Aplica FRGRL = 'X', BSTYP = 'F', cabecalho e itens nao eliminados, e
  "! soma EKPO-NETWR por documento.
  "! @parameter is_filter | Filtro do ecra de seleccao
  "! @parameter rt_pos    | POs pendentes, com valor e nome do fornecedor
  "! @raising zcx_porel   | Erro de leitura nao recuperavel
  METHODS read_pending_pos
    IMPORTING
      is_filter     TYPE zif_porel_types=>ty_po_filter
    RETURNING
      VALUE(rt_pos) TYPE zif_porel_types=>tt_po
    RAISING
      zcx_porel.

  "! Le as estrategias (T16FS + T16FV) dos pares frggr/frgsx presentes nas POs.
  "! Os pre-requisitos da T16FV sao normalizados em mascara CHAR8 por codigo.
  "! @parameter it_pos        | POs ja seleccionadas
  "! @parameter rt_strategies | Estrategias com codigos e pre-requisitos
  "! @raising zcx_porel       | Erro de leitura nao recuperavel
  METHODS read_strategies
    IMPORTING
      it_pos               TYPE zif_porel_types=>tt_po
    RETURNING
      VALUE(rt_strategies) TYPE zif_porel_types=>tt_strategy
    RAISING
      zcx_porel.

  "! Le os textos dos codigos de liberacao (T16FD-FRGCT) no idioma dado.
  "! @parameter it_codes | Pares grupo/codigo
  "! @parameter iv_langu | Idioma do texto
  "! @parameter rt_texts | Texto por grupo/codigo
  "! @raising zcx_porel  | Erro de leitura nao recuperavel
  METHODS read_code_texts
    IMPORTING
      it_codes        TYPE zif_porel_types=>tt_code_key
      iv_langu        TYPE spras
    RETURNING
      VALUE(rt_texts) TYPE zif_porel_types=>tt_code_text
    RAISING
      zcx_porel.

ENDINTERFACE.
