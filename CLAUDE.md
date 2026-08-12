# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Contexto permanente do repositório ZPOREL

Lê este ficheiro no início de cada sessão. Ele contém o que é **sempre verdade** neste projecto.
O que construir, por que ordem e com que critérios de aceitação está em
**`doc/ESPEC_ZPOREL_NOTIF_SEMANAL.md`** — a especificação é a fonte de verdade funcional e não
deve ser duplicada aqui.

---

## 0. Estado do repositório e comandos

Estado: **Fases 0–6 concluídas** — a aguardar o gate da Fase 6 (pull + ABAP Unit + preview do template).
Nota de âmbito: **"dias parada" (§3.5) fora de âmbito**; **`ZPOREL_C_RESP` adiada** (só T16FW).
Convenção: tipos nomeados nas assinaturas (nunca `TYPE c LENGTH n`); ficheiros **sem BOM**.
- `doc/ESPEC_ZPOREL_NOTIF_SEMANAL.md` — especificação (fonte de verdade).
- `doc/fase0_descobertas.md` — descobertas reais do CBD/010 + **divergências D1–D10** (ler antes de codificar).
- `doc/ddic_manual.md` — guião dos objectos DDIC/SE91/SLG0 (criados no CBD, package `$ZPOREL`).
- `.abapgit.xml` (raiz) + `src/package.devc.xml` — repositório abapGit inicializado (`check` OK).
- Fase 2: `src/zif_porel_types`, `zcx_porel`, `zif_porel_po_reader`, `zif_porel_resp_prov`.
- Fase 3: `src/zcl_porel_strategy` + testes (10 da §9) — **verdes**, activada.
- Fase 4: `src/zcl_porel_po_reader` + testes (4, `normalize_prereq`) — verde, activada.
- Fase 5: `src/zcl_porel_mail_resolver` (+4 testes de `pick_email`, D6) e `src/zcl_porel_resp_prov_t16fw`.
- Fase 6: `src/zcl_porel_notif_builder` (+4 testes) e os templates `doc/zhcb_master_po.html` (master
  próprio) + `doc/zpo_pend_release.html` (body). Carregam-se à mão no `ZEMAIL_TMPL_MAINT`.

**Gate da Fase 6 (a decorrer):** o Amarildo faz pull (inclui `zif_porel_types` — tipos do builder),
activa `zcl_porel_notif_builder`, corre a ABAP Unit (4 testes) **e** carrega/pré-visualiza os 2
templates. Só depois avança a **Fase 7** (`ZCL_POREL_RUN_CONTROL` + `ZCL_POREL_PROCESSOR`). Não encadear fases.

Não há toolchain de build/lint/test local: **compilação, activação e ABAP Unit correm dentro do
CBD/010**, não aqui (ver secção 2). A única verificação local é o metafile do abapGit:

```
abapgit_meta.py check --root .
```

Corre-a no fim de cada fase, depois de gerar/alterar qualquer objecto ABAP (ver secção 4).

---

## 1. O projecto em três linhas

`ZPOREL` é um relatório ABAP executado semanalmente em background que identifica todos os
Pedidos de Compra pendentes de liberação e envia a cada responsável, por e-mail HTML, a lista
das POs paradas **na etapa dele**. O envio é feito através do framework corporativo `ZEMAIL`.

Cliente: HCB — Hidroeléctrica de Cahora Bassa. Sistema: **CBD/010** (ECC EHP7, ABAP 7.40).

---

## 2. Modelo de trabalho — Git-first, MCP read-only

**Os servidores MCP/ADT são estritamente de leitura.** Nada é escrito, activado ou transportado
directamente no SAP a partir daqui.

O que os MCP **podem** fazer: ler definições de classes, interfaces, tabelas DDIC e código
existente; inspeccionar customizing; confirmar assinaturas de métodos do `ZEMAIL`.

O que **não** podem: criar objectos, activar, gravar, executar transacções.

Fluxo real de cada objecto:

```
Claude Code escreve ficheiros no repositório
        -> commit + push
        -> Amarildo faz pull no abapGit dentro do CBD/010
        -> activa e testa no SAP
        -> reporta o resultado na sessão seguinte
```

