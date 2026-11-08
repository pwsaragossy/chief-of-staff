# Plano: projeto = a pasta que o Pedro cria

Contrato: [prd.md](prd.md) e [design.md](design.md). Este plano diz como o código chega lá, arquivo por arquivo.

## Ideia central
A pasta do projeto é a própria raiz. O marcador `.chief-of-staff` dela tem a linha `kind: project`; `cos_root`
já acha o marcador mais próximo, então todo script que hoje chega a uma raiz chega à pasta do projeto. O que muda é
como cada script acha "o projeto" dentro da raiz:

| | workspace antigo (até a migração) | pasta de projeto (`kind: project`) |
|---|---|---|
| pasta do projeto | `root/projects/<slug>` | `root` |
| slug | o nome da subpasta | o nome da pasta (`basename root`) |
| board | `root/board`, cards filtrados por `project:` | `root/board`, todos os cards são do projeto |
| quem fala com o dono e registra o OK | `central/` (OK) e `projects/<slug>` (perguntas) | a coordenadora: sessão na raiz, pasta registrada, e não é thread |
| role cards | `root/specialists` | `root/specialists` se existir, senão os do plugin |
| biblioteca | linha `library:` do marcador, senão `root/knowledge` | linha `library:` do marcador, senão `<plugin data>/library` |

Os dois modelos convivem só até a migração do dock-folders (último passo, com o sim do Pedro). Os ramos `central/`
e `projects/<slug>` saem num commit seguinte, depois do arquivamento; o selftest antigo continua cobrindo-os até lá.

## Quem é a coordenadora (os dois portões que mudam de dono)
Três condições, cada uma numa camada:
1. **Pasta** (shell, `cos_owner` em lib.sh): `CLAUDE_PROJECT_DIR` é exatamente a raiz de um marcador `kind: project`.
   O diretório vem do Claude Code, não do shell: um `cd` não o muda.
2. **Registro** (shell): a raiz está em `<plugin data>/projects`. Uma worktree dentro do projeto que carregue o
   marcador commitado é raiz de si mesma, mas não está registrada; um marcador plantado numa pasta qualquer também não.
3. **Não é thread** (módulo `hooks/projects.tsx`): uma sessão com `parentSessionId` e não destacada foi iniciada por
   outra sessão. As threads da coordenadora rodam na mesma pasta, então a pasta sozinha não as distingue. O módulo nega
   `AskUserQuestion`, `track.sh ok` e `project.sh` numa thread. Uma sessão aberta pelo Pedro não tem pai.

`ask-guard.sh`, `protocol.sh` (PreToolUse de `track.sh ok`) e `track.sh ok` aceitam: o antigo (`central/`, e
`projects/<slug>` para perguntas) **ou** `cos_owner`. `track.sh ok` numa pasta de projeto só aceita o próprio
projeto (a raiz da sessão é a raiz do `<project_dir>`). O OK continua passando pelo pedido de permissão ao dono.

Proteção dos arquivos novos: `protocol.sh` bloqueia Write/Edit em `<plugin data>/projects` e `<plugin data>/library`
e trata `plugins/data` como nome protegido em comando Bash dentro de um projeto (ler pode, escrever não). Ambos
nascem somente-leitura (444), como o marcador.

## Arquivos que mudam
- `scripts/lib.sh`: `cos_data` (pasta de dados do plugin: `CLAUDE_PLUGIN_DATA`, senão derivada do caminho do script
  em `plugins/cache/<mkt>/<plugin>/<ver>`, senão `~/.cache/chief-of-staff`); `cos_isproj ROOT`; `cos_pdirs ROOT`
  (as pastas de projeto de uma raiz); `cos_pdir ROOT SLUG`; `cos_proj ROOT DIR` (slug e pasta do projeto de uma
  sessão); `cos_registered DIR`; `cos_owner ROOT DIR`; `cos_lib` lê `<plugin data>/library` numa pasta de projeto.
- `scripts/project.sh` (novo): `init <dir>` cria marcador (`kind: project`, 444), `board/Inbox.md`, `STATE.md`,
  `DECISIONS.md` a partir dos templates, só se não houver marcador, e registra a pasta (sem repetir); `library <dir>`
  grava `<plugin data>/library` (cria a estrutura de biblioteca numa pasta vazia, aceita uma biblioteca existente);
  `list` imprime cada pasta registrada e se ela existe.
- `scripts/ask-guard.sh`: aceita `cos_owner`; mensagem fala de coordenadora, não de central.
- `scripts/protocol.sh`: `project`/`pdir` via `cos_proj` em vez de `projects/<slug>` (arquivo de controle TRACK/DELIVERY,
  guarda de push por DECISIONS, gate de trilha, STATE da rotação); portão de `track.sh ok` aceita `cos_owner`; role cards
  em `$SPEC`; caminho rápido de Read reconhece a biblioteca global; proteção dos dois arquivos novos.
- `scripts/track.sh`: `ok` aceita `cos_owner` para o próprio projeto.
- `scripts/briefing.sh`: numa pasta de projeto, o briefing de projeto (STATE, decisões, trilha, cards que esperam o dono);
  a frase de coordenadora só na raiz.
- `scripts/health.sh`, `scripts/dispatcher.sh`: laço sobre `cos_pdirs`; TRACK do card via `cos_pdir`.
- `scripts/panel.py`: recebe uma pasta (painel do projeto, ou o workspace antigo) ou `--all` (painel global: cada linha
  de `<plugin data>/projects`). Projetos de várias raízes numa lista, pior primeiro; pasta sumida vira linha cinza
  "Folder not found" com o caminho; lista vazia: "No projects yet. Run /threads in a folder." Mesma página e visual.
