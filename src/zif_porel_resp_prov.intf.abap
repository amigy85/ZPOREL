"! <p class="shorttext synchronized">ZPOREL - fornecedor de responsaveis</p>
"! Abstrai a origem dos responsaveis por codigo de liberacao. A implementacao
"! actual le a T16FW standard; overrides/CC entram como implementacao adicional
"! sem alterar os consumidores (ADR-003, camada Z adiada).
INTERFACE zif_porel_resp_prov
  PUBLIC.

  "! Devolve os utilizadores responsaveis pelos codigos de liberacao dados.
  "! Um codigo sem responsavel nao e erro: devolve simplesmente nada para ele
  "! (o consumidor regista aviso no BAL).
  "! @parameter it_codes | Pares grupo/codigo accionaveis
  "! @parameter rt_resp  | Responsaveis (grupo/codigo/utilizador)
  "! @raising zcx_porel  | Erro de leitura nao recuperavel
  METHODS get_responsibles
    IMPORTING
      it_codes       TYPE zif_porel_types=>tt_code_key
    RETURNING
      VALUE(rt_resp) TYPE zif_porel_types=>tt_responsible
    RAISING
      zcx_porel.

ENDINTERFACE.
