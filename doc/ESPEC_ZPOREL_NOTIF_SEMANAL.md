# ZPOREL — Notificação Semanal de POs Pendentes de Liberação

**Especificação de implementação para Claude Code**
Sistema alvo: SAP ECC EHP7 / ABAP 7.40 · CBD/010 · HCB
Framework de e-mail consumido: pacote `ZEMAIL`
Versão do documento: 1.0

---

## 0. Como usar este documento

Este ficheiro é a fonte de verdade da implementação. Trabalha por fases (secção 12), uma de cada vez, e **pára em cada gate** para confirmação antes de avançar.

Regras permanentes desta sessão:

1. **Os servidores MCP/ADT são read-only.** Nada é escrito directamente no SAP. Todo o código é escrito como ficheiros no repositório abapGit e importado manualmente para CBD/010 via pull.
2. **Usa sempre a skill `abapgit-metafiles`** ao criar qualquer objecto ABAP no repositório. Cada objecto entrega o conjunto completo (`.abap` + `.clas.xml`/`.intf.xml`/`.prog.xml`), na mesma pasta, UTF-8 com BOM e LF. Corre `check` no fim de cada fase.
3. **Fase 0 é obrigatória e não é opcional.** Vários nomes de tabela/campo e a assinatura exacta da API `ZEMAIL` estão marcados neste documento como *a confirmar*. Confirma-os por leitura no sistema (ADT/MCP ou SE11) antes de escrever código que dependa deles. Não inventes campos DDIC.
4. **Clean ABAP** e restrições da 7.40 (secção 11).
5. Comentários, textos de selecção, mensagens e conteúdo de e-mail em **português**. Nomes de objectos, métodos e variáveis em **inglês**.

---

## 1. Objectivo de negócio

Todas as segundas-feiras de manhã, cada responsável por uma etapa de liberação de Pedidos de Compra (PO) recebe um único e-mail HTML com a lista das POs que estão **pendentes de aprovação na etapa dele e apenas nessa etapa** — ou seja, POs em que o código de liberação atribuído a esse responsável ainda não foi executado **e** cujos pré-requisitos de liberação já estão cumpridos (a PO está de facto à espera dele, não à espera de alguém anterior na cadeia).

Ganhos esperados: redução do tempo médio de aprovação, eliminação da consulta manual em ME28/ME29N e visibilidade sobre POs paradas há semanas.

### O que está dentro do âmbito

- Documentos de compra do tipo **PO** (`EKKO-BSTYP = 'F'`).
- Estratégias de liberação sequenciais **e** paralelas.
- Um e-mail agregado por destinatário, mesmo que ele seja responsável por vários códigos de liberação.
- Execução em background, agendada semanalmente, e execução em diálogo com ALV para diagnóstico.

### O que está fora do âmbito (mas o desenho não deve impedir)

- Requisições de compra (PR). A arquitectura deve permitir acrescentar `EBAN` como segunda fonte sem alterar o serviço de notificação nem o template — prevê isso na interface do reader, mas **não implementes** nesta entrega.
- Escalonamento hierárquico automático após N dias.
- Workflow SAP (o âmbito é notificação informativa, não aprovação por e-mail).

---

## 2. Arquitectura

Camadas com dependências sempre a apontar para dentro. O pacote `ZPOREL` é consumidor do framework `ZEMAIL` — nunca o contrário, e `ZEMAIL` não pode ganhar qualquer conhecimento sobre POs.

```
Apresentação      ZRP_MM_PO_PEND_RELEASE (report + SALV + modo teste)
                             |
Aplicação         ZCL_POREL_PROCESSOR  (caso de uso: notificar responsáveis)
                    |         |        |
                    |         |        +--> ZCL_POREL_RUN_CONTROL (idempotência semanal)
                    |         +--> ZCL_POREL_NOTIF_BUILDER (modelo de dados do e-mail)
                    |                        |
                    |                        +--> ZIF_EMAIL_SERVICE  (framework ZEMAIL)
                    |
Domínio           ZCL_POREL_STRATEGY (regra pura: que códigos estão pendentes agora)
                    |
Infra-estrutura   ZIF_POREL_PO_READER  -> ZCL_POREL_PO_READER   (EKKO/EKPO/T16*)
                  ZIF_POREL_RESP_PROV  -> ZCL_POREL_RESP_PROV_DB (ZPOREL_C_RESP + USR21/ADR6)
                  ZIF_LOGGER           -> ZCL_LOGGER_BAL          (do ZEMAIL)
```

### Decisões de arquitectura

**ADR-001 — Tipos em interface, não em DDIC.**
Todos os tipos de trabalho (`ty_po_pending`, `ty_recipient_bundle`, etc.) vivem em `ZIF_POREL_TYPES`. Só as duas tabelas transparentes (customizing e log de execução) são objectos DDIC. Motivo: em ECC 7.40 as estruturas DDIC não têm representação em DDL source e teriam de ser criadas à mão em SE11, o que quebra o fluxo Git-first sem trazer benefício — nenhum destes tipos é usado como parâmetro RFC nem persistido.

**ADR-002 — `ZCL_POREL_STRATEGY` é lógica pura, sem acesso a base de dados.**
Recebe `FRGZU`, os códigos da estratégia (`T16FS`) e os pré-requisitos já normalizados em máscara de 8 posições, e devolve a lista de códigos pendentes accionáveis. A classe **não sabe** de que tabela vieram os pré-requisitos — é o reader que normaliza. Esta é a regra de negócio crítica do relatório: tem de ser testável sem sistema, com dezenas de casos em ABAP Unit.

**ADR-003 — Responsáveis lidos do customizing standard (`T16FW`), com tabela Z apenas como complemento.**

A atribuição de agentes a códigos de liberação já existe no customizing de compras (nó *Workflow* / atribuição de processador ao código de liberação, com o indicador de workflow no código de liberação em `T16FC`). Ler daí é preferível a duplicar a informação: quem gere as estratégias de liberação em SPRO passa a manter também, sem esforço adicional, quem é notificado. Uma tabela Z paralela desactualiza-se ao primeiro colaborador que muda de funções.

A resolução é portanto uma **cadeia de fontes**, por esta ordem:

