# plan-eng-review — plano.md (09/11)

Revisão de engenharia do plano antes do código. Decisões técnicas tomadas aqui (Pedro decide produto, não
arquitetura); cada achado já está aplicado no plano.

## Step 0 — escopo
- O que já existe e é reaproveitado: `sync.sh` (pull/push, lock, conflito, recusa de config), o bloco de envio do
  workspace compartilhado (`protocol.sh:586-613`), o gate da biblioteca de equipe (`protocol.sh:507-585`), `forged`
  e `teamsent` de `track.sh:76-131`. Nada disso é reescrito; muda de casa.
- Mais de 8 arquivos: inerente a uma remoção que atravessa todos os hooks. Mitigação: fase 1 sozinha, suíte antes.
- Distribuição: o marketplace do plugin já publica (`claude plugin marketplace update`).

## Achados

1. **[CRÍTICO] (9/10) `scripts/sync.sh:56-60`** — o push faz `reset` até o merge-base e dobra os commits locais
   num só. No workspace compartilhado só havia arquivos do plugin; num projeto compartilhado que guarda código,
   isso desfaria os commits de código do dono que ainda não foram enviados, e o push seguinte mandaria código que o
   dono não mandou (push é da stop list). Decisão: num projeto compartilhado o plugin nunca mexe no HEAD do dono.
   O envio monta o commit por fora: índice temporário a partir de `@{u}`, só os arquivos que passaram, `commit-tree`
   com pai `@{u}`, `push <commit>:<ramo>`; se o remoto andou, busca e remonta uma vez; o mesmo arquivo mudado lá e
   aqui vira o card de conflito. O pull faz fast-forward, ou `rebase --autostash @{u}` quando há commits locais não
   enviados (conflito: aborta e card). Teste novo: `a shared project's push never moves or sends the owner's own
   unpushed commits`.
2. **[ALTO] (8/10) `scripts/protocol.sh:590`** — `git status -uall` no repo inteiro: num repo de código grande
   passa do orçamento de 5 s do hook. Decisão: o status roda só nos caminhos que vão junto
   (`-- board STATE.md DECISIONS.md knowledge messages/<eu>`), o que também é a própria regra "só o que vai junto".
3. **[MÉDIO] (9/10) `scripts/protocol.sh:74`** — a lista de segredos vive só no protocol; `team.sh` precisa da
   mesma. Decisão: `COS_SECRETS` em `lib.sh`, usada pelos dois (DRY).
4. **[MÉDIO] (7/10) dono do check num projeto com dois membros** — no workspace, cada projeto tinha um membro; agora
   o mesmo projeto é dos dois. Decisão: `share` grava `member: <primeiro>` no STATE.md; só esse membro registra OK
   e roda o check (`track.sh mine`, como hoje). Teste: `the other member's coordinator cannot record the OK`.
5. **[MÉDIO] (7/10) recibo `seen`** — um commit por turno só para o recibo enche o log do time. Decisão: o recibo
   vai no mesmo commit do envio do turno; turno sem mudança não gera commit.
6. **[BAIXO] (6/10) trava em `claude -p`** — sem dono para aprovar, a trava nega e a sessão termina contando ao
   dono. É o comportamento certo; o teste real confere que a pergunta cita a mensagem.

## Cobertura (o que o plano testa)
```
[+] sync.sh            pull ff / rebase / recusa config / grafia / sem base / msg alterada   [plano: ★★★]
                       push por commit-tree / remoto andou / conflito / lock / symlink        [plano: ★★★]
[+] protocol.sh Stop   lista restrita / segredo / 20 MB / repo dentro / OK do dono / config   [plano: ★★★]
[+] protocol.sh Pre    trava do turno: Bash leitura passa, rm/push/ok bloqueia, Write board   [plano: ★★★]
[+] track.sh           forged (4 grafias) / teamsent (3 casos) / mine                          [plano: ★★★]
[+] project.sh         share/join: 9 erros da tabela + caminho feliz                          [plano: ★★★]
[+] team.sh            send/reply/status, 4 recusas de texto, deliver 10 por turno            [plano: ★★★]
[→E2E] selftest --team e tests/team-real.sh
GAPS: nenhum aberto
```

## Fora do escopo
- Autenticar o remetente (assinatura de commit): o PRD aceita; a trava não depende do remetente.
- Tela no painel para mensagens: só a contagem (PRD).

## Resultado
Nenhum item bloqueante aberto: os 6 achados estão aplicados no plano.
