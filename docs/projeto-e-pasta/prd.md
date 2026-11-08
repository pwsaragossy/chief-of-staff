# PRD: projeto = a pasta que o Pedro cria

## Problema
Pedro (fundador solo, trabalha em várias pastas: Radox, SCF, genogramAI, plugins) começa cada trabalho numa pasta nova, mas o plugin só liga board, painel, STATE, trilha, handoff e biblioteca dentro de uma pasta central (`~/chief-of-staff`) da qual ele precisa lembrar. Resultado: o painel mostra só o dock-folders e o resto do trabalho fica invisível.

## Por que agora
A 0.10.0 já levou as regras (especialistas, ambition) para toda pasta. O painel e o board continuam presos à central; sem isso o Pedro não acompanha os projetos, que é o motivo do plugin.

## Entra
1. `/threads` numa conversa transforma a pasta dela em projeto: cria só o mínimo (marcador e `board/`, sem perguntas), registra a pasta na lista de projetos do plugin e abre o painel web daquele projeto junto com o painel Threads.
2. Na pasta do projeto funcionam: board com cards, STATE.md e briefing, DECISIONS.md, trilha de entregas (Stop bloqueia), handoff, "só a coordenadora pergunta ao dono", dispatcher (continua desligado por padrão) e sync de time.
3. Biblioteca global: busca e salva em toda conversa, no lugar escolhido no setup (hoje `~/brain/Company library`).
4. Painel global: a mesma página do `/chief-of-staff:panel`, lendo a lista de projetos registrados; o painel do projeto é a mesma página filtrada a uma pasta.
5. Entradas em camadas: `setup` (primeira vez, escolhe a biblioteca) chama `new-project`; `new-project` (perguntas, coerência, trilha) chama `/threads`; `/threads` sozinho é a entrada leve.
6. O painel lateral Projects (comando `/projects`) sai.
7. Nenhuma central, de nenhum tipo. O dock-folders sai de `~/chief-of-staff/projects/dock-folders` para uma pasta própria, com os cards dele, e a `~/chief-of-staff` é arquivada. A `~/central` também sai: o papel dela (ver todos os projetos, o MAPA.md) passa para o painel global; ela é arquivada, e as linhas do CLAUDE.md global que citam a `~/central` são atualizadas. Arquivar só com o sim do Pedro, depois que o painel global funcionar.

## Não entra
- O painel lateral Threads não muda (aparência e comportamento iguais).
- `~/brain` e `~/brain-radox` não são tocados: são os boards e as regras das sessões, não uma central.
- Nada de painel acessível pela internet: continua 127.0.0.1 com token; no celular segue o resumo em texto (`overview.sh`).
- Nenhuma função nova além da lista de projetos; o resto é religar o que existe.

## Pronto quando
- Numa pasta nova qualquer, `/threads` cria marcador e `board/`, registra a pasta, e o painel web mostra esse projeto (teste no selftest e conferência no app).
- O painel global lista dois projetos em pastas diferentes, sem nenhuma pasta central (selftest).
- Board, trilha, handoff e ask-guard passam no selftest numa pasta de projeto fora de qualquer central.
- Selftest completo passa; o comando `/projects` não existe mais.
- Pedro abre o painel no app e vê os projetos dele.

## Riscos
- Mudança de hook: publicar só com o OK do Pedro.
- Sessões antigas dentro da `~/chief-of-staff` param de achar a central: migrar o dock-folders antes de arquivar.
- Lista de projetos com pasta apagada ou movida: o painel mostra "pasta não encontrada", não quebra.