1. `ZPOREL_C_RESP` com `SOURCE = 'O'` (override) → substitui por completo o que vier do standard, para aquele grupo/código. Serve para excepções e correcções pontuais.
2. `T16FW` — atribuição standard de agentes ao código de liberação. **Fonte primária.**
3. `ZPOREL_C_RESP` com `SOURCE = 'A'` (adicional) → destinatários que se somam aos do standard, tipicamente em `CC` (comprador, secretariado da Direcção).
4. Sem nada em nenhuma das fontes → aviso no BAL, sem excepção.

O que o standard **não** dá e continua a vir da tabela Z: nome de apresentação formatado para o e-mail, idioma, tipo de destinatário (TO/CC) e janela de validade para substituições. O e-mail nunca vem de `T16FW` — vem sempre do cadastro do utilizador (`USR21`/`ADR6`) ou do `EMAIL_OVR`.

Alternativa rejeitada: derivar responsáveis dos valores do objecto de autorização `M_EINK_FRG` por utilizador (`AGR_1251`) — frágil, dependente de perfis compostos e sem forma fiável de obter nome de apresentação.

> ⚠️ **Verificação obrigatória em Fase 0.** Circulam duas leituras diferentes de `T16FW` na documentação e nos fóruns: numa, é a tabela de *estados de liberação* (combinação de códigos já libertados → indicador de liberação, ligada a `T16FS`/`T16FB`); noutra, é a tabela de *atribuição de agente ao código de liberação* para o workflow. **Não escrevas uma linha de código antes de abrir `T16FW` em SE11 e SE16 no CBD/010 e ver os campos e o conteúdo reais.**
>
> - Se `T16FW` contiver a atribuição de agentes (campos com tipo/ID de objecto organizacional, ou utilizador), é a fonte primária como está descrito acima.
> - Se `T16FW` for a tabela de estados, localiza a tabela correcta da atribuição de agentes pelo nó de customizing (SPRO → MM → Compras → Pedido de Compra → Procedimento de liberação → Procedimento com classificação → *Workflow*) e usa o botão de informações técnicas para apanhar o nome da view/tabela. Actualiza este ADR com o nome correcto e segue o mesmo desenho de cadeia.
> - Em qualquer dos casos, verifica também o indicador de workflow em `T16FC`: se os códigos de liberação da HCB não estiverem marcados como relevantes para workflow, é provável que a atribuição de agentes **nunca tenha sido povoada** — e aí a cadeia degrada-se para a tabela Z, que passa a ser a fonte real. Conta-me o que encontraste antes de avançar.

**ADR-004 — Agregação por destinatário, não por PO nem por código.**
A chave de agrupamento é o endereço de e-mail. Um responsável por três códigos recebe um e-mail, com a coluna "Etapa" a diferenciar as linhas. Um responsável que partilha código com outro (dois aprovadores para o mesmo código) recebe cada um o seu e-mail com a mesma lista.

**ADR-005 — Controlo de idempotência semanal.**
`ZPOREL_RUN` regista cada envio por (semana ISO, destinatário). Se o job correr duas vezes na mesma semana, o segundo envio é saltado, salvo se o parâmetro `P_FORCE` estiver activo. Motivo: reexecuções manuais para diagnóstico não devem produzir e-mails duplicados para a Direcção.

---

## 3. Regra de negócio central — determinar a etapa pendente

Esta é a parte onde a maioria dos relatórios deste tipo falha. Implementa exactamente assim.

### 3.1 Selecção das POs candidatas

```abap
SELECT ebeln, bukrs, bstyp, bsart, lifnr, ekorg, ekgrp, waers,
       bedat, aedat, ernam, frggr, frgsx, frgke, frgzu, frgrl
  FROM ekko
  INTO TABLE @lt_ekko
  WHERE bstyp = 'F'          " apenas Pedidos de Compra
    AND loekz = @space       " cabeçalho não eliminado
    AND frggr <> @space      " tem grupo de liberação
    AND frgsx <> @space      " tem estratégia atribuída
    AND frgrl = 'X'          " liberação ainda NÃO concluída
    AND ebeln IN @s_ebeln
    AND bsart IN @s_bsart
    AND ekorg IN @s_ekorg
    AND ekgrp IN @s_ekgrp
    AND lifnr IN @s_lifnr
    AND bedat IN @s_bedat
    AND frggr IN @s_frggr.
```

`FRGRL = 'X'` significa "liberação ainda não efectuada por completo" e é o filtro correcto para "pendente". **A confirmar em Fase 0:** que `FRGRL` está preenchido de forma consistente no CBD — em alguns sistemas com histórico de migração este campo tem lixo; se for o caso, o critério passa a ser derivado de `FRGZU` (ver 3.3) e `FRGRL` fica apenas como filtro auxiliar.

Exclui ainda POs cujos itens estejam **todos** eliminados (`EKPO-LOEKZ <> space`): lê `EKPO` com `FOR ALL ENTRIES` e descarta as POs sem qualquer item activo.

### 3.2 Valor da PO

`EKKO` não tem valor total fiável em ECC. Soma `EKPO-NETWR` dos itens com `LOEKZ = space`, agrupando por `EBELN`, e apresenta na moeda `EKKO-WAERS`. Não converta para moeda de grupo nesta versão — o e-mail mostra a moeda do documento.

### 3.3 Códigos da estratégia e estado actual

Para cada par distinto (`FRGGR`, `FRGSX`) presente no resultado, lê uma vez (não dentro do LOOP):

| Tabela | Conteúdo | Campos relevantes |
|---|---|---|
| `T16FS` | Estratégias de liberação — **fonte principal** | `FRGGR`, `FRGSX`, `FRGC1`…`FRGC8` (códigos por posição) e, se existirem, os campos de pré-requisito por posição |
| `T16FD` | Descrição das estratégias | descrição de `FRGSX` |
| `T16FC` | Códigos de liberação | `FRGGR`, `FRGCO` |
| `T16FT` / texto de código | Descrição dos códigos | descrição de `FRGCO` |
| `T16FG` | Grupos de liberação | descrição de `FRGGR` |
| `T16FV` | Pré-requisitos — **só se não estiverem na `T16FS`** | por código, que posições têm de estar libertadas antes |

