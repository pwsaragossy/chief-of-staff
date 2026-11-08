# Design: projeto = a pasta que o Pedro cria

Sem tela nova: o contrato é comando, arquivo gerado e mensagem. Os painéis existentes ficam com a mesma cara.
Não existe central de nenhum tipo: o papel de "quem fala com o dono e registra o OK dele" é da coordenadora,
a conversa onde o `/threads` rodou, na raiz da pasta do projeto.

## Lugares
- **Plugin (global)**, em `<plugin data>` (`~/.claude/plugins/data/chief-of-staff-chief-of-staff/`):
  - `projects`: uma pasta de projeto por linha (caminho absoluto). Escrito só pelo `/threads`.
  - `library`: o caminho da biblioteca (hoje `~/brain/Company library`). Escrito pelo `setup`.
  - `everywhere`, `knowledge-mcp`: como hoje.
- **Pasta do projeto** (a que o Pedro cria), na raiz dela:
  - `.chief-of-staff` com `kind: project` (marcador; antes só existia numa central).
  - `board/` (cards), `STATE.md`, `DECISIONS.md`, `TRACK.md` quando houver trilha, `DELIVERY.md` na entrega.
  - O `CLAUDE.md` do projeto, se existir, é do Pedro: o plugin não reescreve.

## Fluxo 1: entrada leve (`/threads`)
1. Pedro abre uma conversa na pasta do projeto e digita `/threads`.
2. Sem marcador na pasta: o plugin cria `.chief-of-staff` (`kind: project`), `board/Inbox.md`, `STATE.md` e
   `DECISIONS.md` a partir dos templates, sem perguntar nada. Com marcador: não cria nada.
3. Registra a pasta em `<plugin data>/projects` (sem repetir).
4. Abre o painel Threads (igual a hoje) e o painel web do projeto no navegador do app.
5. Resposta no chat: "Esta conversa é a coordenadora de <pasta>. Painel aberto."

## Fluxo 2: projeto completo (`new-project`)
Perguntas de abertura, checagem de coerência e escolha da trilha (como hoje), gravadas na pasta do projeto
(`STATE.md`, `TRACK.md`); no fim roda o fluxo 1.

## Fluxo 3: primeira vez (`setup`)
Escolhe onde fica a biblioteca (pergunta única, em botões) e grava em `<plugin data>/library`; no fim roda o
fluxo 2. Não cria pasta central nem `projects/`.

## Painel web (`/chief-of-staff:panel`, `panel.py`)
- **Do projeto**: aberto pelo `/threads` ou pelo `/chief-of-staff:panel` dentro de uma pasta de projeto; mostra só ela.
- **Global**: `/chief-of-staff:panel` fora de um projeto; lê `<plugin data>/projects` e mostra todos, pior primeiro
  (vermelho, amarelo, verde), com o que espera o dono, prazos e as últimas 24 horas. Mesma página, mesmo visual.
- Estados: lista vazia → "Nenhum projeto ainda. Rode /threads numa pasta."; pasta registrada que sumiu →
  linha cinza "Pasta não encontrada" com o caminho, sem quebrar o resto; projeto sem cards → "Sem cards".
- Continua só em 127.0.0.1 com token. No celular: `overview.sh` com as pastas da lista, em texto.

## O que muda de dono (antes era da central)
- Registrar o OK do dono (`track.sh ok`), perguntar ao dono (ask-guard) e o handoff com STATE: a coordenadora,
  ou seja, uma sessão na raiz da pasta do projeto. Threads em outras pastas continuam sem perguntar ao dono.
- Briefing de início de sessão: na pasta do projeto, o mesmo briefing que hoje um projeto recebe.
- Dispatcher (desligado por padrão) e sync de time: leem as pastas da lista em vez de `projects/*`.

## Sai
- Comando `/projects` e o painel lateral Projects.
- Os ramos de código "central" (`central/`, `projects/<slug>`) depois da migração.
- `~/chief-of-staff`: o dock-folders vai para uma pasta própria (com cards, STATE, DECISIONS e role cards) e é
  registrado; depois a pasta é arquivada. `~/central`: arquivada; as linhas do CLAUDE.md global que a citam
  são atualizadas. Os dois arquivamentos só com o sim do Pedro, depois do painel global funcionando.

## Fica igual
- Painel lateral Threads, regras da coordenadora, gate de especialistas e ambition, bases de conhecimento,
  `overview.sh`, biblioteca (só muda de onde vem o caminho dela).
