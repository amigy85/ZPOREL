"! <p class="shorttext synchronized">ZPOREL - tipos de trabalho</p>
"! Todos os tipos de trabalho do ZPOREL vivem aqui (ADR-001): nao ha
"! representacao DDIC para eles em 7.40 e nenhum e persistido nem usado por RFC.
INTERFACE zif_porel_types
  PUBLIC.

  " ----- Definicao da estrategia de liberacao -----
  TYPES:
    "! Mascara CHAR8 de posicoes (mesmo formato de EKKO-FRGZU / pre-requisitos)
    ty_mask TYPE c LENGTH 8,
    "! Semana ISO no e-mail (ex.: '2026-W33')
    ty_iso_week TYPE c LENGTH 8,
    "! Codigo numa posicao da estrategia (T16FS: posicao -> codigo)
    BEGIN OF ty_strategy_code,
      position TYPE i,
      frgco    TYPE frgco,
    END OF ty_strategy_code,
    tt_strategy_code TYPE STANDARD TABLE OF ty_strategy_code WITH DEFAULT KEY,

    "! Mascara de pre-requisitos por codigo (T16FV normalizada): 'X' na
    "! posicao que tem de estar libertada antes deste codigo.
    BEGIN OF ty_prereq,
      frgco TYPE frgco,
      mask  TYPE ty_mask,
    END OF ty_prereq,
    tt_prereq TYPE HASHED TABLE OF ty_prereq WITH UNIQUE KEY frgco,

    "! Estrategia completa (chave frggr/frgsx)
    BEGIN OF ty_strategy,
      frggr  TYPE frggr,
      frgsx  TYPE frgsx,
      codes  TYPE tt_strategy_code,
      prereq TYPE tt_prereq,
    END OF ty_strategy,
    tt_strategy TYPE HASHED TABLE OF ty_strategy WITH UNIQUE KEY frggr frgsx,

    tt_frgco TYPE STANDARD TABLE OF frgco WITH DEFAULT KEY,

    "! Codigo pendente devolvido pela regra de liberacao
    BEGIN OF ty_pending_code,
      frgco         TYPE frgco,
      position      TYPE i,
      is_actionable TYPE abap_bool,
      blocked_by    TYPE string,
    END OF ty_pending_code,
    tt_pending_code TYPE STANDARD TABLE OF ty_pending_code WITH DEFAULT KEY.

  " ----- Modo por omissao quando nao ha pre-requisitos configurados -----
  CONSTANTS:
    BEGIN OF c_mode,
      sequential TYPE c LENGTH 1 VALUE 'S',
      parallel   TYPE c LENGTH 1 VALUE 'P',
    END OF c_mode.

  " ----- PO pendente (linha de trabalho do reader) -----
  TYPES:
    BEGIN OF ty_po,
      ebeln        TYPE ekko-ebeln,
      bukrs        TYPE ekko-bukrs,
      bstyp        TYPE ekko-bstyp,
      bsart        TYPE ekko-bsart,
      lifnr        TYPE ekko-lifnr,
      name1        TYPE lfa1-name1,
      ekorg        TYPE ekko-ekorg,
      ekgrp        TYPE ekko-ekgrp,
      waers        TYPE ekko-waers,
      bedat        TYPE ekko-bedat,
      aedat        TYPE ekko-aedat,
      frggr        TYPE ekko-frggr,
      frgsx        TYPE ekko-frgsx,
      frgzu        TYPE ekko-frgzu,
      netwr        TYPE ekpo-netwr,
    END OF ty_po,
    tt_po TYPE STANDARD TABLE OF ty_po WITH DEFAULT KEY,

    "! Chave de codigo de liberacao (grupo + codigo)
    BEGIN OF ty_code_key,
      frggr TYPE frggr,
      frgco TYPE frgco,
    END OF ty_code_key,
    tt_code_key TYPE HASHED TABLE OF ty_code_key WITH UNIQUE KEY frggr frgco,

    "! Texto do codigo de liberacao (T16FD-FRGCT)
    BEGIN OF ty_code_text,
      frggr TYPE frggr,
      frgco TYPE frgco,
      text  TYPE t16fd-frgct,
    END OF ty_code_text,
    tt_code_text TYPE HASHED TABLE OF ty_code_text WITH UNIQUE KEY frggr frgco,

    "! Responsavel (agente) de um codigo, antes de resolver e-mail
    BEGIN OF ty_responsible,
      frggr TYPE frggr,
      frgco TYPE frgco,
      bname TYPE xubname,
    END OF ty_responsible,
    tt_responsible TYPE STANDARD TABLE OF ty_responsible WITH DEFAULT KEY.

  " ----- Resolucao de e-mail (USR21 -> ADR6 -> ADRP) -----
  TYPES:
    tt_bname TYPE STANDARD TABLE OF xubname WITH DEFAULT KEY,
    BEGIN OF ty_resolved_mail,
      bname     TYPE xubname,
      email     TYPE ad_smtpadr,
      disp_name TYPE ad_namtext,
    END OF ty_resolved_mail,
    tt_resolved_mail TYPE HASHED TABLE OF ty_resolved_mail WITH UNIQUE KEY bname.

  " ----- Linha do e-mail e destinatario agregado -----
  TYPES:
    BEGIN OF ty_po_line,
      ebeln     TYPE ekko-ebeln,
      bsart     TYPE ekko-bsart,
      lifnr     TYPE ekko-lifnr,
      name1     TYPE lfa1-name1,
      bedat     TYPE ekko-bedat,
      netwr     TYPE ekpo-netwr,
      waers     TYPE ekko-waers,
      frgco     TYPE frgco,
      frgco_txt TYPE t16fd-frgct,
      ekgrp     TYPE ekko-ekgrp,
    END OF ty_po_line,
    tt_po_line TYPE STANDARD TABLE OF ty_po_line WITH DEFAULT KEY,

    BEGIN OF ty_recipient,
      email     TYPE ad_smtpadr,
      disp_name TYPE ad_namtext,
      langu     TYPE spras,
      bname     TYPE xubname,
    END OF ty_recipient,
    tt_recipient TYPE STANDARD TABLE OF ty_recipient WITH DEFAULT KEY,

    BEGIN OF ty_recipient_bundle,
      recipient TYPE ty_recipient,
      lines     TYPE tt_po_line,
    END OF ty_recipient_bundle,
    tt_recipient_bundle TYPE STANDARD TABLE OF ty_recipient_bundle WITH DEFAULT KEY.

  " ----- Entrada/saida do notif builder -----
  TYPES:
    "! Linha achatada (destinatario + uma linha de PO) antes de agregar
    BEGIN OF ty_notif_line,
      recipient TYPE ty_recipient,
      line      TYPE ty_po_line,
    END OF ty_notif_line,
    tt_notif_line TYPE STANDARD TABLE OF ty_notif_line WITH DEFAULT KEY,
    "! Resultado do envio por destinatario
    BEGIN OF ty_send_result,
      email    TYPE ad_smtpadr,
      po_count TYPE i,
      status   TYPE c LENGTH 1,
      send_id  TYPE string,
      message  TYPE string,
    END OF ty_send_result,
    tt_send_result TYPE STANDARD TABLE OF ty_send_result WITH DEFAULT KEY.

  " ----- Filtro do reader (do ecra de seleccao) -----
  TYPES:
    tr_ebeln TYPE RANGE OF ekko-ebeln,
    tr_bsart TYPE RANGE OF ekko-bsart,
    tr_ekorg TYPE RANGE OF ekko-ekorg,
    tr_ekgrp TYPE RANGE OF ekko-ekgrp,
    tr_lifnr TYPE RANGE OF ekko-lifnr,
    tr_bedat TYPE RANGE OF ekko-bedat,
    tr_frggr TYPE RANGE OF ekko-frggr,
    BEGIN OF ty_po_filter,
      ebeln    TYPE tr_ebeln,
      bsart    TYPE tr_bsart,
      ekorg    TYPE tr_ekorg,
      ekgrp    TYPE tr_ekgrp,
      lifnr    TYPE tr_lifnr,
      bedat    TYPE tr_bedat,
      frggr    TYPE tr_frggr,
    END OF ty_po_filter.

ENDINTERFACE.
