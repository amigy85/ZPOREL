# fase0_descobertas.md — Descobertas da Fase 0

Sistema: **CBD/010** (ECC EHP7, ABAP 7.40) · leitura por MCP `abap-adt` + `abap-crud` (read-only).
Data da recolha: **2026-08-11**. Todos os factos abaixo foram lidos do sistema, não inferidos.

> **Resultado global:** nenhum bloqueador. O desenho da especificação mantém-se válido, com
> **10 divergências** a incorporar antes de escrever código (secção 8) e alguns pontos a validar
> **em PRD** (secção 9). Nota de âmbito: a `ZPOREL_C_RESP` foi **adiada** — a resolução de
> responsáveis assenta na `T16FW` standard (ver resposta ao Amarildo, 2026-08-11).

---

## 0. Notas de acesso MCP (para as próximas sessões)

- `abap-adt`: `GetInterface`/`GetClass`/`GetPackage`/`SearchObject` **funcionam**.
  `GetTable`/`GetStructure`/`GetTypeInfo`/`GetTableContents` **falham** (o serviço ADT DataPreview
  devolve 404 e os endpoints DDL/dataelement não existem para tabelas clássicas).
- `abap-crud`: `runQuery` e `tableContents` **são o caminho fiável** para estrutura + dados de
  tabelas. **JOINs multi-tabela dão "Internal server error"** — fazer SELECTs de tabela única e
  cruzar em memória.
- Estruturas/tipos do dicionário (ex.: `ZEMAIL_S_RECIPIENT`) não se leem por endpoint DDIC; leram-se
  **pela utilização** nas classes consumidoras (`ZCL_ASSIST_NOTIF_BUILDER`, `ZCL_NOTIFICATION_SERVICE`).

---

## 1. Contrato do framework ZEMAIL — CONFIRMADO

Pacote `ZEMAIL` inventariado por `GetPackage`. Assinaturas reais:

### `ZIF_EMAIL_SERVICE~send`
```abap
METHODS send
  IMPORTING
    iv_template_id   TYPE zemail_template_id
    iv_langu         TYPE spras                              " NÃO "iv_language"
    it_recipients    TYPE zemail_t_recipient
    it_values        TYPE zemail_t_placeholder
    it_tables        TYPE zif_email_service=>tt_table_placeholder OPTIONAL
  RETURNING VALUE(rs_result) TYPE zemail_s_send_result
  RAISING  zcx_email.
```
`tt_table_placeholder` = tabela de ( `name` TYPE zemail_placeholder_name, `data` TYPE REF TO data ).

### Estruturas (lidas por utilização)
- **`ZEMAIL_S_RECIPIENT`**: `address` (ad_smtpadr) · `visible_name` · `recipient_type` (zemail_recipient_type).
- **`ZEMAIL_S_PLACEHOLDER`**: `name` (zemail_placeholder_name) · `value` · `format` (zemail_placeholder_format).
- **`ZEMAIL_S_SEND_RESULT`**: `send_id` · `status` (zemail_estado_envio) · `message`.

### `ZIF_EMAIL_CONST` (constantes a usar — nunca literais)
- `recipient_type`: `to_addr='TO'`, `cc='CC'`, `bcc='BCC'`.
- `placeholder_format`: `plain=' '` (espaço!), `date='D'`, `currency='C'`, `html='H'`.
- `send_status`: `success='S'`, `error='E'`.
- `config_param`: `SENDER_ADDRESS`, `FALLBACK_LANGU`, `STRICT_MODE`, `BAL_OBJECT`, `BAL_SUBOBJECT`, `PA0105_SUBTYPE`.

### Factory
`ZCL_EMAIL_FACTORY=>create_notification_service( [it_images] ) RETURNING zif_email_service`
(compõe provider DB + placeholder + engine + renderer + sender BCS + logger BAL a partir de
`ZEMAIL_CONFIG`). Também existe `create_sender( )`. **O fallback do processor é
`create_notification_service( )`** — não há método `create` genérico.

### `ZIF_LOGGER`
`info(iv_text)` · `warning(iv_text)` · `error(iv_text OPTIONAL, ix_exc OPTIONAL)` · `save( )`.
Texto **livre** (string), sem integração com classe de mensagens. O objecto/sub-objecto BAL é
fixado no construtor de `ZCL_LOGGER_BAL( iv_object, iv_subobject, iv_extnumber )` — **não** é por
mensagem (ver divergência D7).

---

## 2. Render de tabela HTML — DECISÃO TÉCNICA (importante)

Há **dois** mecanismos em `ZCL_PLACEHOLDER_SERVICE`:

