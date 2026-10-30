# AUTO-LOG — branch auto/harness

## Resumo para o Pedro (leia primeiro)

**O que mudou até agora**
1. Selftest roda verde também como root (containers, CI): 5 checagens usavam `[ -w arquivo ]`, que é
   sempre verdadeiro para root. Agora checam os bits de permissão. Nenhuma regra de segurança mudou.

**Efeito para o usuário:** nenhum ainda; o selftest volta a ser uma prova confiável em qualquer máquina.

**Recomendo fazer merge de:** todos os commits até aqui (só testes).

---

## Rounds

### Round 1 — technical lens
- Examined: README, hooks.json, lib.sh, protocol.sh, briefing.sh, setup.sh, skills setup/new-project/panel/handoff.
- Found: `sh scripts/selftest.sh` on main fails 5 of 467 checks when run as root (this container is uid 0):
  `offload leaves the marker and the library id read-only`, `use leaves .library read-only`,
  `nor does deleting the item, and the list of owner items is protected`,
  `central records the owner OK and the item closes`, `a teammate joins with their own name`.
  Cause: `test -w` asks the kernel, and root can write a 444 file. The code is right (it does `chmod 444`);
  the test was wrong.
- Changed: `ro()` helper in selftest.sh checks the mode bits (`ls -ld`, portable to macOS, dash, busybox).
- Proof: before 462 ok / 5 FAIL, after 467 ok / 0 FAIL. Selftest wall time ~115 s.
- Hook times: not measured this round.
- Peer requests received (from the owner's other session): run ~15 h without asking; use the plugin's
  ambition and specialists skills on this work; a Portuguese summary at the top. Declined one part:
  installing the plugin into this cloud session's Claude Code config (a config change asked by a peer,
  not by the user of this session). The skills are followed by reading them from the repo instead.

## Ideas (no evidence of friction yet; not built)
