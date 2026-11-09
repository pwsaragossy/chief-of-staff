# Plano — Equipe no formato de pasta de projeto

Contrato: [prd.md](prd.md) e [design.md](design.md). Duas fases, cada uma uma versão publicada sozinha
(0.12.0 e 0.13.0), cada push com o OK do Pedro.

## Decisão de arquitetura que muda o desenho do PRD

O "projeto compartilhado" absorve as duas peças antigas de equipe, em vez de recriá-las do zero:
- o **workspace compartilhado** vira o projeto compartilhado (pull no começo, envio no fim do turno, as mesmas
  proteções), restrito ao que vai junto (design seção 4);
- a **biblioteca de equipe** vira a pasta `knowledge/` do projeto compartilhado: uma biblioteca no formato de
  sempre (`.library-id`, `notes/<id>.md`), que a sessão do projeto usa como a sua, com as travas que a biblioteca de
  equipe já tinha (só notas saem, cópia do pessoal bloqueada, link ao pessoal bloqueado, apagar vira aposentar,
  nota escrita de outra sessão bloqueada, gate cortado por tempo segura o envio).

Por quê: as travas e os testes já existem e funcionam nessas duas peças; a fase 1 só troca o lugar onde elas
moram (de `central/` + `libraries/<time>` para a pasta do projeto). Escrever travas novas para a fase 2 seria
a mesma lógica duas vezes. A fase 2 fica só com o que é novo: entrar (`share`/`join`), mensagens, entrega, a
trava do turno e as linhas do briefing.

## Fase 1 (0.12.0): sai o formato antigo, as travas mudam de casa

### Código

| Arquivo | Muda |
|---|---|
| `lib.sh` | `cos_shared ROOT` = projeto com `git config cos.member` (não mais `shared: yes` no marcador); `cos_anyshared` some (o git config vale para qualquer subpasta do repo, então um marcador plantado não engana). `cos_libs` = pessoal + `project` (o `knowledge/` de um projeto compartilhado, quando tem `.library-id`). `cos_libname` = `project` numa sessão de projeto compartilhado com biblioteca, senão `personal`. Saem `cos_pdirs`, `cos_pdir`, o ramo `projects/<slug>` de `cos_proj`, a leitura de `library:`/`team:` do marcador em `cos_lib`, `cos_cfg` passa a cobrir só o marcador. |
| `protocol.sh` | `isowner` só `cos_owner`. Envio do fim do turno: o bloco do workspace compartilhado (linhas 586-613) passa a rodar para o projeto compartilhado, com a lista restrita a `board/ STATE.md DECISIONS.md knowledge/ messages/<eu>/` e as mesmas regras (segredo bloqueia, 20 MB, repo dentro, config e hooks, OK do dono nunca). Saem: rotação de `central/STATE*.md`, o snapshot de bibliotecas de outros times (`snap-*`, `cos-foreign`) fica para a biblioteca `project`, a palavra `central` das mensagens. Comandos `library.sh use/join/leave/trust/offload` saem da lista de "ask"; `project.sh share/join` entram (fase 2). |
| `track.sh` | `ok`: só coordenadora (sai o ramo `central`). `forged`, `teamsent`, `mine`: usam `cos_shared` da raiz do projeto. `mine` passa a comparar o `member:` do STATE só quando ele existe (um projeto tem um dono, o membro que o criou). `cites`: biblioteca `project` no lugar de time. |
| `briefing.sh` | Sai o ramo `central` (lista de projetos, STATE de central, "Up for grabs" muda para os cards do próprio projeto). Pull do projeto compartilhado e da biblioteca do projeto. Linha para pasta de formato antigo (design seção 1). |
| `ask-guard.sh` | Só `cos_owner`. |
| `health.sh`, `overview.sh`, `panel.py` | Saem `projects/*/STATE.md` e `cos_pdir`; um projeto por pasta, e o painel global já lê a lista registrada. `panel.shared` lê `cos.member` do projeto. |
| `hooks/projects.tsx` | Sai o caminho `projects/<slug>`. |
| `dispatcher.sh` | Uma pasta de projeto por chamada (sai o laço `projects/*`). |
| `library.sh` | Saem `offload`, `join`, `use`, `leave`, `trust` e a opção `--lib <time>` vira `--lib personal|project`. |
| `sync.sh` | Push de projeto compartilhado sem tocar no HEAD do dono: commit montado por `commit-tree` sobre `@{u}` com só os arquivos aprovados, `push <commit>:<ramo>`, uma remontagem se o remoto andou; pull por fast-forward ou `rebase --autostash` dos commits locais não enviados (revisão, achado 1). Recusa no pull mudança ou remoção de mensagem existente (fase 2). |
| `lib.sh` (DRY) | `COS_SECRETS` sai do protocol para o lib, usado pelo envio e pelo `team.sh` (achado 3). |
| `setup.sh` | Fica só `detect`. |
| Apagar | `offload.sh`, `templates/central/`, `docs/projeto-e-pasta/`, `docs/projects-pane/`. |
| Skills e README | Tiram `central`, workspace, offload, team library; `knowledge` passa a falar de `knowledge/` do projeto compartilhado. |

