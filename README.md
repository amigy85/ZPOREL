# ZPOREL — Notificação Semanal de POs Pendentes de Liberação

Relatório ABAP que, semanalmente, envia a cada responsável de uma etapa de liberação de Pedidos de
Compra (PO) um e-mail HTML com as POs que estão pendentes **da aprovação dele e apenas dele** — ou
seja, POs cujo código de liberação atribuído a esse responsável ainda não foi executado **e** cujos
pré-requisitos de liberação já estão cumpridos.

- **Cliente:** HCB — Hidroeléctrica de Cahora Bassa
- **Sistema:** CBD/010 (SAP ECC EHP7, ABAP 7.40)
- **Framework de e-mail consumido:** pacote `ZEMAIL` (dependência unidireccional; nunca alterado)

## Documentação

| Ficheiro | Conteúdo |
|---|---|
| `doc/ESPEC_ZPOREL_NOTIF_SEMANAL.md` | Especificação funcional — fonte de verdade. |
| `doc/fase0_descobertas.md` | Descobertas da Fase 0 (leitura real do CBD/010) e divergências D1–D10. |
| `doc/ddic_manual.md` | Guião de criação manual dos objectos DDIC/SE91/SLG0. |
| `doc/template_zpo_pend_release.html` | Template HTML do e-mail (Fase 6). |
| `CLAUDE.md` | Contexto permanente do projecto e convenções. |

## Modelo de trabalho — Git-first

O código é escrito como ficheiros neste repositório abapGit e importado manualmente para o CBD/010
via pull; a activação e os testes são feitos no SAP. Os servidores MCP/ADT são **só de leitura**.

Configuração abapGit: `STARTING_FOLDER = /src/`, `FOLDER_LOGIC = PREFIX`, `MASTER_LANGUAGE = E`.

## Arquitectura (resumo)

Camadas com dependências a apontar para dentro:
`ZRP_MM_PO_PEND_RELEASE` (apresentação) → `ZCL_POREL_PROCESSOR` (aplicação) →
`ZCL_POREL_STRATEGY` (domínio, lógica pura) ← readers/providers de infra-estrutura
(`ZIF_POREL_PO_READER`, `ZIF_POREL_RESP_PROV`) e o `ZIF_EMAIL_SERVICE` do `ZEMAIL`.

## Configuração e diagnóstico

- **Responsáveis:** lidos do customizing standard de liberação (`T16FW`). Uma camada de
  override/CC (`ZPOREL_C_RESP`) foi **adiada** — acrescenta-se depois, se necessário, como segundo
  provider de `ZIF_POREL_RESP_PROV`, sem rework. Ver `doc/fase0_descobertas.md` §5 e `doc/ddic_manual.md`.
- **Diagnóstico:** cada execução deixa rasto no log de aplicação (SLG1), objecto BAL `ZPOREL`.

## Estado

Fase 0 (descoberta) concluída. Fase 1 (bootstrap do repositório + guião DDIC) em curso. As fases e
os respectivos gates estão na especificação, secção 12.
