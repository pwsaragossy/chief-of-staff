# Auditoria adversarial de `origin/auto/harness`

Escopo: os 40 commits de `main..origin/auto/harness` (até `d5ecc48`, buscado de novo ao final, sem commits novos).
Branch da auditoria: `audit/harness`, criado a partir de `32e582a`. Todos os testes rodaram no macOS (bash 3.2 como
`/bin/sh`, disco APFS que ignora maiúsculas). A suíte do `auto/harness` passou inteira no macOS antes da auditoria
(502 de 502), então nenhuma falha era específica do macOS. Com as correções, a suíte tem 506 de 506. As correções aplicadas
por cima do `d5ecc48` (o topo atual do `auto/harness`) passam 510 de 510.

## Achados

**1. Um OK do dono escrito com o "K" do símbolo Kelvin era aceito como verdadeiro** (commit `c902c21`). No disco do Mac,
um arquivo chamado `.owner-oK`, com o caractere Kelvin (U+212A) no lugar do k, abre como se fosse `.owner-ok`. O git, os
filtros do join e do pull e o guard de escrita comparam bytes, então nenhum deles reconhece o nome. Efeito para o
usuário: um colega podia commitar esse arquivo num projeto compartilhado, e no Mac de quem puxava o `track.sh` aceitava
o OK falso e fechava um item que só o dono pode fechar. O próprio agente também podia escrever esse arquivo, mesmo num
workspace pessoal, porque o guard deixava passar tanto o Write quanto o Bash. O furo também existe no `main`, e a
promessa do `c7bd34a` ("um OK forjado continua não confiável") não valia para esse nome. Correção: o guard converte o
caractere antes de comparar, e o `track.sh` tira do caminho, com o nome `.from-team`, qualquer arquivo do dono cujo
nome no disco não seja exatamente o esperado. Teste: "an owner OK named with a Kelvin K, committed by a teammate or
written here, is not trusted" e "the guard blocks a write to a protected name spelled with a Kelvin K or a long s".
Os dois falhavam e agora passam.

**2. Um marcador `.chief-of-ſtaff` (com "s" longo) passava pelo join e mudava a raiz do workspace** (commit `c902c21`).
O Mac abre esse nome como `.chief-of-staff`. O join aceitava o repositório do time com esse arquivo dentro de um projeto,
e o projeto virava um workspace separado, sem o gate da trilha e sem o aviso antes do push. O mesmo furo existe no `main`,
e as notas do `2c4e049` diziam que o join recusa esse caso, o que não era verdade para essa grafia. Correção: o `cos_root`
(e o `panel.py`, que faz a mesma busca) só aceita o marcador com o nome exato. Teste: "a marker named with a long s or a
ligature, beside a name with a line break, does not move the workspace root". Falhava e agora passa.

**3. O join e o pull deixavam entrar `.mcp.json`, o marcador e arquivos do dono escritos com ligaduras ou "s" longo**
(commit `f31d38b`). O disco do Mac faz a dobra Unicode completa, então as ligaduras ﬀ ﬁ ﬂ ﬃ ﬄ ﬅ ﬆ abrem como as letras
que representam. Assim, `.mcp.jſon` abre como `.mcp.json`, o arquivo que liga servidores MCP que rodam comandos, e
`.chief-of-staﬀ` abre como o marcador. Efeito para o usuário: um colega fazia chegar por join ou por `sync.sh pull` um
arquivo que roda código ou desliga gates, apesar de os dois dizerem que recusam isso. Correção: uma função `cos_fold`
na lib.sh troca os nove caracteres cuja dobra vira só letras ASCII pelas letras, e o guard, o join e o pull comparam
depois dela. Teste: o caso do join ganhou `.chief-of-staﬀ`, `.mcp.jſon` e `.owner-oK`, e há um caso novo para o pull:
"a teammate's .mcp.json spelled with a long s ... is not pulled either". Os dois falhavam e agora passam.

