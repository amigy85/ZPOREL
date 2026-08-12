"! <p class="shorttext synchronized">ZPOREL - resolucao de e-mail (USR21/ADR6)</p>
"! Traduz utilizadores SAP (BNAME) em enderecos SMTP. Leitura em massa:
"! USR21 (BNAME -> PERSNUMBER/ADDRNUMBER) -> ADR6 (SMTP) -> ADRP (nome).
"! Regra D6 (Fase 0): escolhe o registo com FLGDEFAULT = 'X'; so se nenhum
"! estiver marcado e que cai para o menor CONSNUMBER. Sem e-mail nao e erro:
"! o utilizador simplesmente nao entra no resultado (o chamador avisa no BAL).
CLASS zcl_porel_mail_resolver DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      "! Candidato de e-mail de um PERSNUMBER (linha de ADR6)
      BEGIN OF ty_addr_cand,
        consnumber TYPE adr6-consnumber,
        flgdefault TYPE adr6-flgdefault,
        smtp_addr  TYPE adr6-smtp_addr,
      END OF ty_addr_cand,
      tt_addr_cand TYPE STANDARD TABLE OF ty_addr_cand WITH DEFAULT KEY.

    "! Resolve os enderecos SMTP dos utilizadores dados.
    "! @parameter it_bnames | Utilizadores SAP a resolver
    "! @parameter rt_mails  | Utilizador -> e-mail + nome (so os que tem e-mail)
    METHODS resolve_emails
      IMPORTING
        it_bnames       TYPE zif_porel_types=>tt_bname
      RETURNING
        VALUE(rt_mails) TYPE zif_porel_types=>tt_resolved_mail.

    "! Escolhe o e-mail de um conjunto de candidatos (D6): FLGDEFAULT = 'X'
    "! primeiro; senao o de menor CONSNUMBER; vazio se nao houver nenhum.
    "! Estatico e publico para teste unitario sem BD.
    "! @parameter it_addrs | Candidatos de um PERSNUMBER
    "! @parameter rv_email | Endereco escolhido (vazio se nenhum)
    CLASS-METHODS pick_email
      IMPORTING
        it_addrs        TYPE tt_addr_cand
      RETURNING
        VALUE(rv_email) TYPE ad_smtpadr.

  PRIVATE SECTION.

    CONSTANTS c_default TYPE adr6-flgdefault VALUE 'X'.

    TYPES:
      BEGIN OF ty_usr,
        bname      TYPE usr21-bname,
        persnumber TYPE usr21-persnumber,
        addrnumber TYPE usr21-addrnumber,
      END OF ty_usr,
      tt_usr TYPE STANDARD TABLE OF ty_usr WITH DEFAULT KEY,

      BEGIN OF ty_adr6,
        addrnumber TYPE adr6-addrnumber,
        persnumber TYPE adr6-persnumber,
        consnumber TYPE adr6-consnumber,
        flgdefault TYPE adr6-flgdefault,
        smtp_addr  TYPE adr6-smtp_addr,
      END OF ty_adr6,
      tt_adr6 TYPE STANDARD TABLE OF ty_adr6 WITH DEFAULT KEY,

      BEGIN OF ty_adrp,
        persnumber TYPE adrp-persnumber,
        name_text  TYPE adrp-name_text,
      END OF ty_adrp,
      tt_adrp TYPE SORTED TABLE OF ty_adrp WITH NON-UNIQUE KEY persnumber.

ENDCLASS.


CLASS zcl_porel_mail_resolver IMPLEMENTATION.

  METHOD resolve_emails.
    IF it_bnames IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_usr TYPE tt_usr.
    SELECT bname, persnumber, addrnumber
      FROM usr21
      FOR ALL ENTRIES IN @it_bnames
      WHERE bname = @it_bnames-table_line
      INTO TABLE @lt_usr.

    " so utilizadores com cadastro de endereco resolvem e-mail
    DATA lt_drv TYPE tt_usr.
    lt_drv = lt_usr.
    DELETE lt_drv WHERE persnumber IS INITIAL.
    IF lt_drv IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_adr6 TYPE tt_adr6.
    SELECT addrnumber, persnumber, consnumber, flgdefault, smtp_addr
      FROM adr6
      FOR ALL ENTRIES IN @lt_drv
      WHERE addrnumber = @lt_drv-addrnumber
        AND persnumber = @lt_drv-persnumber
      INTO TABLE @lt_adr6.

    DATA lt_adrp TYPE tt_adrp.
    SELECT persnumber, name_text
      FROM adrp
      FOR ALL ENTRIES IN @lt_drv
      WHERE persnumber = @lt_drv-persnumber
        AND nation     = @space
      INTO TABLE @lt_adrp.

    DATA lt_cand TYPE tt_addr_cand.
    DATA ls_res  TYPE zif_porel_types=>ty_resolved_mail.
    LOOP AT lt_drv INTO DATA(ls_u).
      CLEAR lt_cand.
      LOOP AT lt_adr6 INTO DATA(ls_a)
           WHERE addrnumber = ls_u-addrnumber
             AND persnumber = ls_u-persnumber.
        APPEND VALUE #( consnumber = ls_a-consnumber
                        flgdefault = ls_a-flgdefault
                        smtp_addr  = ls_a-smtp_addr ) TO lt_cand.
      ENDLOOP.

      DATA(lv_email) = pick_email( lt_cand ).
      IF lv_email IS INITIAL.
        CONTINUE.                           " sem e-mail: nao entra (caller avisa)
      ENDIF.

      CLEAR ls_res.
      ls_res-bname = ls_u-bname.
      ls_res-email = lv_email.
      READ TABLE lt_adrp INTO DATA(ls_p) WITH KEY persnumber = ls_u-persnumber.
      IF sy-subrc = 0.
        ls_res-disp_name = ls_p-name_text.
      ENDIF.
      INSERT ls_res INTO TABLE rt_mails.
    ENDLOOP.
  ENDMETHOD.


  METHOD pick_email.
    DATA lv_min TYPE adr6-consnumber.

    " 1) preferencia: registo marcado como default
    LOOP AT it_addrs INTO DATA(ls) WHERE flgdefault = c_default.
      rv_email = ls-smtp_addr.
      RETURN.
    ENDLOOP.

    " 2) fallback: menor CONSNUMBER
    CLEAR rv_email.
    LOOP AT it_addrs INTO ls.
      IF rv_email IS INITIAL OR ls-consnumber < lv_min.
        lv_min   = ls-consnumber.
        rv_email = ls-smtp_addr.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