**Decisão (revista):** a `T16FS` é a única leitura obrigatória para a regra de liberação. Ela decifra o `FRGZU` (posição → código) e, se a estrutura confirmar em Fase 0 que também transporta os pré-requisitos por posição, resolve tudo com um único `SELECT`. A `T16FV` fica como fonte alternativa, a usar apenas se a `T16FS` não tiver essa informação.

> **A confirmar em Fase 0, por esta ordem:**
> 1. Abrir `T16FS` em SE11 e listar **todos** os campos. Se além de `FRGC1`…`FRGC8` houver um segundo conjunto de campos por posição (indicadores de pré-requisito/sequência), é essa a fonte — a `T16FV` sai do desenho.
> 2. Se `T16FS` só tiver os códigos, abrir `T16FV` e usá-la como fonte de pré-requisitos.
> 3. Se nenhuma das duas der pré-requisitos utilizáveis, aplica-se o modo por omissão da secção 3.4.2.
>
> Confirmar também os nomes exactos das tabelas de texto (`T16FD`/`T16FT`), que variam entre releases. E validar sempre contra uma PO real: pega numa PO com estratégia de 3 níveis, compara o resultado do algoritmo com o que a ME29N mostra, e só avança quando bater certo.

`EKKO-FRGZU` é `CHAR 8`. A posição *i* corresponde ao código na posição *i* da estratégia em `T16FS`:

- `FRGZU+i(1) = 'X'` → o código dessa posição **já libertou**.
- `FRGZU+i(1) = space` → ainda **não libertou**.

`FRGZU` é apenas um mapa de `X` e espaços: não contém nenhum código. Sem a `T16FS` para decifrar as posições, sabe-se quantas liberações faltam mas não de quem — por isso ela é o elo que não se pode saltar.

### 3.4 Algoritmo (`ZCL_POREL_STRATEGY=>get_pending_codes`)

A classe recebe tudo já lido e não conhece a origem dos dados. Isto é deliberado: se a fonte dos pré-requisitos mudar de `T16FS` para `T16FV` (ou vice-versa) depois da Fase 0, só muda o reader — a regra de negócio e os seus testes ficam intactos.

#### 3.4.1 Núcleo — comparação posicional

Os pré-requisitos entram normalizados como **máscara de 8 posições** com a mesma semântica do `FRGZU`, seja qual for a tabela de origem. Assim o teste inteiro colapsa numa comparação posicional, sem lógica aninhada:

```
ENTRADA: iv_frgzu   (CHAR8, estado actual)
         it_codes   (posição -> código, de T16FS)
         it_prereq  (código -> máscara CHAR8 de posições exigidas)
         iv_mode    (modo por omissão quando não há máscara — ver 3.4.2)
SAÍDA:   et_pending (código, posição, is_actionable, blocked_by)

Para cada posição i de 1 a 8:
  código := it_codes[i]
  SE código é vazio        -> ignora (estratégia com menos de 8 níveis)
  SE iv_frgzu+(i-1)(1) = 'X' -> já libertado, ignora

  " candidato a pendente
  máscara := it_prereq[código]
  SE máscara está vazia:
      is_actionable := regra por omissão de iv_mode
  SENÃO:
      is_actionable := abap_true
      Para j de 1 a 8:
          SE máscara+(j-1)(1) = 'X' E iv_frgzu+(j-1)(1) <> 'X':
              is_actionable := abap_false
              acrescenta it_codes[j] a blocked_by
  Acrescenta a et_pending
```

Em ABAP, o núcleo da comparação é literalmente isto:

```abap
lv_actionable = abap_true.
DO 8 TIMES.
  lv_pos = sy-index - 1.
  IF lv_prereq_mask+lv_pos(1) = 'X' AND iv_frgzu+lv_pos(1) <> 'X'.
    lv_actionable = abap_false.
    APPEND it_codes[ sy-index ]-frgco TO lt_blocked_by.
  ENDIF.
ENDDO.
```

#### 3.4.2 Modo por omissão — quando não há pré-requisitos configurados

Este ponto é decisivo e não pode ficar implícito. Se a estratégia não tiver pré-requisitos definidos (nem na `T16FS`, nem na `T16FV`, ou porque o customizing nunca foi povoado), não há forma de distinguir uma estratégia sequencial de uma paralela só a olhar para os dados. Duas regras possíveis:

| Modo | Regra | Consequência |
|---|---|---|
| `S` — sequencial (**omissão**) | Só a **primeira** posição por libertar é accionável | Conservador: notifica apenas quem está de facto na vez. Se a estratégia for paralela, os outros aprovadores não são notificados nessa semana |
| `P` — paralelo | **Todas** as posições por libertar são accionáveis | Se a estratégia for sequencial, o nível 3 recebe POs que o nível 2 ainda nem viu — falso positivo grave |

O modo é controlado pelo parâmetro `P_PARMOD` do report (omissão `S`). O erro do modo sequencial é uma notificação a menos; o do modo paralelo é ruído que destrói a credibilidade do e-mail à terceira semana. Por isso a omissão é `S`.

Se, na Fase 0, se verificar que a HCB usa estratégias paralelas sem pré-requisitos configurados, a recomendação é **povoar o customizing** em vez de mudar o modo — a informação passa a estar no sítio certo e beneficia também o workflow standard.

#### 3.4.3 Regras de saída

**Só entram no e-mail as linhas com `is_actionable = abap_true`.** As restantes existem no resultado interno (aparecem no ALV com semáforo amarelo, úteis para diagnóstico) mas nunca geram notificação — é precisamente isto que garante que ninguém recebe POs que ainda estão à espera do nível anterior.

Casos-limite que o algoritmo tem de tratar sem dump e que têm de ter teste unitário:

- Estratégia com um único código (`FRGC1` preenchido, restantes vazios).
- `FRGZU` totalmente vazio (nenhuma liberação ainda) → todos os códigos sem pré-requisito são accionáveis em modo `P`; apenas o primeiro em modo `S`.
- `FRGZU` com todos os 'X' → nada pendente; a PO não devia ter passado o filtro `FRGRL`, mas se passar, é descartada silenciosamente com aviso no log.
- Estratégia existente em `EKKO` mas **inexistente** em `T16FS` (customizing apagado) → não rebenta; regista erro no BAL com o número da PO e continua.
- Máscara de pré-requisitos que aponta para uma posição sem código atribuído → ignora essa posição, regista aviso.
- Códigos com pré-requisitos circulares no customizing → detecta e regista aviso; trata como não accionável.

