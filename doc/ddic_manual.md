# ddic_manual.md — Guião dos objectos manuais (SE11 / SE91 / SLG0)

Objectos criados **à mão** no CBD/010 (não geráveis por abapGit a partir deste repositório — ver
`CLAUDE.md` §3). Criar **por esta ordem** (dependências de baixo para cima). Todos no pacote
**`ZPOREL`**, língua principal **E (inglês)**, ordem de transporte de workbench própria.

> Referências: especificação §6 e `fase0_descobertas.md` (correcções D1–D10).
> Onde um tipo standard serve, **reutiliza-se** — só se criam objectos Z sem equivalente.

> **Âmbito (decisão 2026-08-11):** a `ZPOREL_C_RESP` foi **adiada**. A resolução de responsáveis
> assenta na **`T16FW` standard** (todos os agentes dos grupos PO são utilizadores `US` — ver
> `fase0` §5). A camada de override/CC/substituição (tabela Z + SM30 + domínios `ZPOREL_SOURCE`,
> `ZPOREL_RECIP_TYPE`, `ZPOREL_DISP_NAME`) **não** faz parte deste build; entra depois, se e quando
> houver necessidade real, através de um segundo provider de `ZIF_POREL_RESP_PROV`, sem rework.

---

## 1. Domínio (SE11 → Domínio)

| Domínio | Tipo | Comp. | Valores fixos | Uso |
|---|---|---|---|---|
| `ZPOREL_RUN_STATUS` | CHAR | 1 | `S` = Sucesso · `E` = Erro · `K` = Saltado (idempotência) | estado do envio em `ZPOREL_RUN` |

> Os valores alinham com `zif_email_const=>send_status` (`S`/`E`) mais `K` local.

---

## 2. Elementos de dados (SE11 → Elemento de dados)

| Data element | Domínio | Texto curto |
|---|---|---|
| `ZPOREL_RUN_STATUS` | `ZPOREL_RUN_STATUS` | Estado do envio (S/E/K) |
| `ZPOREL_ISO_WEEK` | `CHAR8` (standard) | Semana ISO (ex.: `2026W33`) |

Restantes campos reutilizam data elements **standard** (secção 3) — não criar Z para eles.

---

## 3. Tabela `ZPOREL_RUN` — controlo de idempotência / log de execução (SE11 → Tabela)

Regista cada envio por (semana ISO, destinatário). Ver especificação §6 e ADR-005.

| Campo | Data element / Tipo | Chave | Notas |
|---|---|:--:|---|
| `MANDT` | `MANDT` | ✓ | Mandante |
| `RUN_ID` | `SYSUUID_C32` | ✓ | Identificador da execução |
| `ISO_WEEK` | `ZPOREL_ISO_WEEK` | | Semana ISO (ex.: `2026W33`) |
| `EMAIL` | `AD_SMTPADR` | | Destinatário |
| `RUN_DATE` | `DATUM` | | Data do envio |
| `RUN_TIME` | `UZEIT` | | Hora do envio |
| `PO_COUNT` | `INT4` | | Nº de POs incluídas |
| `SEND_ID` | `CHAR32` (tipo integrado) | | ID devolvido pelo `ZEMAIL` (`ZEMAIL_S_SEND_RESULT-send_id`) |
| `STATUS` | `ZPOREL_RUN_STATUS` | | `S`/`E`/`K` |
| `MESSAGE` | `CHAR255` (tipo integrado) | | Texto de erro, se houver |
| `TEST_MODE` | `XFELD` | | Execução em modo teste |

**Índice secundário `WK`:** campos `ISO_WEEK` + `EMAIL` — é a leitura do controlo de idempotência.
**Definições técnicas (aba Utils. → Def. técnicas):** classe de entrega **`A`** (dados de aplicação),
classe de dados `APPL1`, categoria de tamanho `1`. **Sem** manutenção SM30 (é log).

> Registos com `TEST_MODE = 'X'` **não** contam para o controlo semanal (ver especificação §7/§10).
> Confirmar o tipo real de `ZEMAIL_S_SEND_RESULT-send_id`; se não for CHAR32, ajustar `SEND_ID`.

---

## 4. Classe de mensagens `ZPOREL` (SE91)

Criar a classe `ZPOREL` e as mensagens abaixo. Usadas no ecrã de selecção e para **formatar texto
de log** (o `ZIF_LOGGER` do ZEMAIL recebe string — ver D7 — logo usa-se `MESSAGE … INTO lv_text`).

| Nº | Texto |
|---|---|
| 001 | Estratégia de liberação &1/&2 não encontrada no customizing |
| 002 | Código de liberação &1 sem responsável configurado |
| 003 | Utilizador &1 sem endereço de e-mail |
| 004 | &1 POs pendentes distribuídas por &2 destinatários |
| 005 | E-mail enviado a &1 com &2 documento(s) |
| 006 | Falha no envio para &1: &2 |
| 007 | Notificação já enviada a &1 na semana &2 — ignorada |
| 008 | Modo teste activo: todos os e-mails redireccionados para &1 |
| 009 | Nenhuma PO pendente encontrada com os filtros indicados |
| 010 | Pré-requisitos circulares detectados na estratégia &1/&2 |

---

## 5. Objecto de log de aplicação BAL `ZPOREL` (SLG0)

Transacção **SLG0** → novo objecto:
- Objecto: **`ZPOREL`** — "Notificação de POs pendentes de liberação".
- Sub-objectos:
  | Sub-objecto | Uso |
  |---|---|
  | `SELECT` | selecção e filtragem das POs |
  | `RESOLVE` | resolução de responsáveis e e-mails |
  | `NOTIFY` | envio e resultado |

> **D7 (Fase 0):** o `ZIF_LOGGER`/`ZCL_LOGGER_BAL` fixa objecto **e** sub-objecto na construção. Para
> escrever nos três sub-objectos, o código instancia **um logger por sub-objecto** (ou um só). Criar
> na mesma os três sub-objectos aqui, para manter a rastreabilidade da especificação §8.

---

## 6. Checklist de entrega (Fase 1 gate)

- [ ] Domínio `ZPOREL_RUN_STATUS` activo
- [ ] Data elements `ZPOREL_RUN_STATUS` e `ZPOREL_ISO_WEEK` activos
- [ ] `ZPOREL_RUN` activa com índice secundário `WK`
- [ ] Classe de mensagens `ZPOREL` (001–010)
- [ ] Objecto BAL `ZPOREL` + sub-objectos `SELECT`/`RESOLVE`/`NOTIFY`
- [ ] Tudo numa ordem de transporte de workbench própria

---

## Apêndice — Agendamento (executar só na Fase 9, após transporte)

Não faz parte do gate da Fase 1; documentado aqui para ficar tudo num sítio.

- **Variante `SEMANAL`** do report `ZRP_MM_PO_PEND_RELEASE`: `p_send='X'`, `p_test=' '`,
  `p_force=' '`, `p_langu='P'`, `p_parmod='S'`, `p_mindia=0`, filtros de documento vazios.
- **Job SM36 `ZPOREL_NOTIF_SEMANAL`:** passo único = report + variante `SEMANAL`; periodicidade
  **semanal, segunda-feira 07:00**; utilizador técnico de batch com autorização de leitura de
  compras (`M_BEST_EKO`, ACTVT `03`) em todas as EKORG.