**4. A minha primeira correção era burlável por um arquivo com quebra de linha no nome** (commit `f31d38b`). Na primeira
versão do achado 1, a checagem do nome exato usava `ls | grep`. Um arquivo isca chamado `x` + quebra de linha +
`.owner-ok` imprimia uma linha `.owner-ok`, e o OK falso voltava a ser aceito; o mesmo truque fazia a raiz mudar de
novo. Correção: a checagem passou a usar `find -name`, que compara bytes, e o arquivo deixou de receber `chmod` através de
um link simbólico. Teste: a isca entrou nos dois testes dos achados 1 e 2. Falhava sobre `c902c21` e agora passa.

**5. Uma pasta com o nome protegido respondia por si mesma** (commit `f6ff5ab`). O `find` também testa a pasta de onde a
busca começa. Um projeto numa pasta chamada `.owner-ok`, contendo `.owner-oK`, passava como "o nome exato existe", e o OK
falso era aceito. Uma pasta `.chief-of-staff` contendo `.chief-of-ſtaff` virava raiz. Correção: `-mindepth 1`. Teste: os
dois casos entraram nos testes dos achados 1 e 2. Falhavam sobre `f31d38b` e agora passam.

## O que ataquei e resistiu

A aprovação automática dos comandos de leitura do plugin aprova só leituras. Testei metacaracteres, `$(...)`, crases,
redirecionamentos, variáveis antes do comando, segunda chave `command`, escapes JSON, quebra de linha, aspas
desbalanceadas, links simbólicos que saem do workspace, `..`, caminhos relativos, caminhos com acento, um nome igual ao
do workspace só com outra caixa de letra, a sintaxe do zsh (`=palavra`) e o `--lib` antes do subcomando. Nenhum desses
casos foi aprovado. Os subcomandos aprovados não rodam o comando do `check:` da trilha. As únicas escritas são o cache do
índice da biblioteca e a remoção de arquivos do dono forjados, e os hooks já fazem as duas coisas sozinhos. O
`track.sh decide` (`f4a4932`) só acrescenta uma linha que não substitui nada, porque o `|` é proibido e então não dá para
forjar um `replaces:`. Ele não abre nada que um `echo >>` já não abrisse no `main`, uma lacuna que o AUTO-LOG já registra.
As mudanças do gate de DECISIONS.md (`fc9aa60`, `4c00486`) foram desfeitas por `4b07b0e`, e o diff líquido não mexe no
gate dos especialistas. O `cos_broken` (`dba4dbc`) limpa o vermelho quando uma sessão revisada de outra pessoa termina.
Isso enfraquece o sinal do painel em relação ao `main`, mas é uma escolha documentada e não deixa entregável nenhum
passar pelo gate, então não conto como furo. O `GIT_CONFIG_COUNT` com valor inválido e o repositório falso commitado
por um colega já tinham testes e se mantiveram.

## Veredito

Todo o `auto/harness` pode ir para o `main`, mas só junto com os três commits desta auditoria (`c902c21`, `f31d38b` e
`f6ff5ab`). Os furos 1 e 2 também existem no `main`, então o merge conjunto deixa o `main` mais seguro do que está hoje.

- Seguros como estão: os commits de texto, mensagens, README, templates, skills e painel (`480cbeb`, `7b8af46`,
  `1907712`, `25c6db8`, `9daa4e6`, `e1db128`, `9dd72d2`, `047e099`, `ae39f30`, `2d7cbe2`, `d4ea43c`, `9804b95`,
  `2fd2315`, `776ef73`, `10a7973`, `9da7121`, `9248b4e`, `e80a7af`, `d5ecc48`), os commits só de AUTO-LOG, `dba4dbc`,
  `f4a4932` e o trio `4c00486`/`fc9aa60`/`4b07b0e`, que se anula.
- Seguros só com as correções da auditoria: a aprovação automática e a proteção contra OK forjado (`1b696a0`, `64f2b60`,
  `c7bd34a`), as mudanças de raiz, marcador e join (`6201eb8`, `10087e7`, `7fea9b4`, `2c4e049`) e `6161586`. Elas
  prometem recusar OK forjado e marcador aninhado, e no Mac essas promessas só valem com `c902c21`, `f31d38b` e `f6ff5ab`.