### 3.5 Dias pendentes (P2, opcional mas especificado)

Para a coluna "Dias parada", a data de referência é a mais recente entre:

- `EKKO-AEDAT` (última alteração do cabeçalho), e
- a data da última alteração de `FRGZU` em `CDPOS` (`OBJECTCLAS = 'EINKBELEG'`, `TABNAME = 'EKKO'`, `FNAME = 'FRGZU'`).

Se a estratégia foi **reposta** (registo em `CDPOS` com `FNAME = 'FRGKE'` e `VALUE_OLD = 'A'` / `VALUE_NEW = 'B'`, ou `FRGZU` a voltar a vazio), a contagem reinicia a partir dessa data — uma PO alterada depois de aprovada não deve aparecer como "parada há 90 dias".

Lê `CDHDR`/`CDPOS` numa única passagem com `FOR ALL ENTRIES` sobre a lista de POs já filtrada, **nunca dentro do LOOP**. Se `P_MINDIA` estiver preenchido, filtra as POs com menos dias que o limite.

---

## 4. Resolução do responsável

### 4.1 Cadeia de fontes

`ZIF_POREL_RESP_PROV` tem três implementações e um composto:

| Classe | Papel |
|---|---|
| `ZCL_POREL_RESP_PROV_T16FW` | Lê os agentes atribuídos ao código de liberação no customizing standard |
| `ZCL_POREL_RESP_PROV_DB` | Lê `ZPOREL_C_RESP` (overrides, destinatários adicionais, metadados de apresentação) |
| `ZCL_POREL_RESP_PROV_CHAIN` | Compõe as duas segundo a ordem do ADR-003 e devolve a lista final |
| `ZCL_POREL_MAIL_RESOLVER` | Traduz um utilizador/objecto organizacional num endereço SMTP |

O processor conhece apenas `ZIF_POREL_RESP_PROV` e recebe o composto por injecção. Assim, se em Fase 0 se concluir que `T16FW` não serve, basta injectar só o provider da tabela Z — sem tocar em mais nada.

### 4.2 Leitura do customizing standard (`ZCL_POREL_RESP_PROV_T16FW`)

Lê **uma vez**, para todos os pares (`FRGGR`, `FRGCO`) distintos do resultado, nunca dentro do LOOP. Preenche os nomes de campo depois da verificação de Fase 0.

Três formatos possíveis de agente e como tratar cada um:

- **Utilizador SAP** (tipo de objecto `US` ou campo de utilizador directo) → caso simples, segue para o resolvedor de e-mail.
- **Posição** (`S`) ou **unidade organizacional** (`O`) → é preciso expandir para pessoas. Usa `RH_STRUC_GET` ou a leitura de `HRP1001` (relação `A008` posição → pessoa, e `A003`/`B003` para org unit) e depois `PA0105` subtipo `0001` para o utilizador SAP. **A HCB usa Infotype 0105 subtipo `0010` para o e-mail corporativo** — se a expansão organizacional entrar em jogo, obtém o e-mail directamente daí em vez de passar por `USR21`/`ADR6`.
- **Cargo/função** (`AC`) ou regra (`AG`) → fora do âmbito. Regista aviso e deixa a tabela Z cobrir esses códigos.

Se existirem substituições de workflow activas (`HRUS_D2`), o substituto **acresce** ao titular, não o substitui — a decisão é notificar ambos, porque um e-mail informativo a mais é preferível a uma PO parada. Documenta esta escolha no README.

Se `T16FW` (ou a tabela equivalente confirmada) estiver vazia para um código, isso não é erro: a cadeia continua para a tabela Z.

### 4.3 Tabela de customizing `ZPOREL_C_RESP`

Tabela transparente, classe de entrega `C`, manutenção via SM30 (gerar view de manutenção `V_ZPOREL_C_RESP` com grupo de função próprio).

| Campo | Tipo | Chave | Descrição |
|---|---|---|---|
| `MANDT` | `MANDT` | ✓ | Mandante |
| `FRGGR` | `FRGGR` | ✓ | Grupo de liberação |
| `FRGCO` | `FRGCO` | ✓ | Código de liberação |
| `BNAME` | `XUBNAME` | ✓ | Utilizador SAP responsável |
| `EMAIL_OVR` | `AD_SMTPADR` | | E-mail alternativo (sobrepõe-se ao do utilizador) |
| `DISP_NAME` | `CHAR60` (dom. próprio) | | Nome de apresentação no e-mail |
| `LANGU` | `SPRAS` | | Idioma do e-mail (default `P`) |
| `RECIP_TYPE` | `CHAR3` (dom. próprio: TO/CC) | | Tipo de destinatário |
| `SOURCE` | `CHAR1` (dom. próprio) | | `O` = substitui o standard · `A` = acresce ao standard |
| `VALID_FROM` | `DATS` | | Início de validade (substituições) |
| `VALID_TO` | `DATS` | | Fim de validade |
| `ACTIVE` | `XFELD` | | Registo activo |

A chave inclui `BNAME` para permitir vários aprovadores no mesmo código. Registos com `ACTIVE = space` ou fora da janela de validade são ignorados — é assim que se implementa substituição por férias sem apagar nada.

Um registo com `SOURCE = 'A'` e `BNAME` de um utilizador que **já vem** do standard não duplica o destinatário: serve para enriquecer os metadados dele (nome de apresentação, idioma, `RECIP_TYPE`). A deduplicação é sempre por endereço de e-mail resolvido.

### 4.4 Resolução do e-mail (`ZCL_POREL_MAIL_RESOLVER`)

Independentemente da fonte do responsável, o endereço resolve-se por esta ordem:

1. `EMAIL_OVR` da tabela Z preenchido → usa-o.
2. E-mail do utilizador SAP: `USR21` (`BNAME` → `PERSNUMBER`, `ADDRNUMBER`) e depois `ADR6` (`SMTP_ADDR`, o registo com menor `CONSNUMBER`).
3. Se o agente veio de expansão organizacional e tem PERNR conhecido: `PA0105` subtipo `0010` (e-mail corporativo HCB).
4. Sem e-mail em lado nenhum → **não é erro fatal**. Regista aviso no BAL com grupo/código/utilizador, a PO aparece no ALV marcada como "sem destinatário", e o processamento continua.