1. `replace_table` → placeholder `{{TAB:NAME}}`, gera `<table>` por RTTI a partir de `it_tables`.
   Escapa os **valores** das células, não as tags. **Mas produz tabela sem estilos** (`<table><tr><th>`),
   inútil para Outlook.
2. `replace` → placeholder `{{NAME}}`, escapa por omissão **excepto** quando `format='H'` (html),
   caso em que injecta o valor **em bruto**.

**A classe irmã `ZCL_ASSIST_NOTIF_BUILDER` (que também consome o ZEMAIL) NÃO usa `{{TAB:}}`.**
Constrói as linhas `<tr>` com estilos inline em ABAP e passa-as como placeholder escalar
`format = html`. É o padrão provado para e-mail estilado compatível com Outlook.
→ **O `ZCL_POREL_NOTIF_BUILDER` deve seguir o mesmo padrão**: shell `<table>` estático estilado no
template + `{{LINHAS_POS}}` com `format='H'`; construir as `<tr>` em ABAP.

**Lacuna do framework a contornar:** `format='C'` (currency) **nunca** recebe `iv_waers` (o
`ZCL_TEMPLATE_ENGINE->build` não o reencaminha) e `format='D'` (date) usa o `SY-DATFM` de quem corre
o job. → **Pré-formatar valores e datas em ABAP e passar como `plain`** (foi o que o ZASSIST fez).

---

## 3. Tabelas de estratégia de liberação — ESTRUTURA REAL

| Tabela | Campos reais | Papel |
|---|---|---|
| `T16FS` | MANDT, FRGGR, FRGSX, **FRGC1..FRGC8**, FRGEX | posição → código. **Só códigos, sem pré-requisitos.** |
| `T16FV` | MANDT, FRGGR, FRGSX, FRGCO, **FRGA1..FRGA8** | **fonte dos pré-requisitos** (ver 4). |
| `T16FC` | MANDT, FRGGR, FRGCO, **FRGWF** | indicador de workflow. `FRGWF='1'` em todos os códigos PO. |
| `T16FG` | MANDT, FRGGR, **FRGOT**, FRGFG, FRGKL | `FRGOT='2'`=**PO**, `FRGOT='1'`=Requisição. |
| `T16FW` | MANDT, FRGGR, FRGCO, WERKS, **OTYPE, OBJID** | **atribuição de agente** ao código (ver 5). |
| `T16FD` | MANDT, SPRAS, FRGGR, FRGCO, **FRGCT** | **texto do CÓDIGO** (ex.: "Chefe Depart.DGO-POS", "Adm.Pelouro DEM"). É a descrição da "Etapa" no e-mail. Há entradas `SPRAS='P'`. |
| `T16FT` | MANDT, SPRAS, FRGGR, FRGSX, **FRGXT** | **texto da ESTRATÉGIA** (ex.: "Req.Cons.DEM-A"). |
| `T16FE` | MANDT, SPRAS, FRGKE, FRGET | texto do **indicador** de liberação ("Aprovado"/"Bloqueado") — não usado. |

> ⚠️ A especificação tinha `T16FD`/`T16FT` **trocados**: o texto do **código** está em `T16FD`
> (FRGCT), o texto da **estratégia** está em `T16FT` (FRGXT). Ver D10.

**Grupos de liberação (T16FG):**
- **PO (`FRGOT='2'`, classe `ZLIB_PED_COMPRAS`):** KC, KI, KS, KT, **PC, PD, PI, PK, PS, PT**.
- **Requisição (`FRGOT='1'`, classe `ZLIB_REQ_COMPRAS`):** RC, RI, RS, RT — **fora de âmbito**.
- POs pendentes concentram-se em **PC, PI, PS, PT**. O `SELECT` sobre `EKKO WHERE BSTYP='F'` já
  exclui requisições por natureza (são `EBAN`), logo o reader não precisa de filtrar grupos.

---

## 4. Regra de liberação — VALIDADA contra dados reais

`EKKO-FRGZU` (CHAR8) posicional confirmado: posição *i* = `'X'` → código `FRGC(i)` de `T16FS` já
libertou. `EKKO-FRGRL`: **`'X'` = pendente** (358 POs), `''` = concluída (24 957). Campo limpo,
sem lixo — o filtro `FRGRL='X'` é válido.

**Normalização de pré-requisitos a partir de `T16FV`:** para o código `FRGCO`, `FRGAn='X'` marca a
**própria** posição e `FRGAn='+'` marca uma posição **exigida antes**. A máscara CHAR8 que o
`ZCL_POREL_STRATEGY` recebe é: `mask+(j-1)(1)='X'` sse `FRGAj='+'`.

