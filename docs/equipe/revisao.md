# Revisão — chief-of-staff 0.12.0 (fim do formato antigo e do código de equipe)

09/11. Escopo: só a fase 1 (decisão do Pedro, 09/11: equipe vira plugin separado).

## O que foi feito
- Saem: sessão central, `projects/<slug>`, `setup.sh create/join`, `templates/central`, `offload.sh`,
  `sync.sh`, projeto compartilhado (`cos.member`), biblioteca de equipe, envio do fim do turno, visão GitHub e
  botão Fetch do painel, `teamsent` e o filtro por membro. Pedro aprovou as remoções (09/11: "Sim, pode apagar",
  "Sim, pode tirar"). Volta: versão 0.11.5 ou `git checkout 7f56dbf -- <caminho>`.
- Fica e passa a valer em todo projeto com git: a trava de OK do dono vindo do git (`track.sh`, `.from-git`),
  inclusive quando o projeto é subpasta de um repositório maior.
- Pasta antiga e pasta que já foi compartilhada recebem uma linha no briefing.
- Bug do hand-back corrigido: o crédito de agente em segundo plano lia um formato de payload que o Claude Code não
  manda (`run_in_background` no input); o real traz `tool_response.status = async_launched`. O teste antigo usava o
  formato inventado; o novo usa o real.

## Provas
- Suíte inteira: 454 ok, 0 FAIL (`.metodo/equipe-selftest.log`).
- Mutação: 12 de 12 travas tiradas fazem o teste delas falhar (`.metodo/equipe-mutacao.log`, script
  `tests/mutation.sh`).
- Hand-back: reprodução com o payload real, bloqueado antes, creditado depois
  (`.metodo/equipe-handback-antes.log`, `equipe-handback-depois.log`).
- Monorepo: teste falhou antes da correção, passa depois (`.metodo/equipe-monorepo.log`).

## Revisores
- Produto e revisor independente sobre o PRD: achados aplicados no commit be10be6 (trava de grafia fica, aviso a
  quem usava equipe, pontos em aberto do plugin de sync).
- Revisor de bypass sobre o código: um achado ALTO novo desta mudança (projeto dentro de repositório maior não
  passava pela trava de git), corrigido com teste e mutação. Os outros achados já existiam antes desta versão e o
  README os lista como limites: nome de arquivo montado numa variável no Bash, cópia renomeada do `project.sh`,
  `CLAUDE_PROJECT_DIR` confiado pelo `track.sh` fora do hook, caminho relativo no Write.
- O teste real com dois `claude -p` era da fase 2 e foi para o plugin de sync.