Igualmente: código de liberação **sem qualquer responsável configurado** gera aviso, nunca excepção. O objectivo do relatório é notificar quem dá para notificar, não abortar por customizing incompleto.

### 4.5 Agregação

Após resolver, constrói o mapa `e-mail → conjunto de linhas`. Uma linha aparece uma única vez por destinatário, mesmo que a mesma pessoa seja responsável por dois códigos accionáveis na mesma PO (caso raro mas possível em estratégias paralelas) — nesse caso a coluna "Etapa" concatena os códigos.

Ordena as linhas de cada e-mail por dias pendentes descendente (as mais paradas em cima) e, como critério secundário, por valor descendente.

---

## 5. Integração com o framework ZEMAIL

### 5.1 Contrato

O processor recebe `ZIF_EMAIL_SERVICE` por injecção no construtor, com fallback para a factory do framework:

```abap
METHODS constructor
  IMPORTING
    io_reader        TYPE REF TO zif_porel_po_reader   OPTIONAL
    io_resp_provider TYPE REF TO zif_porel_resp_prov   OPTIONAL
    io_email_service TYPE REF TO zif_email_service      OPTIONAL
    io_logger        TYPE REF TO zif_logger             OPTIONAL.
```

Quando um parâmetro vem inicial, o construtor instancia a implementação por omissão (`ZCL_EMAIL_FACTORY` para o serviço de e-mail). Isto mantém o report simples (`NEW zcl_porel_processor( )`) e os testes totalmente isolados.

O envio faz-se pela fachada:

```abap
ls_result = mo_email_service->send(
    iv_template_id = mv_template_id      " 'ZPO_PEND_RELEASE'
    iv_language    = ls_recipient-langu
    it_recipients  = lt_recipients        " zemail_t_recipient
    it_values      = lt_values            " zemail_t_placeholder
    it_tables      = lt_tables ).         " tabela(s) para render HTML
```

> **A confirmar em Fase 0:** nomes exactos dos parâmetros e do método em `ZIF_EMAIL_SERVICE`, o nome do método da factory (`ZCL_EMAIL_FACTORY=>...`), e a estrutura de `ZEMAIL_T_RECIPIENT` / `ZEMAIL_T_PLACEHOLDER` / `ZEMAIL_S_SEND_RESULT`. Lê as definições reais por ADT antes de escrever o builder. Se a assinatura divergir do que está acima, **adapta o código a ela** — não alteres o `ZEMAIL`.

### 5.2 Template `ZPO_PEND_RELEASE`

Novo template *child* em `ZEMAIL_TMPL` / `ZEMAIL_TMPL_CNT`, assente no master `ZHCB_MASTER` já existente (cabeçalho com logótipo CID e rodapé institucional). Entrega o HTML como ficheiro `.md`/`.html` de especificação em `doc/`, para carregamento manual pela transacção de manutenção de templates — **não** o escrevas hardcoded em ABAP.

Placeholders escalares:

| Placeholder | Conteúdo |
|---|---|
| `{{NOME_RESPONSAVEL}}` | Nome de apresentação do destinatário |
| `{{DATA_EXECUCAO}}` | Data da execução, formato `DD.MM.AAAA` |
| `{{SEMANA}}` | Semana ISO, ex.: `2026-W33` |
| `{{TOTAL_PO}}` | Número de POs pendentes para este destinatário |
| `{{VALOR_TOTAL}}` | Soma dos valores, formatada com separador de milhares |
| `{{MOEDA}}` | Moeda predominante (ou `—` se houver mais de uma) |
| `{{DIAS_MAIS_ANTIGA}}` | Dias da PO parada há mais tempo |
| `{{LINK_ME29N}}` | Texto de instrução de acesso (ME29N / portal), configurável |

Placeholder de tabela: `{{TABELA_POS}}`, alimentado por `it_tables` e renderizado pelo `ZCL_PLACEHOLDER_SERVICE` via RTTI.

Colunas da tabela, por esta ordem: **PO · Tipo · Fornecedor · Data doc. · Valor · Moeda · Etapa (código + descrição) · Dias parada · Grupo compras**.

> ⚠️ **Armadilha conhecida.** O placeholder da tabela **não pode** passar por `cl_http_utility=>escape_html`. Se passar, as tags `<tr>`/`<td>` chegam ao e-mail como texto literal — sintoma já observado nesta instalação: o cabeçalho estático renderiza bem e as linhas dinâmicas aparecem em bruto. Os valores escalares são escapados; o bloco de tabela é injectado em bruto. Confirma qual é o comportamento do `ZCL_PLACEHOLDER_SERVICE` em modo estrito antes de dar a fase por fechada, e valida com `cl_demo_output=>display_html` sobre a string final antes de enviar.

O assunto do e-mail vive no template, não no ABAP. Sugestão: `POs pendentes da sua aprovação — {{TOTAL_PO}} documento(s) — semana {{SEMANA}}`.

---

## 6. Objectos a criar

Pacote `ZPOREL`, repositório abapGit próprio, `FOLDER_LOGIC = PREFIX`, `MASTER_LANGUAGE = E`, `STARTING_FOLDER = /src/`.

```
.abapgit.xml
README.md
doc/
  ESPEC_ZPOREL_NOTIF_SEMANAL.md          ← este documento
  template_zpo_pend_release.html         ← HTML do template para carregar em ZEMAIL
  ddic_manual.md                         ← guião SE11/SE91 dos objectos manuais
src/
  package.devc.xml
  zif_porel_types.intf.abap|.intf.xml
  zif_porel_po_reader.intf.abap|.intf.xml
  zif_porel_resp_prov.intf.abap|.intf.xml
  zcl_porel_po_reader.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_strategy.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_resp_prov_t16fw.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_resp_prov_db.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_resp_prov_chain.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_mail_resolver.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_notif_builder.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_run_control.clas.abap|.clas.xml|.clas.testclasses.abap
  zcl_porel_processor.clas.abap|.clas.xml|.clas.testclasses.abap
  zcx_porel.clas.abap|.clas.xml
  zrp_mm_po_pend_release.prog.abap|.prog.xml
```