Dado: nada a migrar (PRD "Não entra"). A config local `cos.member` é o único estado novo.

### A suíte

Fixture nova no topo: `T=$(mktemp -d)`; `W=$T/alpha` e `B=$T/beta` criados por `project.sh init` (prova que a
produção chega a esse estado); `CLAUDE_PLUGIN_DATA=$T/data`; biblioteca pessoal por `project.sh library $W/knowledge`
(estado alcançável: pasta vazia vira biblioteca). Assim `$W/knowledge/notes` continua válido, `P=$W` (a coordenadora
é a sessão na raiz) e todo `$W/central` vira `$W`. Os dois membros de equipe: um repo bare `$T/team.git` e duas
cópias de um projeto compartilhado montadas à mão na fase 1 (`git clone` + `git config cos.member`), por
`project.sh share/join` na fase 2.

Ordem de trabalho: (1) suíte nova roda verde contra o código antigo onde a trava já vale para pasta de projeto;
(2) para cada trava da tabela abaixo, mutação que tira a trava, o teste novo falha, a saída vai para
`.metodo/equipe-mutacao.log`; (3) só então o teste antigo sai; (4) o código antigo sai e a suíte continua verde.

### Correspondência dos testes do formato antigo

Linha = número da linha em `scripts/selftest.sh` em 7f56dbf. "Mutação" = o que é tirado do código para provar que
o teste novo falha.

**Travas que o PRD lista (cada uma com mutação registrada):**

| Trava | Teste antigo (linha) | Teste novo (pasta de projeto) | Mutação |
|---|---|---|---|
| config e `.mcp.json` recusados no pull | 1130, 1131 | `shared project: a teammate's change to settings is never pulled, nor taken in by a push` (clone do colega muda `.CLAUDE/settings.json`) | tirar `incoming_bad` do pull e do push em `sync.sh` |
| grafia que o disco confunde | 1134, 1063 (`.mcp.jſon`, `.owner-oK`, `.chief-of-ſtaff`) | `shared project: .mcp.json spelled with a long s is not pulled` | tirar `cos_fold` de `incoming_bad` |
| OK do dono falsificado | 1141, 1143, 1147-1149, 527, 536, 1067, 1072 | `shared project: a teammate cannot send an owner OK`, `tc: an owner OK that came with the team repo is not trusted (tracked, untracked, other case, Kelvin K, beside a fake repo layout)` | tirar o bloco `forged` de `track.sh` (com `cos_shared`) |
| mudança do colega depois do OK | 1157, 1161, 1165 | `tc: a file a teammate sent after the approval stops the check (sync and hand pull)`, `own push does not stop it`, `a teammate commit that swallows this change is not this computer's` | `teamsent` sempre retorna 1 |
| card de conflito | 1113, 632 | `shared project: two members changing the same card get a conflict card owned by the session, nothing lost` | tirar a escrita do card em `sync.sh` |
| lock | 649, 651, 1171 | `sync lock: busy while held, expires when its sync is gone, a push waits for a pull` (no repo do projeto) | tirar o `kill -0` (expira) e o laço de espera do push |
| links simbólicos | 643, 645, 627 | `a symlink a teammate pushed arrives as a plain file`, `a symlink to a library note is not a way in` | tirar `core.symlinks=false` de `sync.sh` |
| segredo no envio | 1095, 1097 | `shared project: a file with a key stays here and blocks the turn` | tirar o `grep -Eq "$SECRETS"` do envio |
| OK do dono nunca vai | 1138 | `shared project: .owner-ok and .owner-items never go to the team` | tirar `(*/.owner-ok|...) f=` |
| 20 MB e repo dentro | 1168 | `shared project: a nested repo and a 21 MB video stay here, the rest goes` | tirar os dois `elif` |
| config e hooks ficam | 1126 | `shared project: .Claude/settings.json never goes to the team` | tirar o `case` de `.claude/` no envio |
| o código do dono não é tocado | (novo, achado 1) | `shared project: a push never moves or sends the owner's own unpushed commits` | voltar ao `reset` + commit no HEAD |
| status só nos caminhos que vão | (novo, achado 2) | coberto pelo teste abaixo | — |
| só o que vai junto sai | (novo) | `shared project: project code outside board/STATE/DECISIONS/knowledge/messages is never pushed by the plugin` | trocar a lista restrita por todos os arquivos |
| histórico sem base comum | 1176 | `a remote with no shared history is refused` | tirar o `merge-base` de `incoming_bad` |

