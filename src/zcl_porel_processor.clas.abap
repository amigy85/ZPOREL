"! <p class="shorttext synchronized">ZPOREL - orquestracao da notificacao</p>
"! Caso de uso "notificar responsaveis": le POs, aplica a regra de liberacao,
"! resolve responsaveis e e-mails, agrega e envia, com idempotencia semanal e
"! modo teste. Dependencias injectadas (com instanciacao por omissao), para o
"! report ser simples e os testes isolados. O processor nao conhece SQL nem HTML.
CLASS zcl_porel_processor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING
        io_reader      TYPE REF TO zif_porel_po_reader     OPTIONAL
        io_resp_prov   TYPE REF TO zif_porel_resp_prov     OPTIONAL
        io_resolver    TYPE REF TO zcl_porel_mail_resolver OPTIONAL
        io_run_control TYPE REF TO zif_porel_run_control   OPTIONAL
        io_builder     TYPE REF TO zcl_porel_notif_builder OPTIONAL
        io_logger      TYPE REF TO zif_logger              OPTIONAL.

    "! Fluxo completo: seleccao -> regra -> responsaveis -> e-mail -> envio.
    METHODS notify
      IMPORTING
        is_filter  TYPE zif_porel_types=>ty_po_filter
        is_policy  TYPE zif_porel_types=>ty_run_policy
      EXPORTING
        et_results TYPE zif_porel_types=>tt_send_result
        et_lines   TYPE zif_porel_types=>tt_notif_line
      RAISING
        zcx_porel.

    "! Determina as etapas accionaveis de cada PO (usa a regra pura). Testavel.
    METHODS compute_actionable
      IMPORTING
        it_pos              TYPE zif_porel_types=>tt_po
        it_strategies       TYPE zif_porel_types=>tt_strategy
        iv_mode             TYPE c
      RETURNING
        VALUE(rt_actionable) TYPE zif_porel_types=>tt_actionable.

    "! Cruza etapas accionaveis, responsaveis, e-mails e textos em linhas de
    "! notificacao. Avisa (BAL) codigos sem responsavel e utilizadores sem
    "! e-mail. Testavel.
    METHODS build_notif_lines
      IMPORTING
        it_actionable   TYPE zif_porel_types=>tt_actionable
        it_responsibles TYPE zif_porel_types=>tt_responsible
        it_mails        TYPE zif_porel_types=>tt_resolved_mail
        it_texts        TYPE zif_porel_types=>tt_code_text
        iv_langu        TYPE spras
      RETURNING
        VALUE(rt_lines) TYPE zif_porel_types=>tt_notif_line.

    "! Envia os pacotes aplicando idempotencia, modo teste e simulacao. Testavel.
    METHODS dispatch
      IMPORTING
        it_bundles        TYPE zif_porel_types=>tt_recipient_bundle
        is_policy         TYPE zif_porel_types=>ty_run_policy
        iv_run_date       TYPE dats
      RETURNING
        VALUE(rt_results) TYPE zif_porel_types=>tt_send_result.

  PRIVATE SECTION.

    DATA mo_reader      TYPE REF TO zif_porel_po_reader.
    DATA mo_resp_prov   TYPE REF TO zif_porel_resp_prov.
    DATA mo_resolver    TYPE REF TO zcl_porel_mail_resolver.
    DATA mo_run_control TYPE REF TO zif_porel_run_control.
    DATA mo_builder     TYPE REF TO zcl_porel_notif_builder.
    DATA mo_logger      TYPE REF TO zif_logger.
    DATA mo_strategy    TYPE REF TO zcl_porel_strategy.

    METHODS distinct_code_keys
      IMPORTING it_actionable  TYPE zif_porel_types=>tt_actionable
      RETURNING VALUE(rt_keys) TYPE zif_porel_types=>tt_code_key.

    METHODS distinct_bnames
      IMPORTING it_responsibles  TYPE zif_porel_types=>tt_responsible
      RETURNING VALUE(rt_bnames) TYPE zif_porel_types=>tt_bname.

    METHODS get_iso_week
      IMPORTING iv_date        TYPE dats
      RETURNING VALUE(rv_week)  TYPE zif_porel_types=>ty_iso_week.

    METHODS emit
      IMPORTING iv_number TYPE symsgno
                iv_type   TYPE symsgty DEFAULT 'W'
                iv_v1     TYPE clike DEFAULT space
                iv_v2     TYPE clike DEFAULT space.

ENDCLASS.