**Exemplo real — estratégia `PC/B3`** (`T16FS`: FRGC1=`RD`, FRGC2=`SJ`; `T16FV`: RD→pos1 sem
pré-requisito, SJ→pos2 exige pos1):
- PO `0004182120`, `FRGZU=''` → RD accionável; SJ bloqueado por RD → **só RD é notificado**.
- PO `0004201761`, `FRGZU='X'` → RD já libertou; pré-requisito de SJ cumprido → **SJ é notificado**.

Todas as estratégias PO observadas são **sequenciais** (posição *k* exige 1..k-1). Como o `T16FV`
está **povoado** para todas as estratégias pendentes, o "modo por omissão" `P_PARMOD` (S/P) é uma
salvaguarda que na prática nunca é accionada — mas mantém-se.

---

## 5. Responsáveis e e-mail — ADR-003 resolvido + ACHADO CRÍTICO

**`T16FW` é a tabela de atribuição de agentes** (não estados de liberação). Para os grupos PO todos
os agentes são `OTYPE='US'` (utilizador SAP) com `WERKS` vazio (independente de centro) → **não é
preciso expansão organizacional** (posição/unidade). `FRGWF='1'` confirma workflow activo. A cadeia
do ADR-003 (T16FW primária + `ZPOREL_C_RESP` override/adicional) é viável.

**Resolução de e-mail — DUAS correcções à especificação (§4.4):**

1. `USR21` (BNAME → PERSNUMBER + ADDRNUMBER) → `ADR6`. **Usar o registo com `FLGDEFAULT='X'`, NÃO o
   de menor `CONSNUMBER`.** Exemplo real (utilizador funcional `DGO_LS`, persnumber 0000092887):
   | CONSNUMBER | FLGDEFAULT | SMTP |
   |---|---|---|
   | 1 | (vazio) | Manuel.Balawe@hcb.co.mz |
   | 2 | **X** | **luis.simone@hcb.co.mz** ← correcto |
   | 3 | (vazio) | Joao.Chambene@hcb.co.mz |
   O menor `CONSNUMBER` daria o e-mail **errado** (titular anterior). Estes utilizadores são contas
   **funcionais** partilhadas (vários titulares sucessivos); `FLGDEFAULT` aponta o titular actual.

2. **Só ~27% das contas de aprovador têm e-mail resolvível.** Análise da **população completa**: os
   grupos PO têm **52** utilizadores aprovadores distintos em `T16FW`. Destes, apenas **14 têm SMTP
   em `ADR6`**; 37 têm `PERSNUMBER` mas **nenhum** registo `ADR6`, e 1 (`CA_DIC`) nem sequer existe
   em `USR21`. Os 14 com e-mail são contas pessoais reais (ex.: `DSA_AJ`→amarildo.assane,
   `DGO_LS`→luis.simone, `DST_AD`→Almiro.Marques); a maioria das contas **funcionais** (`CA_*`,
   grande parte de `DAF_*`/`DHB_*`/`DSG_*`) não têm e-mail povoado **neste sistema**.
   ⚠️ **CBD/010 é sistema de teste/QA — este número NÃO é indicativo de PRD**, onde o cadastro de
   e-mails é mantido de forma diferente. Não tirar daqui conclusões de go-live. O que interessa para
   o desenho é técnico e independente do ambiente: (a) resolver por `FLGDEFAULT='X'`; (b) "sem e-mail
   → aviso no BAL, sem dump", já previsto. A cobertura real confirma-se **em PRD**, não aqui.

---

## 6. Padrão de código a replicar

`ZCL_ASSIST_NOTIF_BUILDER` (pacote ZEMAIL, consumidor irmão) é o **molde** para o
`ZCL_POREL_NOTIF_BUILDER` e para o `ZCL_POREL_PROCESSOR`:
- Injecção de `zif_email_service` no construtor + duplos nos testes.
- `it_recipients = VALUE #( ( address=… visible_name=… recipient_type=zif_email_const=>recipient_type-to_addr ) )`.
- `it_values` com `format` explícito; linhas de tabela pré-construídas com `format=html`.
- Cada destinatário no seu `TRY/CATCH zcx_email` — uma falha não interrompe os restantes.

---

## 7. Autorização (§7 da espec)

Não há ferramenta MCP para ler objectos de autorização; os campos foram **confirmados pelo Amarildo**
em SU21/PFCG:

