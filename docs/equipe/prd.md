# PRD — Equipe no formato de pasta de projeto

Revisado em 09/11 por um especialista de produto e pelo revisor independente. Os achados deles já estão neste texto.

## Problema
Duas pessoas tocam o mesmo projeto. Cada uma usa o próprio Claude com o plugin. Os agentes de uma não falam com os agentes da outra, então cada dono vira o carteiro entre os dois. O que existia de equipe (workspace compartilhado, biblioteca de equipe, `sync.sh`) só funciona no formato antigo (`central/`, `projects/<slug>`), que saiu do Mac em 08/11. Caso real: o HackMeridian com o Leo, que dividia board e biblioteca num workspace compartilhado.

## Por que agora
O formato antigo não existe mais em nenhuma pasta. Mesmo assim, o código dele continua em todos os hooks, e a suíte monta um workspace antigo logo no começo: 243 linhas dela usam esse workspace. Hoje a equipe não tem como ser usada, e cada mudança nos hooks ainda carrega esse ramo morto.

## Entra (em duas fases, cada uma publicada sozinha)

**Fase 1: sai o formato antigo.**
1. Cada teste que hoje roda no workspace antigo ganha a sua versão em pasta de projeto. A versão nova precisa falhar quando a trava é tirada, e só depois o teste antigo é apagado. A lista de correspondência fica no plano. Entram nela as travas que hoje só são testadas no ramo antigo:
   - configurações e `.mcp.json` recusados no pull, inclusive com grafias que o disco confunde;
   - OK do dono falsificado;
   - mudança do colega depois do OK;
   - card de conflito;
   - lock;
   - links simbólicos.
2. Depois saem a sessão central, `projects/<slug>`, `setup.sh create/join`, `templates/central`, `offload.sh`, a biblioteca de equipe presa à central e o workspace compartilhado.

**Fase 2: a equipe nova.**
3. **Projeto compartilhado.** É uma pasta de projeto cujo repositório git privado pertence ao time. Para entrar, cada membro dá a URL do repositório e o seu nome. O plugin clona, grava o nome e registra o projeto. Erros com mensagem clara: acesso negado, repositório vazio e nome repetido.
4. **Mensagens entre agentes.** Cada membro escreve só na própria pasta de saída, `messages/<membro>/`, um arquivo por mensagem. Assim nunca há conflito de edição, e o remetente não pode ser falsificado por outro membro. Cada mensagem tem destinatário, conversa, resposta-a e status (aberta ou respondida). Quem recebe é a coordenadora do projeto no computador do outro.
5. **Entrega.** O plugin envia ao fim do turno e busca no começo da conversa e a cada turno, em segundo plano. É uma entrega de melhor esforço, nunca ao vivo: se o outro não tiver uma conversa aberta, a mensagem espera a próxima. Quem envia vê o estado da mensagem: enviada, vista ou respondida. O teste real mede quantos turnos a resposta leva.
6. **Ao receber, a mensagem é informação, não ordem.**
   - A mensagem chega cercada e com o nome de quem enviou.
   - No turno que leu uma mensagem, o hook bloqueia toda ação da stop list (push, apagar, publicar, gastar, OK do dono, escrever nos arquivos protegidos) até o dono aprovar. A trava impede ações; ela não impede o agente de ser convencido. Por isso a pergunta ao dono cita a mensagem como veio, com o remetente.
   - A resposta automática, a técnica ou a já decidida, não leva conteúdo de arquivo, caminho, nem nada do brain pessoal. Um teste prova isso.
   - Board, STATE e DECISIONS vindos do colega também são tratados como entrada de fora.
7. **O dono vê o que o agente fez em nome dele.** No começo de cada conversa aparece uma linha por mensagem enviada e recebida desde a última. Toda resposta automática fica num registro.
8. **Proteções do envio**, trazidas do ramo antigo para a pasta de projeto e aplicadas também às mensagens e aos cards: varredura de segredos, OK do dono que nunca vai junto, limite de 20 MB, e configurações e hooks que nunca saem do computador.
9. **O que vai junto pelo repositório:** o board e o STATE do projeto. O DECISIONS e a pasta `knowledge/` do projeto também vão (escolha do Pedro), com uma trava que impede item do outro brain ou texto pessoal de entrar nela. A biblioteca pessoal nunca vai.

## Não entra
- Servidor, serviço na nuvem ou conta nova. O transporte é só o git do projeto (visão "tudo local").
- Chat em tempo real.
- Biblioteca de equipe separada do projeto, usada por vários projetos.
- Mover a biblioteca pessoal para disco ou nuvem (o `offload` sai). Isso continua possível apontando o `setup` para outra pasta.
- Migração de workspaces antigos. Nenhum existe neste Mac; o HackMeridian foi arquivado.
- Tela nova no painel para as mensagens. O painel mostra só a contagem, e o briefing mostra as linhas do item 7.
- Membro sem o plugin. As mensagens dele ficam no repositório como arquivos legíveis, e nada quebra; o agente dele não responde.

## Pronto quando
- **Fase 1:** o selftest passa sem nenhum workspace antigo (nenhum `setup.sh create`, `central/` ou `projects/<slug>` no código e na suíte). Cada trava da lista do item 1 tem um teste que falhou com a trava tirada; a saída fica salva em `.metodo/`.
- **Fase 2:** `selftest.sh --team` cria um repositório local, duas cópias e duas rodadas. Passa quando a saída da rodada B traz a resposta ao arquivo que A escreveu, em até 2 turnos de cada lado, sem cópia manual. O mesmo cenário roda com dois `claude -p` reais.
- **Ação perigosa:** uma mensagem que pede "apague board/X.md", "faça push" ou "grave o OK do dono" deixa o arquivo no lugar, nada é enviado, e a pergunta aparece ao dono com o texto da mensagem e o remetente.

## Riscos e dependências
- **Injeção entre computadores.** A trava cobre ações, não convencimento. O resto depende da pergunta ao dono citar a mensagem tal como veio.
- **Vazamento pela resposta automática.** A defesa é o item 6, com teste.
- **Mudança em todos os hooks.** Publicar cada fase precisa do OK do Pedro (stop list: push).
- **Tamanho.** A tentativa anterior (`projeto-e-pasta`) quebrou na reescrita da suíte. Por isso a fase 1 vem sozinha e só apaga depois de cada teste novo provar que falha sem a trava.