Consequência prática: **nunca digas "criei a classe no sistema"**. Criaste ficheiros. A
activação é manual e pode falhar por sintaxe que o teu contexto não apanha — assume isso e
escreve código conservador.

---

## 3. Objectos manuais (não geráveis por abapGit aqui)

Estes são criados à mão por mim, em SE11/SE91/SLG0, a partir do guião em `doc/ddic_manual.md`.
Não tentes gerar XML abapGit para eles:

- Tabela transparente `ZPOREL_RUN` (idempotência), respectivo domínio e elementos de dados
- Classe de mensagens `ZPOREL` (SE91)
- Objecto de log BAL `ZPOREL` e sub-objectos (SLG0)

> **Adiado (decisão 2026-08-11):** `ZPOREL_C_RESP` (+ view SM30 e domínios `ZPOREL_SOURCE`/
> `ZPOREL_RECIP_TYPE`/`ZPOREL_DISP_NAME`) **saiu do âmbito**. Responsáveis vêm da `T16FW` standard.
> A camada de override/CC entra depois, se preciso, como 2º provider de `ZIF_POREL_RESP_PROV`.

Se precisares de um destes objectos e ele ainda não existir no CBD, **pára e avisa** — não
contornes com uma tabela interna nem com literais.

---

## 4. Skill obrigatória: `abapgit-metafiles`

Usa-a **sempre** que criares qualquer objecto ABAP no repositório, mesmo que o pedido seja só
"cria uma classe". Um `.abap` sozinho é invisível para o abapGit.

Regras que se aplicam a todos os ficheiros: UTF-8 **SEM BOM**, fim de linha **LF**, quebra de
linha final, nomes em minúsculas no padrão `<nome>.<tipo>.<ext>`, todos os ficheiros de um
objecto na mesma pasta.

> ⚠️ **Correcção ao skill (2026-08-11):** o abapGit do CBD/010 **rejeita BOM** no source ABAP
> (erro `The statement ﻿ is unexpected` / `INTF error while scanning source`). O
> `abapgit_meta.py` gera **com** BOM — por isso, depois de gerar/`check --fix`, **remover o BOM**
> de tudo em `src/` e do `.abapgit.xml` antes do commit. A regra "sem BOM = erro" do `check` **não
> se aplica** aqui; usa o `check` só para EOL/pares metafile↔código/packages, ignora o aviso de BOM.

Configuração deste repositório: `STARTING_FOLDER = /src/`, `FOLDER_LOGIC = PREFIX`,
`MASTER_LANGUAGE = E`.

---

## 5. Regra de ouro: o `ZEMAIL` não se toca

`ZPOREL` é **consumidor** do framework. A dependência é unidireccional e não negociável.

- Nunca alteres nada no pacote `ZEMAIL`, nem "só um campinho".
- Se a API do `ZEMAIL` não servir para o que é preciso, **pára e diz-me** — a decisão de
  estender o framework é minha, e afecta o `ZASSIST` que também o consome.
- Adapta o código de `ZPOREL` à assinatura real de `ZIF_EMAIL_SERVICE`, lida por ADT. Se a
  assinatura divergir da que está na especificação, é a especificação que está desactualizada.
- O `ZEMAIL` não pode ganhar qualquer conhecimento sobre Pedidos de Compra. Nem uma constante.

---

## 6. Convenções ABAP

**Nomenclatura.** Objectos, métodos, parâmetros e variáveis em **inglês**. Comentários, textos
de selecção, mensagens e conteúdo de e-mail em **português (variante europeia)**.

Prefixos: `zcl_porel_*`, `zif_porel_*`, `zcx_porel*`, report `zrp_mm_po_pend_release`.
Parâmetros: `iv_`/`is_`/`it_`/`io_`, `ev_`/`es_`/`et_`, `rv_`/`rs_`/`rt_`, locais `lv_`/`ls_`/`lt_`/`lo_`.

**Nível de linguagem: 7.40.** Podes usar `VALUE`, `FOR`, `REDUCE`, `CORRESPONDING`, `NEW`,
`COND`, `SWITCH`, string templates, SQL com `@` e declarações inline. **Não** uses sintaxe
7.50+ sem confirmar que compila no CBD.