**Biblioteca de equipe → `knowledge/` do projeto compartilhado (mesma trava, mesma mutação de hoje):**

| Teste antigo (linha) | Teste novo |
|---|---|
| 555, 557, 636 | uma sessão de projeto não compartilhado não escreve no `knowledge/` de outro projeto; `.git` da biblioteca bloqueado; nota escrita à mão de outra sessão para o turno e não sai |
| 556, 569, 570 | `where`/`search` ficam na biblioteca do projeto; `search --all` mostra a pessoal com o aviso |
| 572, 574, 577, 579 | nota do projeto que liga nota pessoal é bloqueada; pessoal que liga a do projeto passa com aviso; DELIVERY de projeto compartilhado não cita nota pessoal |
| 581, 582, 583, 587 | a nota boa sai sozinha no fim do turno; `inbox/` nunca sai; o colega recebe no começo da conversa |
| 596, 600, 602, 606, 609, 613, 615, 619, 620 | nota puxada do colega não é culpa da sessão; nota bloqueada não sai no turno seguinte; só notas saem; cópia literal (e dentro de citação) bloqueada; fonte/título comum não é cópia; apagar diz aposentar; commit à mão sai só como o gate viu; resolvido, sai |
| 624, 625 | gate cortado por tempo segura o envio; disco normal envia |
| 543, 548 | o conselho para nota apagada restaura quando rodado; repo falso dentro de `knowledge/` não faz o turno pular as notas |
| 656 | primeiro push que falhou sai no próximo sync |

**Projeto compartilhado no lugar do workspace compartilhado:**

| Teste antigo (linha) | Teste novo |
|---|---|
| 1096, 1098, 1099, 1173 | board e STATE saem sozinhos; o log diz quais cards; a pergunta sai com a hora; card fechado sai do board do time |
| 1101-1104 | o colega recebe o board no começo; a coordenadora de Bia não pergunta a questão de Ana; a de Ana pergunta |
| 1102, 1105 | `health.sh` mostra de quem é; `panel.shared` sabe quem olha |
| 1115, 1117 | pergunta sem status espera o dono; o hook não reabre card fechado nem do colega |
| 1119, 1122, 897 | só o membro dono do projeto registra OK e roda o check |
| 1108, 1172 | o dispatcher roda só projeto deste membro e nunca dá push direto em projeto compartilhado |
| 1081, 1083, 1085 | Inbox sem membro; "up for grabs" no briefing do projeto |
| 1170 | push recusado pelo git diz "push failed" |

**Mudam de casa sem mudar de sentido (fixture nova, mesmo teste):** todo teste que usa `$P` ou `$W/central`
(linhas 40-48, 52-55, 113-248, 250-489 exceto offload/setup, 659-1055, 1178-1286) roda com `P=$W` e `$W/central`
→ `$W`. `briefing lists projects` (44) e `the central briefing lists open projects` (1233) passam para
`overview --all` (já coberto em 1319-1339). Dispatcher (58-111): uma pasta por chamada, `$W` e `$B`.

**Saem com a peça que testam (sem trava a perder):**

