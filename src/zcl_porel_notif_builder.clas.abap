"! <p class="shorttext synchronized">ZPOREL - construcao e envio da notificacao</p>
"! Modelo de dados do e-mail: agrega as linhas por destinatario (um e-mail por
"! pessoa), pre-formata valores/datas em ABAP (D4 - o FORMAT do ZEMAIL esta
"! furado) e constroi as linhas <tr> da tabela (FORMAT=HTML, D3). Envia pela
"! fachada ZIF_EMAIL_SERVICE. Segue o padrao de ZCL_ASSIST_NOTIF_BUILDER.
CLASS zcl_porel_notif_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! @parameter io_email_service | Servico de e-mail (fallback: factory do ZEMAIL)
    "! @parameter iv_template_id   | Template child (default ZPO_PEND_RELEASE)
    "! @parameter iv_langu         | Idioma por omissao do e-mail
    "! @parameter iv_link_text     | Texto de {{LINK_ME29N}} (configuravel)
    METHODS constructor
      IMPORTING
        io_email_service TYPE REF TO zif_email_service OPTIONAL
        iv_template_id   TYPE zemail_template_id DEFAULT 'ZPO_PEND_RELEASE'
        iv_langu         TYPE spras DEFAULT 'P'
        iv_link_text     TYPE string OPTIONAL.

    "! Agrupa as linhas achatadas por destinatario (e-mail), ordenando cada
    "! conjunto por valor descendente. Puro e testavel.
    "! @parameter it_lines   | Linhas (destinatario + linha de PO)
    "! @parameter rt_bundles | Um pacote por destinatario
    METHODS aggregate
      IMPORTING
        it_lines          TYPE zif_porel_types=>tt_notif_line
      RETURNING
        VALUE(rt_bundles) TYPE zif_porel_types=>tt_recipient_bundle.

    "! Constroi e envia o e-mail de um destinatario. Uma falha do servico nao
    "! rebenta: devolve o resultado com estado de erro.
    "! @parameter is_bundle    | Destinatario + linhas
    "! @parameter iv_exec_date | Data de execucao ({{DATA}})
    "! @parameter iv_iso_week  | Semana ISO ({{REF}})
    "! @parameter rs_result    | Resultado do envio
    METHODS send_bundle
      IMPORTING
        is_bundle        TYPE zif_porel_types=>ty_recipient_bundle
        iv_exec_date     TYPE dats
        iv_iso_week      TYPE zif_porel_types=>ty_iso_week
      RETURNING
        VALUE(rs_result) TYPE zif_porel_types=>ty_send_result.

    "! Moeda predominante das linhas, ou '-' se houver mais de uma. Testavel.
    METHODS predominant_currency
      IMPORTING
        it_lines        TYPE zif_porel_types=>tt_po_line
      RETURNING
        VALUE(rv_waers) TYPE waers.

  PRIVATE SECTION.

    CONSTANTS c_mixed TYPE waers VALUE '-'.
    CONSTANTS c_default_link TYPE string
      VALUE 'Para aprovar, aceda à transacção ME29N no sistema SAP.'.

    " Logo HCB embutido inline via CID (T3.5/T3.6, ZCL_EMAIL_RENDERER) — o master
    " ZHCB_MASTER_PO tem <img src="cid:logo_hcb">, que so resolve se o e-mail levar
    " o anexo inline correspondente. Mesmo content-id e caminho MIME do ZASSIST
    " (ZCL_ASSIST_MEDIC_PROCESSOR); o PNG e carregado a mao em /SAP/PUBLIC/ZHCB.
    CONSTANTS c_logo_content_id TYPE zemail_content_id VALUE 'logo_hcb'.
    CONSTANTS c_logo_mime_path  TYPE string VALUE '/SAP/PUBLIC/ZHCB/logo_hcb.png'.

    DATA mo_email_service TYPE REF TO zif_email_service.
    DATA mv_template_id   TYPE zemail_template_id.
    DATA mv_langu         TYPE spras.
    DATA mv_link_text     TYPE string.

    METHODS build_values
      IMPORTING
        is_bundle        TYPE zif_porel_types=>ty_recipient_bundle
        iv_exec_date     TYPE dats
        iv_iso_week      TYPE zif_porel_types=>ty_iso_week
      RETURNING
        VALUE(rt_values) TYPE zemail_t_placeholder.

    METHODS build_rows
      IMPORTING
        it_lines       TYPE zif_porel_types=>tt_po_line
      RETURNING
        VALUE(rv_html) TYPE string.

    METHODS build_single_row
      IMPORTING
        is_line       TYPE zif_porel_types=>ty_po_line
        iv_even       TYPE abap_bool
      RETURNING
        VALUE(rv_row) TYPE string.

    METHODS format_amount
      IMPORTING
        iv_amount      TYPE ekpo-netwr
        iv_waers       TYPE waers
      RETURNING
        VALUE(rv_text) TYPE string.

    METHODS format_date
      IMPORTING
        iv_date        TYPE dats
      RETURNING
        VALUE(rv_text) TYPE string.

    METHODS esc
      IMPORTING
        iv_text        TYPE string
      RETURNING
        VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_porel_notif_builder IMPLEMENTATION.

  METHOD constructor.
    mo_email_service = COND #(
      WHEN io_email_service IS BOUND THEN io_email_service
      ELSE zcl_email_factory=>create_notification_service(
        it_images = VALUE #( ( content_id = c_logo_content_id mime_path = c_logo_mime_path ) ) ) ).
    mv_template_id = iv_template_id.
    mv_langu       = iv_langu.
    mv_link_text   = COND #( WHEN iv_link_text IS NOT INITIAL THEN iv_link_text ELSE c_default_link ).
  ENDMETHOD.


  METHOD aggregate.
    TYPES:
      BEGIN OF ty_agg,
        email  TYPE ad_smtpadr,
        bundle TYPE zif_porel_types=>ty_recipient_bundle,
      END OF ty_agg.
    DATA lt_agg TYPE HASHED TABLE OF ty_agg WITH UNIQUE KEY email.
    DATA ls_agg TYPE ty_agg.

    LOOP AT it_lines INTO DATA(ls_nl).
      IF ls_nl-recipient-email IS INITIAL.
        CONTINUE.                          " sem e-mail nao agrega (caller avisa)
      ENDIF.

      READ TABLE lt_agg ASSIGNING FIELD-SYMBOL(<agg>)
        WITH TABLE KEY email = ls_nl-recipient-email.
      IF sy-subrc <> 0.
        CLEAR ls_agg.
        ls_agg-email             = ls_nl-recipient-email.
        ls_agg-bundle-recipient  = ls_nl-recipient.
        INSERT ls_agg INTO TABLE lt_agg ASSIGNING <agg>.
      ENDIF.
      APPEND ls_nl-line TO <agg>-bundle-lines.
    ENDLOOP.

    LOOP AT lt_agg INTO ls_agg.
      SORT ls_agg-bundle-lines BY netwr DESCENDING.
      APPEND ls_agg-bundle TO rt_bundles.
    ENDLOOP.
  ENDMETHOD.


  METHOD send_bundle.
    rs_result-email    = is_bundle-recipient-email.
    rs_result-po_count = lines( is_bundle-lines ).

    DATA(lt_recipients) = VALUE zemail_t_recipient(
      ( address        = is_bundle-recipient-email
        visible_name   = is_bundle-recipient-disp_name
        recipient_type = zif_email_const=>recipient_type-to_addr ) ).

    DATA(lv_langu) = COND spras(
      WHEN is_bundle-recipient-langu IS NOT INITIAL THEN is_bundle-recipient-langu
      ELSE mv_langu ).

    TRY.
        DATA(ls_send) = mo_email_service->send(
          iv_template_id = mv_template_id
          iv_langu       = lv_langu
          it_recipients  = lt_recipients
          it_values      = build_values( is_bundle    = is_bundle
                                         iv_exec_date = iv_exec_date
                                         iv_iso_week  = iv_iso_week ) ).
        rs_result-status  = zif_email_const=>send_status-success.
        rs_result-send_id = ls_send-send_id.
        rs_result-message = ls_send-message.

      CATCH zcx_email INTO DATA(lx_email).
        rs_result-status  = zif_email_const=>send_status-error.
        rs_result-message = lx_email->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD build_values.
    DATA(lv_total) = REDUCE ekpo-netwr(
      INIT s = CONV ekpo-netwr( 0 )
      FOR ls IN is_bundle-lines
      NEXT s = s + ls-netwr ).

    DATA(lv_moeda) = predominant_currency( is_bundle-lines ).

    DATA(lv_nome) = COND string(
      WHEN is_bundle-recipient-disp_name IS NOT INITIAL THEN is_bundle-recipient-disp_name
      ELSE |{ is_bundle-recipient-bname }| ).

    rt_values = VALUE #(
      ( name = 'DATA'             value = format_date( iv_exec_date )
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'REF'              value = |{ iv_iso_week }|
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'NOME_RESPONSAVEL' value = lv_nome
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'TOTAL_PO'         value = |{ lines( is_bundle-lines ) }|
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'VALOR_TOTAL'      value = format_amount( iv_amount = lv_total iv_waers = lv_moeda )
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'MOEDA'            value = |{ lv_moeda }|
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'LINK_ME29N'       value = mv_link_text
        format = zif_email_const=>placeholder_format-plain )
      ( name = 'LINHAS_POS'       value = build_rows( is_bundle-lines )
        format = zif_email_const=>placeholder_format-html ) ).
  ENDMETHOD.


  METHOD build_rows.
    DATA lv_idx  TYPE i VALUE 0.
    DATA lv_even TYPE abap_bool.
    LOOP AT it_lines INTO DATA(ls).
      lv_idx  = lv_idx + 1.
      lv_even = COND #( WHEN lv_idx MOD 2 = 0 THEN abap_true ELSE abap_false ).
      rv_html = rv_html && build_single_row( is_line = ls iv_even = lv_even ).
    ENDLOOP.
  ENDMETHOD.


  METHOD build_single_row.
    DATA(lv_bg) = COND string( WHEN iv_even = abap_true THEN '#f5f5fa' ELSE '#ffffff' ).

    DATA(lv_cell) = |style="padding:9px 8px; font-family:Arial,Helvetica,sans-serif;|
                 && | font-size:13px; color:#333333; background-color:{ lv_bg };|
                 && | border-bottom:1px solid #ededf3;"|.
    DATA(lv_cell_r) = |style="padding:9px 8px; font-family:Arial,Helvetica,sans-serif;|
                   && | font-size:13px; color:#333333; background-color:{ lv_bg };|
                   && | border-bottom:1px solid #ededf3; text-align:right; white-space:nowrap;"|.

    rv_row =
         |<tr>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-ebeln ALPHA = OUT }| ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-bsart }| ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-name1 }| ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( format_date( is_line-bedat ) ) }</td>|
      && |<td class="tbl-cell" { lv_cell_r }>{ esc( format_amount( iv_amount = is_line-netwr iv_waers = is_line-waers ) ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-waers }| ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-frgco } { is_line-frgco_txt }| ) }</td>|
      && |<td class="tbl-cell" { lv_cell }>{ esc( |{ is_line-ekgrp }| ) }</td>|
      && |</tr>|.
  ENDMETHOD.


  METHOD predominant_currency.
    DATA lt_w TYPE SORTED TABLE OF waers WITH UNIQUE KEY table_line.
    LOOP AT it_lines INTO DATA(ls).
      INSERT ls-waers INTO TABLE lt_w.
    ENDLOOP.
    IF lines( lt_w ) = 1.
      READ TABLE lt_w INDEX 1 INTO rv_waers.
    ELSE.
      rv_waers = c_mixed.
    ENDIF.
  ENDMETHOD.


  METHOD format_amount.
    DATA lv_char TYPE char30.
    IF iv_waers IS INITIAL OR iv_waers = c_mixed.
      WRITE iv_amount TO lv_char.
    ELSE.
      WRITE iv_amount TO lv_char CURRENCY iv_waers.
    ENDIF.
    CONDENSE lv_char.
    rv_text = lv_char.
  ENDMETHOD.


  METHOD format_date.
    IF iv_date IS INITIAL.
      RETURN.
    ENDIF.
    rv_text = |{ iv_date+6(2) }.{ iv_date+4(2) }.{ iv_date(4) }|.
  ENDMETHOD.


  METHOD esc.
    rv_text = escape( val = iv_text format = cl_abap_format=>e_html_text ).
  ENDMETHOD.

ENDCLASS.