Objectos **manuais** (SE11/SE91 — documenta em `doc/ddic_manual.md`, não tentes gerar XML):

- Tabela `ZPOREL_C_RESP` + domínios/elementos de dados próprios + view de manutenção SM30.
- Tabela `ZPOREL_RUN` (log de execução/idempotência).
- Classe de mensagens `ZPOREL` (SE91).

### Classe de mensagens `ZPOREL`

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

### Tabela `ZPOREL_RUN`

| Campo | Tipo | Chave | Descrição |
|---|---|---|---|
| `MANDT` | `MANDT` | ✓ | Mandante |
| `RUN_ID` | `SYSUUID_C32` ou `CHAR32` | ✓ | Identificador da execução |
| `ISO_WEEK` | `CHAR8` | | Semana ISO, ex.: `2026W33` |
| `EMAIL` | `AD_SMTPADR` | | Destinatário |
| `RUN_DATE` / `RUN_TIME` | `DATS` / `TIMS` | | Momento do envio |
| `PO_COUNT` | `INT4` | | Nº de POs incluídas |
| `SEND_ID` | `CHAR32` | | ID devolvido pelo `ZEMAIL` |
| `STATUS` | `CHAR1` | | `S` sucesso, `E` erro, `K` saltado |
| `MESSAGE` | `CHAR255` | | Texto de erro, se houver |
| `TEST_MODE` | `XFELD` | | Execução em modo teste |

Índice secundário por `ISO_WEEK` + `EMAIL` — é a leitura do controlo de idempotência. Registos com `TEST_MODE = 'X'` **não** contam para o controlo semanal.

---

## 7. Report `ZRP_MM_PO_PEND_RELEASE`

Ecrã de selecção:

```
BLOCO b1 — Filtros de documento
  s_ebeln  SELECT-OPTIONS FOR ekko-ebeln
  s_bsart  SELECT-OPTIONS FOR ekko-bsart
  s_ekorg  SELECT-OPTIONS FOR ekko-ekorg
  s_ekgrp  SELECT-OPTIONS FOR ekko-ekgrp
  s_lifnr  SELECT-OPTIONS FOR ekko-lifnr
  s_bedat  SELECT-OPTIONS FOR ekko-bedat
  s_frggr  SELECT-OPTIONS FOR ekko-frggr

BLOCO b2 — Notificação
  p_send   CHECKBOX  DEFAULT 'X'   " enviar e-mails
  p_tmpl   TYPE ... DEFAULT 'ZPO_PEND_RELEASE'
  p_langu  TYPE spras DEFAULT 'P'
  p_mindia TYPE i DEFAULT 0        " dias mínimos pendente
  p_force  CHECKBOX                " ignorar controlo semanal
  p_parmod TYPE c LENGTH 1 DEFAULT 'S'   " modo sem pré-requisitos: S/P (ver 3.4.2)

BLOCO b3 — Modo teste
  p_test   CHECKBOX
  p_mailts TYPE ad_smtpadr         " obrigatório se p_test = 'X'
```

Comportamento:

- `p_test = 'X'` → **todos** os e-mails vão para `p_mailts`, com prefixo `[TESTE — destinatário real: xxx@hcb.co.mz]` no assunto, e o registo em `ZPOREL_RUN` marcado com `TEST_MODE`. Validação `AT SELECTION-SCREEN`: com `p_test` marcado e `p_mailts` vazio, erro.
- `p_send = space` → simulação completa: selecciona, resolve, agrega, mostra ALV, **não envia nada** e não escreve em `ZPOREL_RUN`.
- Em background (`sy-batch = abap_true`): sem SALV; escreve resumo em lista (spool) e log completo no BAL.
- Em diálogo: SALV com semáforo — verde = accionável e notificado, amarelo = pendente mas bloqueado por nível anterior, vermelho = accionável mas sem destinatário resolvido. Hotspot em `EBELN` chamando `ME23N` via `SET PARAMETER ID 'BES'` + `CALL TRANSACTION`.

Autorização: `AUTHORITY-CHECK OBJECT 'M_BEST_EKO' ID 'EKORG' FIELD ... ID 'ACTVT' FIELD '03'` por organização de compras distinta encontrada. Sem autorização numa EKORG, exclui essas POs e regista aviso — não aborta o job inteiro.

---

## 8. Logging

Usa o `ZIF_LOGGER` / `ZCL_LOGGER_BAL` do `ZEMAIL`, com objecto BAL `ZPOREL` e sub-objectos `SELECT`, `RESOLVE` e `NOTIFY`. Cria o objecto BAL em SLG0 (documenta em `doc/ddic_manual.md`).

Regista pelo menos: contagem de POs seleccionadas, POs descartadas e porquê, códigos sem responsável, utilizadores sem e-mail, cada envio com destinatário e contagem, cada falha com o texto da excepção. O log tem de permitir responder, em SLG1, à pergunta "porque é que o fulano não recebeu e-mail esta semana?" sem depurar nada.

---

## 9. Testes ABAP Unit

Cada classe com lógica leva `.clas.testclasses.abap`. Duplos de teste implementam as interfaces — nunca acedas à base de dados em testes.

**`ZCL_POREL_STRATEGY`** (a mais importante, sem duplos, lógica pura):

- Estratégia de 1 nível, `FRGZU` vazio → 1 código accionável.
- Estratégia de 3 níveis sequenciais, `FRGZU = 'X   '` → só o nível 2 é accionável; nível 3 pendente mas bloqueado.
- Estratégia de 3 níveis paralelos (sem pré-requisitos), `FRGZU` vazio → 3 accionáveis.
- Estratégia mista: níveis 1 e 2 paralelos, nível 3 dependente de ambos; com só o 1 libertado → o 2 accionável, o 3 bloqueado.
- `FRGZU` completo → nenhum pendente.
- Estratégia inexistente em `T16FS` → devolve vazio, sem dump.
- Pré-requisitos circulares → nenhum accionável, aviso emitido.
- **Sem máscara de pré-requisitos, modo `S`**: `FRGZU = 'X   '` numa estratégia de 3 níveis → só o nível 2 accionável.
- **Sem máscara de pré-requisitos, modo `P`**: os mesmos dados → níveis 2 e 3 accionáveis.
- Máscara a apontar para posição sem código → posição ignorada, resultado inalterado, aviso emitido.