| Objecto | Campos | Uso no `ZRP_MM_PO_PEND_RELEASE` |
|---|---|---|
| `M_BEST_EKO` | **ACTVT**, **EKORG** | Gate principal (espec §7): `AUTHORITY-CHECK OBJECT 'M_BEST_EKO' ID 'ACTVT' FIELD '03' ID 'EKORG' FIELD <ekorg>` por organização de compras distinta. Sem autorização numa EKORG → excluir essas POs e avisar, sem abortar. |
| `M_EINK_FRG` | **FRGGR**, **FRGCO** | Autorização de *liberação* (grupo/código). Opcional — só se quisermos restringir o diagnóstico às etapas que o utilizador em diálogo pode libertar. Não necessário para o job em background (utilizador técnico). |

O ZASSIST (referência) usa `AUTHORITY-CHECK OBJECT 'P_ORGIN'` (HR) e regista que os campos
AUTHC/ACTVT tiveram de ser ajustados no sistema real — mesma lição: validar campos de autorização
sempre no sistema, nunca assumir.

---

## 8. Divergências face à especificação (INCORPORAR antes de codificar)

| # | Local na espec | O que muda |
|---|---|---|
| D1 | §5.1 | Parâmetro é `iv_langu` (não `iv_language`). `it_tables` é `tt_table_placeholder` (name+data ref), não um `ZEMAIL_T_*`. Excepção é `ZCX_EMAIL`. |
| D2 | §5.1 | Factory é `ZCL_EMAIL_FACTORY=>create_notification_service( )`. |
| D3 | §5.2 | Tabela do e-mail: usar placeholder escalar `format='H'` com `<tr>` construídas em ABAP (padrão ZASSIST), **não** `{{TABELA_POS}}`+`it_tables`. `placeholder_format-plain` é `' '`. |
| D4 | §5.2 / §3 | `format` currency/date do framework está furado → **pré-formatar em ABAP, passar `plain`**. |
| D5 | §3.3 | Pré-requisitos vêm de **`T16FV` (FRGA1..8)**, não de `T16FS`. `T16FS` só tem FRGC1..8+FRGEX. |
| D6 | §4.4 | E-mail = `ADR6` com **`FLGDEFAULT='X'`**, não menor `CONSNUMBER`. |
| D7 | §8 | `ZIF_LOGGER` é texto livre; objecto/sub-objecto BAL fixado na construção. Para sub-objectos SELECT/RESOLVE/NOTIFY → **instanciar um logger por sub-objecto** (ou usar um só). Formatar os textos da classe `ZPOREL` para string antes de logar. |
| D8 | §3.1 | Grupos PO são PC/PI/PS/PT… (`FRGOT='2'`); RC/RI/RT são requisições. Filtrar por `BSTYP='F'` já basta. |
| D9 | §4.2 | Agentes são todos `US` → expansão organizacional (HRP1001/PA0105) **não necessária** nesta instalação. `ZEMAIL_CONFIG-PA0105_SUBTYPE` existe se vier a ser preciso. |
| D10 | §3.3 tabela | Textos: `T16FD`=texto do **código** (FRGCT) e `T16FT`=texto da **estratégia** (FRGXT) — a espec trocou-os. Descrição da "Etapa" no e-mail vem de `T16FD-FRGCT` (SPRAS='P'). |

---

## 9. Pontos para decisão do negócio (ANTES do go-live)

1. **Confirmar a cobertura de e-mail em PRD.** Em CBD/010 (teste) só 14/52 aprovadores têm SMTP, mas
   **isso não reflecte PRD**. Antes do go-live, validar em PRD que os aprovadores têm e-mail em
   SU01/ADR6. Onde faltar, o desenho degrada com aviso (não falha). Um mecanismo de override
   (tabela Z de excepções) pode ser acrescentado **se e quando** for preciso — ver nota de âmbito
   sobre a `ZPOREL_C_RESP` (adiada; a resolução usa a `T16FW` standard).
2. **Contas funcionais partilhadas** (ex.: `DGO_LS` com 3 titulares históricos): notificar o e-mail
   `FLGDEFAULT` (titular actual) — assumido — ou outro critério?

---

## 10. Itens da checklist da Fase 0 não fechados por MCP

- **Comparação com ME29N** (3 POs reais): exige SAP GUI → a validar pelo Amarildo. O algoritmo já
  foi validado contra `FRGZU`/`T16FS`/`T16FV` reais (secção 4).

_(Tabelas de texto e objectos de autorização ficaram fechados — ver secções 3, 7 e D10. Fica em
aberto apenas a comparação visual com a ME29N, que exige SAP GUI.)_

---

## Gate da Fase 0

Desenho confirmado. Antes da Fase 1: rever as divergências D1–D9 e decidir os pontos de negócio 1–2.
**Nenhum código deve ser escrito até esta revisão.**