- `scripts/overview.sh`: `--all` lê os boards das pastas registradas.
- `hooks/projects.tsx`: sai `/projects`, o painel Projects (`PANE`) e o que só ele usa (`view`, `busy`, `chats`,
  `newChatDraft`); `/threads` roda `project.sh init` na pasta da conversa e pede à sessão para abrir o painel web do
  projeto; `session.start` numa raiz `kind: project` (fora de thread) liga a coordenadora e abre o Threads; após um
  `project.sh init` bem-sucedido (o fim do `new-project`) a conversa vira coordenadora; o painel Threads lê memória e
  cards da pasta do projeto. Aparência e comportamento do Threads iguais.
- `types/index.d.ts`, `tests/projects.test.tsx`: sem os átomos e testes do painel Projects; testes novos de `/threads`,
  da coordenadora no início e da negação em thread.
- Skills: `setup` (pergunta a biblioteca, `project.sh library`, depois `new-project`; não cria central),
  `new-project` (roda na pasta do projeto, grava STATE/TRACK lá, termina com `project.sh init`), `panel` (projeto ou
  `--all`), `handoff` (sem ramo central: a coordenadora reescreve o STATE do projeto), `knowledge` (sem "only central").
- Templates: `board/Inbox.md` e `board/card.md` sem "central"; `project/CLAUDE.md` idem.
- `README.md`: o modelo novo em poucas linhas.

## Migração de dados (último passo, só com o sim do Pedro, depois do painel global no app)
1. `project.sh library "/Users/pedrosaragossy/brain/Company library"` (a linha `library:` do marcador atual).
2. dock-folders: copiar `~/chief-of-staff/projects/dock-folders` para uma pasta própria, com os cards dele de
   `~/chief-of-staff/board` (os de `project: dock-folders`), os role cards e um marcador `kind: project`; `project.sh init`.
3. Arquivar `~/chief-of-staff` e `~/central` (mover para uma pasta de arquivo; nada é apagado) e atualizar as linhas do
   `~/.claude/CLAUDE.md` que citam `~/central`.
4. Remover os ramos `central/` e `projects/<slug>` e o `setup.sh create` antigo.
Nada disso roda neste PR; o selftest prova a migração numa cópia descartável.

## "Pronto quando" → checagem no selftest (seção "project folders", numa pasta temporária sem central)
| Pronto quando | Checagem |
|---|---|
| `/threads` numa pasta nova cria marcador e `board/`, registra, o painel mostra o projeto | `project.sh init` cria `.chief-of-staff` (`kind: project`, 444), `board/Inbox.md`, `STATE.md`, `DECISIONS.md`; a pasta aparece uma vez em `projects` mesmo rodando duas vezes; rodar de novo não recria nada; `panel.py` (snapshot da pasta) lista o projeto. Teste do módulo: `/threads` chama `project.sh init` com a pasta da conversa e devolve o pedido de abrir o painel. |
| painel global lista dois projetos em pastas diferentes, sem central | duas pastas `init`; `snapshot --all` traz os dois slugs; uma terceira registrada e apagada aparece como "Folder not found" sem quebrar; lista vazia dá a mensagem certa. |
| board, trilha, handoff e ask-guard numa pasta de projeto | ask-guard: raiz registrada passa, subpasta e worktree com marcador próprio bloqueiam, raiz não registrada bloqueia; `track.sh ok` da raiz registrada grava o OK, de subpasta ou de outro projeto recusa; PreToolUse de `track.sh ok` pede o OK do dono na raiz e bloqueia fora dela; gate de trilha do Stop lê o TRACK.md da pasta; briefing mostra STATE, decisões e cards; rotação pede o STATE.md da pasta (handoff); Write em `projects`/`library` do plugin bloqueado. Teste do módulo: thread na raiz não pergunta nem roda `track.sh ok`. |
| selftest completo passa; `/projects` não existe | selftest inteiro; teste do módulo confere que só `threads` é registrado. |
| Pedro abre o painel no app e vê os projetos | manual, depois da migração (`overview.sh --all` também listado no selftest). |

## Revisão de engenharia (plan-eng-review, 2026-11-08)
- Escopo: mais de 8 arquivos, mas é a mudança pedida (religar, sem função nova); nenhuma parte é adiável sem deixar o
  plugin meio central, meio pasta. Fica.
- Caminhos com link simbólico (`/tmp` e `/private/tmp`, pastas no iCloud): o registro grava `pwd -P` e `cos_registered`
  compara `pwd -P` da raiz. Checagem no selftest com a pasta aberta por um link.
- Registro com linha repetida (dois `/threads` ao mesmo tempo): `init` confere antes de gravar e o painel tira repetidas.
- Thread não detectada (a chamada `get_session` do módulo falha): o módulo deixa passar e as camadas de pasta e
  registro continuam valendo; o OK ainda passa pelo pedido de permissão ao dono. Falhar fechado travaria a
  coordenadora quando o app não responde.
- Desempenho: `cos_proj` roda em todo hook; usa um `grep` no marcador e nenhum `cd`. `cos_owner` (`pwd -P`) só roda
  nos portões de pergunta e de OK.
- Regressão: os testes de central e `projects/<slug>` ficam até a migração e provam que o modelo antigo não quebrou.
- Fora do escopo: biblioteca de time por projeto (`.library`) numa pasta de projeto (a de time segue no workspace
  antigo até alguém pedir); mensagens do plugin em português (o plugin todo é em inglês).