**`ZCL_POREL_RESP_PROV_DB`**: prioridade do `EMAIL_OVR`, filtro de validade e `ACTIVE`, distinção entre `SOURCE = 'O'` e `'A'`, código sem responsável.

**`ZCL_POREL_RESP_PROV_CHAIN`** (com duplos dos dois providers): standard sozinho; standard mais adicional em CC; override a anular por completo o standard; ambas as fontes vazias → lista vazia com aviso; mesmo utilizador nas duas fontes → um só destinatário, com os metadados da tabela Z a prevalecer.

**`ZCL_POREL_MAIL_RESOLVER`**: ordem das quatro fontes de endereço, `ADR6` com vários registos (menor `CONSNUMBER`), utilizador inexistente, agente sem e-mail em lado nenhum.

**`ZCL_POREL_NOTIF_BUILDER`**: agregação de várias POs por destinatário, dedup do mesmo destinatário em códigos diferentes, ordenação por dias descendente, formatação de valores, moedas mistas → `{{MOEDA}}` fica `—`.

**`ZCL_POREL_PROCESSOR`** com duplo de `ZIF_EMAIL_SERVICE`: envio chamado uma vez por destinatário; `p_send = space` não chama envio nenhum; modo teste redirecciona todos os destinatários; excepção do serviço de e-mail para um destinatário não impede os restantes.

**`ZCL_POREL_RUN_CONTROL`**: segundo envio na mesma semana é saltado; `P_FORCE` ignora o controlo; registos de teste não bloqueiam.

Meta: cobertura total dos ramos de `ZCL_POREL_STRATEGY` e de todos os métodos públicos das restantes classes.

---

## 10. Agendamento

Job SM36 `ZPOREL_NOTIF_SEMANAL`:

- Passo único: `ZRP_MM_PO_PEND_RELEASE`, variante `SEMANAL`.
- Periodicidade semanal, **segunda-feira às 07:00**.
- Utilizador de execução: utilizador técnico de batch com autorizações de leitura de compras em todas as EKORG.
- Variante `SEMANAL`: `p_send = 'X'`, `p_test = space`, `p_force = space`, `p_langu = 'P'`, `p_parmod = 'S'`, filtros de documento vazios (todas as POs), `p_mindia = 0`.

Documenta os passos exactos de criação do job em `doc/ddic_manual.md`, incluindo a criação da variante — é o passo que costuma ficar esquecido quando o transporte chega a PRD.

---

## 11. Convenções de código

- **ABAP 7.40**: `VALUE`, `FOR`, `REDUCE`, `CORRESPONDING`, `NEW`, `COND`/`SWITCH`, string templates, SQL com `@`. **Não** uses sintaxe 7.50+ (`LOOP AT ... GROUP BY` com `GROUP` avançado só se confirmado no sistema, `CONV` em posições novas, `FILTER` com tabela de condição).
- **Restrição conhecida**: não se pode usar declaração inline (`DATA(...)`) no adjunto `MESSAGE` de excepções de `CALL FUNCTION`. Declara antes.
- Clean ABAP: métodos curtos com uma responsabilidade, nomes por intenção, `RETURNING` em vez de `EXPORTING` quando há um só resultado, excepções baseadas em classes com `IF_T100_MESSAGE`, sem variáveis globais no report (tudo dentro de classes; o report só faz o ecrã de selecção e delega).
- **Zero `SELECT` dentro de `LOOP`.** Todas as leituras são em massa, com `FOR ALL ENTRIES` ou `RANGE`, antes do processamento. Isto é um requisito, não uma preferência: em PRD há milhares de POs abertas.
- `SELECT` sempre com lista de campos explícita, nunca `SELECT *`.
- ABAP Doc em todos os métodos públicos e em todas as interfaces.
- Textos de mensagens sempre pela classe `ZPOREL`, nunca literais no código.

---

## 12. Plano de execução por fases

Confirma comigo no fim de cada fase antes de avançar.

### Fase 0 — Descoberta e confirmação (obrigatória)

- [ ] Ler por ADT/MCP a definição de `ZIF_EMAIL_SERVICE`, `ZCL_EMAIL_FACTORY`, `ZEMAIL_S_RECIPIENT`/`ZEMAIL_T_RECIPIENT`, `ZEMAIL_S_PLACEHOLDER`/`ZEMAIL_T_PLACEHOLDER`, `ZEMAIL_S_SEND_RESULT`, `ZIF_LOGGER`.
- [ ] Confirmar como o `ZCL_PLACEHOLDER_SERVICE` recebe tabelas internas e se aplica escape ao bloco de tabela.
- [ ] **Listar todos os campos de `T16FS` em SE11** e decidir se os pré-requisitos estão lá (secção 3.3). Só se não estiverem é que a `T16FV` entra no desenho.
- [ ] Confirmar em SE11 a estrutura real de `T16FC`, `T16FG` e das tabelas de texto correspondentes.
- [ ] Verificar, com `SE16` sobre as estratégias de PO activas na HCB, se os pré-requisitos estão de facto povoados — se não estiverem, confirmar comigo o modo por omissão (`P_PARMOD`) antes da Fase 3.
- [ ] Confirmar o comportamento de `EKKO-FRGRL` no CBD com uma consulta de amostra.
- [ ] Validar o algoritmo contra 3 POs reais com estratégias diferentes (1 nível, sequencial de 3, paralela), comparando com a ME29N.
- [ ] **Abrir `T16FW` em SE11 e SE16** e determinar qual das duas leituras se aplica (estados de liberação vs. atribuição de agentes) — ver o aviso no ADR-003. Registar os campos reais e uma amostra do conteúdo.
- [ ] Se `T16FW` não for a tabela de agentes, identificar a tabela/view correcta pelo nó de customizing de workflow e actualizar o ADR-003.
- [ ] Verificar o indicador de workflow em `T16FC` para os códigos de liberação de PO da HCB — se não estiverem marcados, a atribuição de agentes pode nunca ter sido povoada.
- [ ] Confirmar o tipo dos agentes encontrados (utilizador, posição, unidade organizacional) e se é preciso expansão organizacional.
- [ ] Listar as estratégias de liberação de PO activas na HCB e os códigos de cada uma, com os agentes atribuídos — serve de base à decisão sobre quanto é preciso povoar em `ZPOREL_C_RESP`.

