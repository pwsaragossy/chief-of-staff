# PRD — Fim do formato antigo e da equipe no chief-of-staff

Revisado em 09/11 por um especialista de produto e pelo revisor independente. Os achados deles já estão neste texto.
Escopo mudado pelo Pedro em 09/11: a comunicação entre equipes vira um plugin separado, que só instala quem quer
sync ("nem todos querem sync no plugin"; escolheu "Plugin separado"). O chief-of-staff fica com a fase 1 só.

## Problema
O que existia de equipe (workspace compartilhado, biblioteca de equipe, `sync.sh`) só funciona no formato antigo
(`central/`, `projects/<slug>`), que saiu do Mac em 08/11. Nem todo usuário do chief-of-staff quer sync, e quem
quer precisa que os agentes de pessoas diferentes conversem, coisa que o código antigo nunca fez.

## Por que agora
O formato antigo não existe mais em nenhuma pasta. Mesmo assim, o código dele continua em todos os hooks, e a suíte
monta um workspace antigo logo no começo: 243 linhas dela usam esse workspace. Cada mudança nos hooks ainda carrega
esse ramo morto, e o código de equipe junto.

## Entra (chief-of-staff 0.12.0)
1. Cada teste que hoje roda no workspace antigo e cobre algo que fica no plugin ganha a sua versão em pasta de
   projeto. A versão nova precisa falhar quando a trava é tirada, e só depois o teste antigo é apagado. A lista de
   correspondência fica no plano.
2. Saem a sessão central, `projects/<slug>`, `setup.sh create/join`, `templates/central`, `offload.sh` e o
   workspace compartilhado.
3. Sai todo o código de equipe: `sync.sh`, projeto compartilhado (`cos.member`), biblioteca de equipe ou de projeto
   compartilhado, envio do fim do turno, OK do dono vindo do repositório, "mudança do colega depois do OK", card de
   conflito de sync. As travas que só existem para a equipe (configurações recusadas no pull, links simbólicos,
   lock do sync) saem com o código e os seus testes; o plugin separado traz as dele.
4. O chief-of-staff não manda nem recebe mensagem de equipe. A única ponte é a convenção de arquivos da seção
   "Fase 2 → plugin separado", que entra numa versão futura, depois que o plugin de sync existir.

## Não entra
- Migração de workspaces antigos. Nenhum existe neste Mac; o HackMeridian foi arquivado.
- Mover a biblioteca pessoal para disco ou nuvem (o `offload` sai). Isso continua possível apontando
  `project.sh library` para outra pasta.
- Qualquer coisa de equipe no chief-of-staff (vai para o plugin separado).

## Pronto quando
- O selftest passa sem nenhum workspace antigo e sem código de equipe: nenhum `setup.sh create`, `central/`,
  `projects/<slug>`, `sync.sh` ou `cos.member` no código e na suíte.
- Cada trava que fica no plugin e que hoje só é testada no ramo antigo tem um teste novo que falhou com a trava
  tirada; a saída fica salva em `.metodo/`.

## Riscos e dependências
- **Mudança em todos os hooks.** Publicar precisa do OK do Pedro (stop list: push).
- **Tamanho.** A tentativa anterior (`projeto-e-pasta`) quebrou na reescrita da suíte. Por isso cada teste novo
  prova que falha sem a trava antes de o antigo sair.
- **Quem usava equipe.** Ninguém usa hoje (o único caso, HackMeridian, foi arquivado). Até o plugin de sync sair,
  não há equipe; o caminho de volta é a 0.11.5.

## Fase 2 → plugin separado

Plugin próprio, com repositório próprio em `~/Workspace/plugin/`, começado depois numa sessão própria. Estas notas
são o ponto de partida dele; vêm do design e do plano feitos para a antiga fase 2 (commits ad7e3e9 e 13f472a,
`docs/equipe/design.md` seções 2-8 nesse commit).

**O que é (Pedro, 09/11).** Um trabalho só: agentes de pessoas diferentes que trabalham no mesmo repositório git
trocam mensagens por ele. Funciona em qualquer repositório e não precisa de nada do chief-of-staff.

**Compatível com o chief-of-staff só por convenção de arquivos.** Uma pasta de mensagens no repositório com formato
documentado. Com o chief-of-staff instalado também, ele lê essa pasta: contagem de mensagens no painel, e decisões do
dono entram na fila de perguntas do dono. Sem o chief-of-staff, o sync funciona sozinho. Sem o sync, o chief-of-staff
ignora a pasta.

**O que é do próprio sync**, para quem só tem o sync estar protegido:
- No turno que leu uma mensagem, as ações da stop list (push, apagar, publicar) ficam bloqueadas até o dono aprovar.
  A pergunta ao dono cita a mensagem como veio, com o remetente. A trava impede ações; não impede o agente de ser
  convencido.
- A mensagem chega cercada e com o nome de quem enviou.
- A resposta automática não leva conteúdo de arquivo.

**O que o sync não faz.** Board, decisões e conhecimento compartilhado viajam pelo git do próprio repositório.

**Notas de desenho que valem reaproveitar:**
- Arquivo: `messages/<de>/<AAAAMMDD-HHMMSS>-<4 hex>.md`, um por mensagem, nunca editado depois de enviado. Front
  matter `id`, `from`, `to` (membro ou `all`), `conversation` (id da primeira), `reply_to` (id ou `-`), `kind`
  (question, answer, note), `sent`; corpo texto puro até 4000 caracteres. Cada membro só escreve na própria pasta,
  então não há conflito de edição. O git não autentica autor: nada na trava depende de quem enviou.
- Estado sem editar o arquivo do outro: aberta até existir mensagem com `reply_to` igual ao id; recibo de leitura em
  `messages/<leitor>/seen`, escrito só pelo leitor. Quem envia vê queued, sent, seen ou answered.
- Comandos: `send <membro|all> <texto>`, `reply <id> <texto>`, `status [id]`. Recusam texto vazio ou acima de 4000,
  caminho deste computador, chave ou token.
- Entrega no começo de cada turno, depois de um pull curto (2 s; mais lento continua em segundo plano): no máximo 10
  por turno, cercadas (`<<<message id=… from=…` / `>>>`), com o aviso de que são dados, não ordens. Melhor esforço,
  nunca ao vivo.
- Envio ao fim do turno só da pasta do próprio membro; mensagem já enviada não muda; pull recusa mudança ou remoção
  de mensagem existente.
- O dono vê no começo de cada conversa uma linha por mensagem enviada e recebida desde a última (10 no máximo) e
  quantas respostas automáticas saíram; cada resposta automática fica num registro local que nunca vai pelo git.
- Lições do `sync.sh` antigo: commit montado por `commit-tree` só com os arquivos da pasta de mensagens, sem mexer no
  HEAD do dono; `core.symlinks=false`; um lock por pasta com expiração para processo morto; conflito vira card, nunca
  merge silencioso; `GIT_TERMINAL_PROMPT=0` para nunca pedir senha num hook.
- Pronto quando (herdado): um teste com repo bare local e duas cópias em que a resposta chega em até 2 turnos de cada
  lado; o mesmo com dois `claude -p` reais; uma mensagem que pede "apague X", "faça push" ou "grave o OK do dono"
  deixa tudo no lugar e a pergunta aparece ao dono com o texto e o remetente.