CLASS zcl_porel_processor IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.      mo_reader = io_reader.           ELSE. mo_reader = NEW zcl_porel_po_reader( ).           ENDIF.
    IF io_resp_prov IS BOUND.   mo_resp_prov = io_resp_prov.     ELSE. mo_resp_prov = NEW zcl_porel_resp_prov_t16fw( ).   ENDIF.
    IF io_resolver IS BOUND.    mo_resolver = io_resolver.       ELSE. mo_resolver = NEW zcl_porel_mail_resolver( ).      ENDIF.
    IF io_run_control IS BOUND. mo_run_control = io_run_control. ELSE. mo_run_control = NEW zcl_porel_run_control( ).     ENDIF.
    IF io_builder IS BOUND.     mo_builder = io_builder.         ELSE. mo_builder = NEW zcl_porel_notif_builder( ).       ENDIF.
    mo_logger   = io_logger.
    mo_strategy = NEW zcl_porel_strategy( ).
  ENDMETHOD.


  METHOD notify.
    DATA(lt_pos) = mo_reader->read_pending_pos( is_filter ).
    IF lt_pos IS INITIAL.
      emit( iv_number = '009' iv_type = 'I' ).
      RETURN.
    ENDIF.

    DATA(lt_strat) = mo_reader->read_strategies( lt_pos ).
    DATA(lt_act)   = compute_actionable( it_pos = lt_pos it_strategies = lt_strat iv_mode = is_policy-mode ).
    IF lt_act IS INITIAL.
      emit( iv_number = '009' iv_type = 'I' ).
      RETURN.
    ENDIF.

    DATA(lt_keys) = distinct_code_keys( lt_act ).
    DATA(lt_resp) = mo_resp_prov->get_responsibles( lt_keys ).
    DATA(lt_txt)  = mo_reader->read_code_texts( it_codes = lt_keys iv_langu = is_policy-langu ).

    DATA(lt_bnames) = distinct_bnames( lt_resp ).
    DATA(lt_mail)   = mo_resolver->resolve_emails( lt_bnames ).

    DATA(lt_lines)   = build_notif_lines( it_actionable   = lt_act
                                          it_responsibles = lt_resp
                                          it_mails        = lt_mail
                                          it_texts        = lt_txt
                                          iv_langu        = is_policy-langu ).
    et_lines = lt_lines.

    DATA(lt_bundles) = mo_builder->aggregate( lt_lines ).

    emit( iv_number = '004' iv_type = 'I'
          iv_v1 = |{ lines( lt_lines ) }| iv_v2 = |{ lines( lt_bundles ) }| ).

    et_results = dispatch( it_bundles = lt_bundles is_policy = is_policy iv_run_date = sy-datum ).

    IF mo_logger IS BOUND.
      mo_logger->save( ).
    ENDIF.

    " O framework ZEMAIL (ZCL_EMAIL_SENDER_BCS) usa CL_BCS=>CREATE_PERSISTENT e
    " NAO faz COMMIT WORK: delega a LUW na aplicacao chamadora. Sem este commit
    " as ordens de envio ficam "Em espera" sem entrada na fila SAPconnect (SOST,
    " msg SO672) e os registos de idempotencia (ZPOREL_RUN) e o log BAL nao
    " persistem. Um unico commit fecha a LUW de toda a execucao. Fica em NOTIFY
    " (fronteira do caso de uso), nunca em DISPATCH — que os testes unitarios
    " exercitam directamente.
    COMMIT WORK.
  ENDMETHOD.


  METHOD compute_actionable.
    DATA ls_act TYPE zif_porel_types=>ty_actionable.
    LOOP AT it_pos INTO DATA(ls_po).
      READ TABLE it_strategies WITH TABLE KEY frggr = ls_po-frggr frgsx = ls_po-frgsx INTO DATA(ls_strat).
      IF sy-subrc <> 0.
        emit( iv_number = '001' iv_v1 = ls_po-frggr iv_v2 = ls_po-frgsx ).
        CONTINUE.
      ENDIF.

      DATA(lt_pending) = mo_strategy->get_pending_codes(
        iv_frgzu  = ls_po-frgzu
        it_codes  = ls_strat-codes
        it_prereq = ls_strat-prereq
        iv_mode   = iv_mode ).

      LOOP AT lt_pending INTO DATA(ls_pc) WHERE is_actionable = abap_true.
        CLEAR ls_act.
        ls_act-po    = ls_po.
        ls_act-frgco = ls_pc-frgco.
        APPEND ls_act TO rt_actionable.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_notif_lines.
    DATA ls_nl  TYPE zif_porel_types=>ty_notif_line.
    DATA lv_txt TYPE t16fd-frgct.

    LOOP AT it_actionable INTO DATA(ls_a).
      CLEAR lv_txt.
      READ TABLE it_texts WITH TABLE KEY frggr = ls_a-po-frggr frgco = ls_a-frgco INTO DATA(ls_t).
      IF sy-subrc = 0.
        lv_txt = ls_t-text.
      ENDIF.

      DATA(lv_has_resp) = abap_false.
      LOOP AT it_responsibles INTO DATA(ls_r)
           WHERE frggr = ls_a-po-frggr AND frgco = ls_a-frgco.
        lv_has_resp = abap_true.

        READ TABLE it_mails WITH TABLE KEY bname = ls_r-bname INTO DATA(ls_m).
        IF sy-subrc <> 0.
          emit( iv_number = '003' iv_v1 = ls_r-bname ).
          CONTINUE.
        ENDIF.

        CLEAR ls_nl.
        ls_nl-recipient = VALUE #( email     = ls_m-email
                                   disp_name = ls_m-disp_name
                                   langu     = iv_langu
                                   bname     = ls_r-bname ).
        ls_nl-line = VALUE #( ebeln     = ls_a-po-ebeln
                              bsart     = ls_a-po-bsart
                              lifnr     = ls_a-po-lifnr
                              name1     = ls_a-po-name1
                              bedat     = ls_a-po-bedat
                              netwr     = ls_a-po-netwr
                              waers     = ls_a-po-waers
                              frgco     = ls_a-frgco
                              frgco_txt = lv_txt
                              ekgrp     = ls_a-po-ekgrp ).
        APPEND ls_nl TO rt_lines.
      ENDLOOP.

      IF lv_has_resp = abap_false.
        emit( iv_number = '002' iv_v1 = ls_a-frgco ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD dispatch.
    DATA(lv_week) = get_iso_week( iv_run_date ).
    DATA ls_bundle TYPE zif_porel_types=>ty_recipient_bundle.

    LOOP AT it_bundles INTO ls_bundle.
      DATA(lv_email_orig) = ls_bundle-recipient-email.

      IF is_policy-test_mode = abap_true.
        ls_bundle-recipient-email = is_policy-test_email.
      ENDIF.

      IF is_policy-force = abap_false AND is_policy-test_mode = abap_false.
        IF mo_run_control->already_sent( iv_iso_week = lv_week iv_email = lv_email_orig ) = abap_true.
          mo_run_control->record( iv_iso_week  = lv_week
                                  iv_email     = lv_email_orig
                                  iv_po_count  = lines( ls_bundle-lines )
                                  iv_status    = 'K'
                                  iv_send_id   = space
                                  iv_message   = space
                                  iv_test_mode = abap_false ).
          emit( iv_number = '007' iv_type = 'I' iv_v1 = lv_email_orig iv_v2 = lv_week ).
          CONTINUE.
        ENDIF.
      ENDIF.

      IF is_policy-send = abap_false.
        CONTINUE.                          " simulacao: nao envia, nao regista
      ENDIF.

      DATA(ls_res) = mo_builder->send_bundle( is_bundle    = ls_bundle
                                              iv_exec_date = iv_run_date
                                              iv_iso_week  = lv_week ).

      mo_run_control->record( iv_iso_week  = lv_week
                              iv_email     = lv_email_orig
                              iv_po_count  = ls_res-po_count
                              iv_status    = ls_res-status
                              iv_send_id   = ls_res-send_id
                              iv_message   = ls_res-message
                              iv_test_mode = is_policy-test_mode ).

      IF ls_res-status = zif_email_const=>send_status-success.
        emit( iv_number = '005' iv_type = 'I' iv_v1 = lv_email_orig iv_v2 = |{ ls_res-po_count }| ).
      ELSE.
        emit( iv_number = '006' iv_type = 'E' iv_v1 = lv_email_orig iv_v2 = ls_res-message ).
      ENDIF.

      APPEND ls_res TO rt_results.
    ENDLOOP.
  ENDMETHOD.


  METHOD distinct_code_keys.
    LOOP AT it_actionable INTO DATA(ls_a).
      INSERT VALUE #( frggr = ls_a-po-frggr frgco = ls_a-frgco ) INTO TABLE rt_keys.
    ENDLOOP.
  ENDMETHOD.


  METHOD distinct_bnames.
    DATA lt_seen TYPE HASHED TABLE OF xubname WITH UNIQUE KEY table_line.
    LOOP AT it_responsibles INTO DATA(ls_r).
      INSERT ls_r-bname INTO TABLE lt_seen.
    ENDLOOP.
    LOOP AT lt_seen INTO DATA(lv_b).
      APPEND lv_b TO rt_bnames.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_iso_week.
    DATA lv_week TYPE scal-week.
    CALL FUNCTION 'DATE_GET_WEEK'
      EXPORTING
        date         = iv_date
      IMPORTING
        week         = lv_week
      EXCEPTIONS
        date_invalid = 1
        OTHERS       = 2.
    IF sy-subrc = 0.
      rv_week = |{ lv_week(4) }W{ lv_week+4(2) }|.
    ENDIF.
  ENDMETHOD.


  METHOD emit.
    IF mo_logger IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA lv_text TYPE string.
    MESSAGE ID 'ZPOREL' TYPE iv_type NUMBER iv_number WITH iv_v1 iv_v2 INTO lv_text.
    CASE iv_type.
      WHEN 'I'.
        mo_logger->info( lv_text ).
      WHEN 'E'.
        mo_logger->error( iv_text = lv_text ).
      WHEN OTHERS.
        mo_logger->warning( lv_text ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