**Armadilhas conhecidas deste sistema** (já custaram tempo antes — não repitas):

- Declaração inline `DATA(...)` **não é permitida** no adjunto `MESSAGE` das excepções de
  `CALL FUNCTION`. Declara as variáveis antes.
- Estruturas DDIC não têm representação em DDL source no 7.40 — por isso os tipos de trabalho
  vivem em `ZIF_POREL_TYPES`, não no dicionário.
- O placeholder de tabela do `ZEMAIL` **não pode** passar por `cl_http_utility=>escape_html`,
  senão as tags `<tr>`/`<td>` chegam ao e-mail como texto literal.

**Performance — requisito, não preferência.** Em PRD há milhares de POs abertas.

- Zero `SELECT` dentro de `LOOP`. Todas as leituras em massa, antes do processamento.
- Customizing (`T16F*`) e responsáveis lidos uma vez para tabelas `HASHED`, com a chave certa.
- `SELECT` sempre com lista explícita de campos. Nunca `SELECT *`.
- `FOR ALL ENTRIES` sempre com verificação de tabela-base não vazia.

**Clean ABAP.** Métodos curtos com uma responsabilidade. Nomes por intenção. `RETURNING` quando
há um só resultado. Excepções de classe com `IF_T100_MESSAGE`, nunca `MESSAGE ... RAISING` solto.
Sem variáveis globais no report: ele só monta o ecrã de selecção e delega. ABAP Doc em todos os
métodos públicos e interfaces. Textos sempre pela classe de mensagens `ZPOREL`, nunca literais.

---

## 7. Arquitectura — a regra da dependência

```
Apresentação  ->  Aplicação  ->  Domínio  <-  Infra-estrutura
```

As setas apontam sempre para dentro. Em concreto:

- `ZCL_POREL_STRATEGY` é **lógica pura**: sem `SELECT`, sem chamadas a função, sem `sy-datum`.
  Recebe tudo por parâmetro. É a única forma de a testar a sério.
- Toda a leitura de base de dados está atrás de `ZIF_POREL_PO_READER` e `ZIF_POREL_RESP_PROV`.
- Dependências injectadas no construtor, com `OPTIONAL` e instanciação por omissão quando vêm
  iniciais. Isto mantém o report simples e os testes isolados.
- O processor não conhece implementações concretas, só interfaces.

---

## 8. Testes

Toda a classe com lógica leva `.clas.testclasses.abap`. Sem excepções.

- Testes **nunca** acedem à base de dados. Usa duplos que implementam as interfaces.
- `ZCL_POREL_STRATEGY` exige cobertura total de ramos — é a regra de negócio crítica.
- Uma fase não fecha com testes em falta ou vermelhos. Não avances "para voltar depois".

---

## 9. Como trabalhar as fases

A especificação define fases com **gates**. Em cada gate: pára, resume o que foi feito, lista o
que precisa de ser criado ou validado por mim no SAP, e espera confirmação. Não encadeies fases.

**Nunca inventes campos DDIC nem assinaturas de métodos.** Se não conseguiste ler a definição
real, diz que não conseguiste e pergunta. Um campo inventado sobrevive a três fases e rebenta
na activação.

Pontos ainda por confirmar (ver Fase 0 da especificação): estrutura real de `T16FS` e onde
vivem os pré-requisitos, conteúdo real de `T16FW`, assinatura de `ZIF_EMAIL_SERVICE`,
comportamento de `EKKO-FRGRL` no CBD.

---

## 10. Glossário mínimo

| Termo | Significado |
|---|---|
| PO | Pedido de Compra (`EKKO`/`EKPO`, `BSTYP = 'F'`) |
| Grupo de liberação | `FRGGR` — agrupa estratégias |
| Estratégia de liberação | `FRGSX` — define a sequência de códigos que têm de libertar |
| Código de liberação | `FRGCO` — uma etapa de aprovação, associada a um responsável |
| `FRGZU` | `CHAR 8` posicional: `X` na posição *i* = código *i* já libertou |
| `FRGRL` | Liberação ainda não concluída |
| Etapa accionável | Código por libertar **cujos pré-requisitos já estão cumpridos** |
| BAL / SLG1 | Log de aplicação do SAP, onde fica o rasto de cada execução |