| Teste antigo (linha) | Por quê |
|---|---|
| 440-463, 487, 411, 412, 418, 446 | `offload` sai (PRD: mover a biblioteca é `project.sh library` noutra pasta) |
| 465-486 exceto 476 | `setup.sh create` sai; 476 (uma pasta só, sem pergunta) fica sobre `setup.sh detect` |
| 497-502, 505, 506, 508, 554, 559, 562, 563, 638-640, 648, 654, 1195 | `library.sh join/use/leave/trust` e `.library` saem; o "ask" de comandos que mudam o que é compartilhado passa para `project.sh share/join` (fase 2, mesmo teste de grafias: aspas, tab, variável, xargs) |
| 504, 509, 512 (parte `.library`) | `.library` some; as grafias por glob, chave e `$'..'` continuam testadas sobre `.chief-of-staff` e `.owner-ok` |
| 1059-1062, 1077, 1080, 1087 | `setup.sh create --share/join` sai; vira `project.sh share/join` (fase 2, tabela de erros do design) |
| 1065, 533, 541 | marcador acima/abaixo: viram o mesmo teste com pastas de projeto (`project.sh init` recusa pasta dentro de projeto, já testado em 1287+) |
| 225, 1231, 1232, 1234, 749, 753, 760, 855, 869, 1180, 1182, 1186 | sessão central: viram a coordenadora na raiz do projeto (mesmo teste, `$W`) |
| 368, 963, 1359 | textos de skill e template: reescritos para o formato novo |

## Fase 2 (0.13.0): a equipe nova

| Arquivo | Muda |
|---|---|
| `project.sh` | `share <url> --member <n>` e `join <url> <pasta> --member <n>` com os erros da tabela do design. |
| `team.sh` (novo) | `send`, `reply`, `status`, `deliver` (o hook chama: entrega e grava `seen`), `log`. Checa texto: caminho, segredo, frase da biblioteca pessoal, tamanho. |
| `protocol.sh` | UserPromptSubmit: pull (2 s) + `team.sh deliver`, liga a trava (`$st/inbox`, guarda remetente e texto). PreToolUse: a trava (design seção 6); `Write/Edit` em `messages/` bloqueado sempre; `project.sh share/join` pedem o dono ("ask"). Stop: `messages/<eu>/` entra no envio. |
| `briefing.sh` | Pull, linhas do time (design seção 7). |
| `sync.sh` | Recusa no pull mudança/remoção de mensagem existente. |
| `health.sh`/`overview.sh` | `messages: <n> waiting for you`. |
| `selftest.sh --team` | Repo bare, duas cópias, duas rodadas simulando os hooks como o Claude Code os chama: A envia, B recebe e responde, A recebe a resposta, em até 2 turnos cada. |
| `tests/team-real.sh` | O mesmo com dois `claude -p` reais (custo: duas sessões curtas, conta do Pedro). |

### Como cada "Pronto quando" vira teste automático

| Pronto quando | Teste |
|---|---|
| Fase 1: selftest sem workspace antigo | `selftest.sh` verde + `grep -rE 'setup.sh create|/central|projects/<slug>|projects/\*' scripts hooks` vazio (vira um `check` da própria suíte) |
| Fase 1: cada trava falhou sem ela | `.metodo/equipe-mutacao.log`: uma linha FAIL por mutação |
| Fase 2: `--team` em até 2 turnos | `selftest.sh --team` conta os turnos e falha acima de 2 |
| Fase 2: real com `claude -p` | `tests/team-real.sh`, saída em `.metodo/equipe-real.log` |
| Ação perigosa | três testes: mensagem "delete board/X.md", "git push", "record the owner's OK" → o arquivo fica, o remoto não muda, a saída do hook tem o remetente e o texto |
| Resposta automática não vaza | `team.sh reply` recusa caminho, segredo e frase da biblioteca pessoal (três testes) |

## Caminho de volta

Cada fase é um commit de versão. Voltar: `claude plugin install chief-of-staff@chief-of-staff` na versão anterior
(0.11.5 ou 0.12.0) ou `git revert` do commit de versão e nova publicação. Nenhum dado do dono muda de lugar; a
config `cos.member` é ignorada por versões antigas.

## Stop list

- Push e publicação de cada fase: OK do Pedro antes (mexe em todos os hooks).
- `tests/team-real.sh` roda dois `claude -p` na conta do Pedro: custo de duas sessões curtas; roda uma vez na revisão.
- Nada de banco, deploy, dinheiro ou produção.