**Entregável:** ficheiro `doc/fase0_descobertas.md` com os factos confirmados e as divergências face a este documento.
**Gate:** revisão minha antes de escrever código.

### Fase 1 — Bootstrap do repositório e DDIC
- [ ] `.abapgit.xml`, `README.md`, `src/package.devc.xml` (skill `abapgit-metafiles`).
- [ ] `doc/ddic_manual.md` com o guião SE11/SE91/SLG0 completo: domínios, elementos de dados, `ZPOREL_C_RESP`, `ZPOREL_RUN`, view SM30, classe de mensagens `ZPOREL`, objecto BAL.
- [ ] Correr `check`.
**Gate:** crio os objectos manuais no CBD e confirmo.

### Fase 2 — Tipos, excepção e interfaces
- [ ] `ZIF_POREL_TYPES`, `ZCX_POREL`, `ZIF_POREL_PO_READER`, `ZIF_POREL_RESP_PROV`.
**Gate.**

### Fase 3 — Regra de liberação
- [ ] `ZCL_POREL_STRATEGY` + testes completos da secção 9.
**Gate:** todos os testes verdes. Esta fase não passa com testes em falta.

### Fase 4 — Leitura de dados
- [ ] `ZCL_POREL_PO_READER` (EKKO/EKPO/T16*/CDHDR/CDPOS) + testes.
**Gate.**

### Fase 5 — Responsáveis
- [ ] `ZCL_POREL_MAIL_RESOLVER` + testes.
- [ ] `ZCL_POREL_RESP_PROV_T16FW` (ou a tabela confirmada em Fase 0) + testes.
- [ ] `ZCL_POREL_RESP_PROV_DB` + testes.
- [ ] `ZCL_POREL_RESP_PROV_CHAIN` + testes.
**Gate:** listagem comparativa, para cada código de liberação activo, de quem vem do standard e quem vem da tabela Z — revista comigo antes de avançar.

### Fase 6 — Construção da notificação
- [ ] `ZCL_POREL_NOTIF_BUILDER` + testes.
- [ ] `doc/template_zpo_pend_release.html` (child do `ZHCB_MASTER`, tabela responsiva, compatível com Outlook — tabelas HTML, estilos inline, sem flexbox).
**Gate:** carrego o template e valido a pré-visualização.

### Fase 7 — Orquestração e controlo de execução
- [ ] `ZCL_POREL_RUN_CONTROL`, `ZCL_POREL_PROCESSOR` + testes com duplo de `ZIF_EMAIL_SERVICE`.
**Gate.**

### Fase 8 — Report e ALV
- [ ] `ZRP_MM_PO_PEND_RELEASE` com ecrã de selecção, validações, SALV, semáforos, hotspot ME23N, comportamento em background.
- [ ] `check` final do repositório completo.
**Gate:** pull para CBD/010, activação e teste em diálogo.

### Fase 9 — Validação e entrega
- [ ] Teste com `p_send = space` e comparação manual com ME28.
- [ ] Teste com `p_test = 'X'` para o meu e-mail.
- [ ] Variante `SEMANAL`, job SM36, documentação de transporte.
- [ ] `README.md` final: o que é, como configurar `ZPOREL_C_RESP`, como diagnosticar em SLG1.

---

## 13. Critérios de aceitação

A solução é aceite quando, cumulativamente:

1. Um responsável recebe **exactamente** as POs à espera dele — validado contra a ME29N do próprio, sem falsos positivos nem omissões, em pelo menos 3 estratégias diferentes.
2. Nenhuma PO bloqueada por um nível anterior aparece em qualquer e-mail.
3. Um responsável por vários códigos recebe **um** e-mail agregado.
4. Reexecutar o job na mesma semana não gera segundo e-mail (salvo `P_FORCE`).
5. Customizing incompleto (código sem responsável, utilizador sem e-mail, estratégia órfã) produz aviso no BAL e nunca dump nem aborto do job.
5b. Acrescentar um agente ao código de liberação no customizing standard faz com que ele passe a ser notificado na semana seguinte, **sem qualquer alteração em tabelas Z nem em código**.
6. O e-mail renderiza correctamente no Outlook desktop e no Outlook Web, com o logótipo visível e a tabela formatada — sem HTML em bruto.
7. Todos os testes ABAP Unit passam; `ZCL_POREL_STRATEGY` com cobertura total de ramos.
8. Execução em background sem qualquer dependência de frontend.
9. `abapgit_meta.py check` sem erros.
10. Tempo de execução aceitável no volume de PRD (alvo: abaixo de 5 minutos com todas as POs abertas).

---

## 14. Pontos em aberto para decisão do negócio

Levanta-os comigo, não decidas sozinho:

- **Cópia para o comprador (EKGRP) ou para a Direcção de Compras?** Sugestão: registo com `SOURCE = 'A'` e `RECIP_TYPE = 'CC'` na tabela de responsáveis resolve isto por configuração, sem código adicional.
- **Substituições de workflow (`HRUS_D2`): notificar titular e substituto, ou só o substituto?** Assumi ambos. Se a Direcção preferir só o substituto durante a ausência, é uma linha a mudar no provider.
- **Incluir ou não POs de valor abaixo de um limite?** Neste momento não há filtro de valor; acrescentar `p_minval` é trivial se for pedido.
- **Idioma dos e-mails.** Assumido português (`P`) para todos. Se houver aprovadores de língua inglesa, o campo `LANGU` da tabela já suporta, mas é preciso criar a versão `E` do template.
- **Estratégias sem pré-requisitos configurados.** Se existirem, a recomendação é povoar o customizing em vez de usar `P_PARMOD = 'P'`. Vale a pena decidir isto com quem gere as estratégias em SPRO, porque beneficia também o workflow standard.
- **Resumo consolidado para a Direcção.** Um e-mail semanal adicional com o total por etapa e os campeões de antiguidade seria uma extensão natural — fora do âmbito desta entrega.
