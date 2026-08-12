"! <p class="shorttext synchronized">ZPOREL - idempotencia via ZPOREL_RUN</p>
"! Implementa ZIF_POREL_RUN_CONTROL sobre a tabela ZPOREL_RUN. Registos em modo
"! teste (TEST_MODE = 'X') nao contam para o controlo semanal. Leitor fino de BD:
"! validado por execucao (a logica de decisao esta e testada no processor).
CLASS zcl_porel_run_control DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_porel_run_control.

  PRIVATE SECTION.
    CONSTANTS c_status_success TYPE c LENGTH 1 VALUE 'S'.

ENDCLASS.


CLASS zcl_porel_run_control IMPLEMENTATION.

  METHOD zif_porel_run_control~already_sent.
    SELECT SINGLE @abap_true
      FROM zporel_run
      WHERE iso_week  = @iv_iso_week
        AND email     = @iv_email
        AND test_mode = @space
        AND status    = @c_status_success
      INTO @DATA(lv_found).
    rv_yes = lv_found.
  ENDMETHOD.


  METHOD zif_porel_run_control~record.
    DATA ls_run TYPE zporel_run.

    ls_run-run_id    = cl_system_uuid=>create_uuid_c32_static( ).
    ls_run-iso_week  = iv_iso_week.
    ls_run-email     = iv_email.
    ls_run-run_date  = sy-datum.
    ls_run-run_time  = sy-uzeit.
    ls_run-po_count  = iv_po_count.
    ls_run-status    = iv_status.
    ls_run-send_id   = iv_send_id.
    ls_run-message   = iv_message.
    ls_run-test_mode = iv_test_mode.

    INSERT zporel_run FROM @ls_run.
  ENDMETHOD.

ENDCLASS.
