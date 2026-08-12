"! <p class="shorttext synchronized">ZPOREL - controlo de idempotencia</p>
"! Abstrai o registo semanal de envios (ZPOREL_RUN). Permite ao processor
"! saltar segundos envios na mesma semana e ser testado com um duplo.
INTERFACE zif_porel_run_control
  PUBLIC.

  "! Ja foi enviado (com sucesso, nao teste) a este destinatario nesta semana?
  "! @parameter iv_iso_week | Semana ISO
  "! @parameter iv_email    | Destinatario
  "! @parameter rv_yes      | abap_true se ja existe envio bem-sucedido
  METHODS already_sent
    IMPORTING
      iv_iso_week   TYPE zif_porel_types=>ty_iso_week
      iv_email      TYPE ad_smtpadr
    RETURNING
      VALUE(rv_yes) TYPE abap_bool.

  "! Regista o resultado de um envio (ou um salto) em ZPOREL_RUN.
  "! @parameter iv_iso_week  | Semana ISO
  "! @parameter iv_email     | Destinatario (endereco original, chave semanal)
  "! @parameter iv_po_count  | Nº de POs
  "! @parameter iv_status    | S sucesso / E erro / K saltado
  "! @parameter iv_send_id   | ID devolvido pelo ZEMAIL
  "! @parameter iv_message   | Texto de erro, se houver
  "! @parameter iv_test_mode | Execucao em modo teste (nao conta para a semana)
  METHODS record
    IMPORTING
      iv_iso_week  TYPE zif_porel_types=>ty_iso_week
      iv_email     TYPE ad_smtpadr
      iv_po_count  TYPE i
      iv_status    TYPE c
      iv_send_id   TYPE string
      iv_message   TYPE string
      iv_test_mode TYPE abap_bool.

ENDINTERFACE.
