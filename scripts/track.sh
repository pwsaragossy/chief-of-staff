#!/bin/sh
# Track gates. A project's TRACK.md lists the minimum deliverables per stage (templates/tracks/).
#   check  <project_dir>  one problem per line, exit 1 if any (the Stop hook blocks on these)
#   brief  <project_dir>  one line for the session briefing: stage, what is open now, what waits
#   status <project_dir>  "stage<US>stages<US>closed<US>total<US>delivery<US>delivered<US>baseline<US>baseline_delivery" for health.sh
#   items  <project_dir>  the map for the panel: S<US>n<US>name and I<US>stage<US>state<US>id<US>card<US>needs<US>deliverable
#   baseline <project_dir>  records the item count when the project opens (new-project runs it once)
# delivery: N in the front matter is the stage that delivers the original request (default: the last stage).
# Item line: - [ ] id | deliverable | card: role | needs: a, b | evidence: path   ([x] done, [-] n/a + why:)
# target: and check: (front matter) are the hard number and the command that measures it (exit 0 = met, last
#   output line = the value, or "none (why)"). The owner approves both once (track.sh ok <p> check), which
#   freezes them; the owner's delivery OK (track.sh ok <p> delivery, or an owner item in the delivery stage)
#   runs the frozen check. verify <project_dir> runs it any time and keeps the result in .check-runs.
# "| owner: ok" marks an item that closes only with the owner's OK, recorded in <project>/.owner-ok by
#   track.sh ok <project_dir> <id> <the owner's words>   (central only; the hook asks the owner to approve it)
# No TRACK.md: silent, exit 0 (old projects keep working).
. "$(dirname "$0")/lib.sh"

cmd=$1; dir=$2; t="$dir/TRACK.md"
if [ ! -f "$t" ]; then # a project made from the template names TRACK.md in its CLAUDE.md: deleting the file must not open the gate
  [ "$cmd" = check ] && grep -qs 'TRACK.md' "$dir/CLAUDE.md" 2>/dev/null && { echo "TRACK.md is missing, but this project's CLAUDE.md requires it: restore it (git) instead of deleting it"; exit 1; }
  exit 0
fi
US=$(printf '\037')
rawstage=$(fm_get "$t" stage); cur=$rawstage; case $cur in ''|*[!0-9]*) cur=1 ;; esac
state=$(fm_get "$dir/STATE.md" status | tr 'A-Z' 'a-z')

# S<US>stage<US>name  and  I<US>stage<US>mark<US>id<US>card<US>needs<US>evidence<US>why<US>owner
rows=$(awk '
  { sub(/\r$/, "") }
  /^## Stage [0-9]+:/ { s = $3; sub(/:$/, "", s); n = $0; sub(/^## Stage [0-9]+: */, "", n); print "S\037" s "\037" n; next }
  /^- \[.\] / {
    m = substr($0, 4, 1); k = split(substr($0, 7), f, / \| /)
    id = f[1]; gsub(/^ +| +$/, "", id); card = needs = ev = why = own = ""
    for (j = 2; j <= k; j++) { v = f[j]; gsub(/^ +| +$|`/, "", v)
      if (v ~ /^card:/) { card = v; sub(/^card: */, "", card) }
      else if (v ~ /^needs:/) { needs = v; sub(/^needs: */, "", needs) }
      else if (v ~ /^evidence:/) { ev = v; sub(/^evidence: */, "", ev) }
      else if (v ~ /^why:/) { why = v; sub(/^why: */, "", why) }
      else if (v ~ /^owner:/) { own = v; sub(/^owner: */, "", own) } }
    print "I\037" (s == "" ? 0 : s) "\037" m "\037" id "\037" card "\037" needs "\037" ev "\037" why "\037" own
  }' "$t")

mark_of() { printf '%s\n' "$rows" | awk -F "$US" -v i="$1" '$1 == "I" && $4 == i { print ($3 == " " ? "o" : $3); exit }'; }
open_needs() { # ids in $1 (comma list) that are not closed
  for n in $(printf '%s' "$1" | tr ',' ' '); do
    [ "$n" = - ] && continue
    case $(mark_of "$n") in x|-) ;; *) printf '%s, ' "$n" ;; esac
  done
}
stages=$(printf '%s\n' "$rows" | grep -c "^S$US")
sname=$(printf '%s\n' "$rows" | awk -F "$US" -v c="$cur" '$1 == "S" && $2 == c { print $3; exit }')
rawdel=$(fm_get "$t" delivery); del=$rawdel; case $del in ''|*[!0-9]*) del=$stages ;; esac
# items of stages 1..delivery still open; empty = the original request is delivered
undelivered=$(printf '%s\n' "$rows" | awk -F "$US" -v d="$del" '$1 == "I" && $2 <= d && $3 != "x" && $3 != "-" { print $4 }')

# target and check: only in a TRACK.md that has the target: key (tracks from before v0.3 are left as they were).
# Once the project opened with the key (a mark in .owner-items) or the owner approved a check, deleting the key
# does not switch the gate off.
TB=$(printf '\t')
# a shared workspace: an owner file that git tracks, in any letter case, came from the team repo (a clone, a
# hand commit), not from this computer's owner (the plugin never commits them: protocol.sh push skip). It is
# moved aside at once, so untracking it later does not make its content trusted.
OKF="$dir/.owner-ok"; OIF="$dir/.owner-items"; forged=
# git reads the workspace's own repository, named outright: a folder of the project laid out like a repository
# (a teammate can commit one) is never taken for it. If git cannot answer, nothing of the owner's is trusted
wroot=$(cos_root "$dir"); wg() { git --git-dir="$wroot/.git" --work-tree="$wroot" -C "$dir" "$@"; }
if cos_anyshared "$dir"; then
  _l=$(wg ls-files -- ':(icase).owner-ok' ':(icase).owner-items' 2>/dev/null) || { OKF=/nonexistent/.owner-ok; OIF=/nonexistent/.owner-items; }
  for _f in $_l; do
    forged="$forged $_f"; [ -e "$dir/$_f" ] && { [ -L "$dir/$_f" ] || chmod u+w "$dir/$_f"; mv -f "$dir/$_f" "$dir/$_f.from-team"; } 2>/dev/null
  done
  case $(printf '%s' "$forged" | tr 'A-Z' 'a-z') in *.owner-ok*) OKF=/nonexistent/.owner-ok ;; esac
  case $(printf '%s' "$forged" | tr 'A-Z' 'a-z') in *.owner-items*) OIF=/nonexistent/.owner-items ;; esac
fi
has_tc=; awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { exit } f && /^target:/ { h = 1 } END { exit !h }' "$t" && has_tc=1
grep -qx 'target:' "$OIF" 2>/dev/null && has_tc=1
grep -q '^check	' "$OKF" 2>/dev/null && has_tc=1
tgt=$(fm_get "$t" target | tr -d '\000-\037'); chk=$(fm_get "$t" check | tr -d '\000-\037')
case $chk in ''|none|none[!A-Za-z0-9_.-]*) runnable= ;; *) runnable=1 ;; esac
# tcfiles: the project files the check names, and the files those name in turn (a helper script)
# ponytail: what the check reaches without naming it (a test suite run by npm or pytest, data) is not frozen
tcfiles() { set -f; _seen=; _q=$chk
  while [ -n "$_q" ]; do _n=
    for _w in $(printf '%s\n' "$_q" | tr -c 'A-Za-z0-9._/-' '\n' | sort -u); do _w=${_w#./}
      case $_w in /*|*..*|.owner-ok|.owner-items|.check-runs|TRACK.md|STATE.md) continue ;; esac
      [ -f "$dir/$_w" ] || continue
      case " $_seen " in *" $_w "*) continue ;; esac
      _seen="$_seen $_w"; _n="$_n $(cat "$dir/$_w" 2>/dev/null)"
    done; _q=$_n
  done; set +f; printf '%s' "${_seen# }"; }
hsum() { if command -v shasum > /dev/null 2>&1; then shasum -a 256 | cut -c1-64
  elif command -v sha256sum > /dev/null 2>&1; then sha256sum | cut -c1-64; else cksum | tr -d ' \t'; fi; }
# the frozen sum covers the target, the command and the files above
tcsum() { { printf '%s\n%s\n' "$tgt" "$chk"; set -f; for _f in $(tcfiles); do printf '%s\n' "$_f"; cat "$dir/$_f"; done; set +f; } 2>/dev/null | hsum; }
frozen() { awk -F '\t' '$1 == "check" { for (i = 4; i <= NF; i++) if ($i ~ /^freeze=/) { f = substr($i, 8); d = $2 } } END { if (f != "") print f "\t" d }' "$OKF" 2>/dev/null; }
# teamsent: a file of this project (any letter case) changed by a commit after the owner approved the check that
# this computer did not make (sync.sh lists its own in cos-own): a pull, by sync.sh or by hand. The approval keeps
# the commit shared with the team repo then (head=), which a push never rewrites; local commits after it are
# folded by sync.sh push, and the folded one is listed as this computer's own
teamsent() { cos_anyshared "$dir" || return 1
  _g=$(wg rev-parse --absolute-git-dir 2>/dev/null) || { echo "its history (git cannot read this project)"; return 0; }; _p=$(wg rev-parse --show-prefix 2>/dev/null)
  _h=$(awk -F '\t' '$1 == "check" { h = ""; for (i = 4; i <= NF; i++) if ($i ~ /^head=/) h = substr($i, 6) } END { print h }' "$OKF" 2>/dev/null)
  [ -n "$_h" ] && wg merge-base --is-ancestor "$_h" HEAD 2>/dev/null || { echo "the history since the approval (its commit is gone)"; return 0; }
  for _c in $(wg rev-list "$_h..HEAD" -- ":(top,icase)$_p" 2>/dev/null); do
    grep -qx "$_c" "$_g/cos-own" 2>/dev/null && continue
    wg diff-tree --no-commit-id --name-only -r "$_c" -- ":(top,icase)$_p" | head -n 1; return 0
  done; return 1; }
# runcheck: rc (0 met, 1 not met, 124 timed out, other could not run) and val (the last output line)
runcheck() {
  _o=$(mktemp); _lim=${COS_CHECK_TIMEOUT:-120}; case $_lim in ''|*[!0-9]*) _lim=120 ;; esac
  # the check runs in its own process group, so the timeout stops what it started too (a pipe, a server).
  # setsid where it exists (Linux: dash refuses set -m without a tty, from a hook), set -m otherwise (macOS)
  if command -v setsid > /dev/null 2>&1; then ( cd "$dir" && exec setsid sh -c "$chk" ) > "$_o" 2>&1 < /dev/null & _p=$!
  else set -m; ( cd "$dir" && exec sh -c "$chk" ) > "$_o" 2>&1 < /dev/null & _p=$!; set +m; fi
  ( trap 'kill $_s 2>/dev/null; exit 0' TERM; sleep "$_lim" & _s=$!; wait $_s; { kill -TERM -"$_p" || kill "$_p"; } 2>/dev/null && : > "$_o.to" ) > /dev/null 2>&1 & _k=$!
  { wait "$_p"; rc=$?; kill "$_k"; wait "$_k"; } 2>/dev/null   # waiting on the stopped timer keeps the shell's "Terminated" notice quiet
  _to=; [ -f "$_o.to" ] && _to=1
  val=$(tr -cd '[:print:]\n' < "$_o" | grep . | tail -n 1 | cut -c1-80); rm -f "$_o" "$_o.to"
  if [ -n "$_to" ]; then rc=124; res="timed out after $_lim s"
  else case $rc in 0) res="pass $val" ;; 1) res="fail $val" ;; *) res="could not run (exit $rc): $val" ;; esac; [ "$rc" = 124 ] && rc=125; fi
}
# the delivery waits on the owner's OK with the check result too (a measured target is part of "delivered")
# a pass counts only for the target and check the owner approved last, and only while they are unchanged;
# 'none (why)' needs no run, only the owner's approval of it
tcpending=
if [ -n "$has_tc" ]; then fzs=$(frozen); fzs=${fzs%%"$TB"*}
  if [ -z "$fzs" ] || [ "$fzs" != "$(tcsum)" ]; then tcpending=1
  elif [ -n "$runnable" ] && ! awk -F '\t' -v s="freeze=$fzs" '$1 != "check" { c = 0; z = 0; for (i = 4; i <= NF; i++) { if ($i ~ /^check=(pass|waived)/) c = 1; if ($i == s) z = 1 } if (c && z) f = 1 } END { exit !f }' "$OKF" 2>/dev/null; then tcpending=1; fi
fi
mine() { # a shared workspace: a project's check runs only on its own member's computer
  _r=$(cos_root "$dir"); _m=
  if [ -n "$_r" ] && cos_shared "$_r"; then _m=$(cos_member "$_r")
    [ -n "$_m" ] && [ "$(fm_get "$dir/STATE.md" member)" = "$_m" ] || return 1
  fi
}

# cites FILE [PREFIX]: each [[id]] in FILE must be a note of the project's library that is not retired.
# A personal project may also cite a team's note; a team project cites only its own library (no leak).
cites() {
  _r=$(cos_root "$dir") || return 0
  _ln=$(cos_libname "$_r" "$dir"); _l=$(cos_libpath "$_r" "$_ln") || {
    [ "$_ln" = personal ] && return 0   # offline personal library: the briefing says so; nothing to compare against
    echo "${2:-}$(basename "$1"): its sources cannot be checked, the team library '$_ln' is not reachable (library.sh where)"; return 0; }
  grep -o '\[\[[^]|#]*' "$1" 2>/dev/null | sed 's/^\[\[//' | sort -u | while IFS= read -r _i; do
    _n="$_l/notes/$_i.md"; _o=
    [ -f "$_n" ] || _o=$(cos_libs "$_r" | while IFS="$(printf '\t')" read -r _a _p; do [ -f "$_p/notes/$_i.md" ] && { printf '%s\t%s\n' "$_a" "$_p"; break; }; done)
    if [ -n "$_o" ] && [ "$_ln" != personal ]; then
      echo "${2:-}$(basename "$1") cites [[$_i]] from the library '${_o%%	*}': this project shares with the team library '$_ln', so its work cannot rest on another library's note. Use a note of '$_ln', or the owner agrees to rewrite the fact there"; continue
    fi
    [ -n "$_o" ] && _n="${_o#*	}/notes/$_i.md"
    if [ ! -f "$_n" ]; then echo "${2:-}$(basename "$1") cites [[$_i]], which is not a note in the library ($_l/notes)"
    elif [ "$(fm_get "$_n" status)" = retired ]; then _s=$(fm_get "$_n" superseded_by)
      echo "${2:-}$(basename "$1") cites [[$_i]], which is retired${_s:+: cite [[$_s]] instead}"
    fi
  done
}

check() {
  case $rawstage in ''|*[!0-9]*|0) echo "stage: in the TRACK.md front matter must be a whole number from 1 to $stages (found '$rawstage')" ;; esac
  [ "$cur" -gt "$stages" ] && echo "stage: $cur in TRACK.md, but the track has $stages stages"
  # lines that look like an item, a stage or a comment but would not be parsed: they would silently drop out of the gate
  awk '{ sub(/\r$/, "") }
    /<!--|-->/ { print "line " NR ": HTML comments hide items from the gate; delete the item with a [-] and why: instead"; next }
    /^[ \t]*[-*+][ \t]*\[.?\]/ && !/^- \[.\] / { print "line " NR ": not a valid item (write exactly: - [ ] id | deliverable | card: role | needs: ids | evidence:)" }
    /^#+[ \t]*[Ss]tage/ && !/^## Stage [0-9]+:/ { print "line " NR ": not a valid stage header (write exactly: ## Stage N: Name)" }' "$t"
  # structure: sequential stages, unique ids, a role on every item, needs that exist, point back and have no loop, one proof file per item
  printf '%s\n' "$rows" | awk -F "$US" '
    $1 == "S" { ns++; if ($2 != ns) print "stage headers must be numbered 1, 2, 3 in order: found Stage " $2 " where Stage " ns " was expected" }
    $1 == "I" { n++; id[n] = $4; nd[n] = $6
      if ($2 == 0) print "item " $4 " is before the first stage header"
      if ($4 !~ /^[A-Za-z0-9_-]+$/) print "item id \"" $4 "\" must use only letters, digits, - and _"
      else if ($4 in at) print "item id " $4 " appears twice"
      else { at[$4] = n; st[$4] = $2 }
      if ($5 == "") print $4 " has no card: (the role that makes it)"
      if ($3 == "x" && $7 != "") { if ($7 in ev) print $4 " and " ev[$7] " share the proof file " $7 ": each item needs its own"; else ev[$7] = $4 } }
    END { for (i = 1; i <= n; i++) { k = split(nd[i], a, /, */)
        for (j = 1; j <= k; j++) { m = a[j]; if (m == "" || m == "-") continue
          if (m == id[i]) print id[i] " needs itself"
          else if (!(m in at)) print id[i] " needs " m ", which is not an item of the track"
          else if (st[m] > st[id[i]]) print id[i] " (stage " st[id[i]] ") needs " m " from the later stage " st[m] ": needs must point back" } }
      do { ch = 0; for (i = 1; i <= n; i++) if (!dn[i]) { ok = 1; k = split(nd[i], a, /, */)
          for (j = 1; j <= k; j++) if ((a[j] in at) && !dn[at[a[j]]]) ok = 0
          if (ok) { dn[i] = 1; ch = 1 } } } while (ch)
      for (i = 1; i <= n; i++) if (!dn[i]) l = l (l ? ", " : "") id[i]
      if (l != "") print "these items wait on each other in a loop, so none can close: " l }'
  # an item that needed the owner's OK at opening still needs it: removing the mark does not skip the owner
  # (.owner-items, read-only and written once by baseline: TRACK.md itself is the agent's to edit)
  # a project opened with a baseline always has the list: without it the owner gate would be off (fail closed)
  for _f in $forged; do echo "$_f came from the team repo (git tracks it), so this computer does not trust it; it was moved aside to $_f.from-team: remove it from git (git rm --cached $_f) and have the owner give their OKs again"; done
  [ -n "$(fm_get "$t" baseline)" ] && [ ! -r "$OIF" ] &&
    echo "the list of owner items is missing (.owner-items, written when the project opened): restore it from git or ask the owner"
  for b in $(cat "$OIF" 2>/dev/null); do [ "$b" = target: ] && continue
    printf '%s\n' "$rows" | awk -F "$US" -v i="$b" '$1 == "I" && $4 == i && $9 == "ok" { f = 1 } END { exit !f }' ||
      echo "$b needed the owner's OK when the project opened (.owner-items): put back its line with | owner: ok"
  done
  # the delivery line: the planned end of the original request
  case $rawdel in ''|[1-9]|[1-9][0-9]) [ "$del" -le "$stages" ] || echo "delivery: $del in TRACK.md, but the track has $stages stages" ;;
    *) echo "delivery: in the TRACK.md front matter must be a stage number from 1 to $stages (found '$rawdel')" ;; esac
  if [ -z "$undelivered" ] && [ "$stages" -gt 0 ]; then
    case $state in
      delivered|done) [ -s "$dir/DELIVERY.md" ] || echo "STATE.md status is $state, but DELIVERY.md is missing or empty: write what the owner asked, what was delivered and the proof files" ;;
      *) echo "stage $del is the delivery line and every item up to it is closed: write DELIVERY.md (what the owner asked, what was delivered, the proof files) and set STATE.md status: delivered. More work goes on the project card as a proposal for the owner." ;;
    esac
  elif [ "$state" = delivered ]; then
    echo "STATE.md status is delivered, but these items up to the delivery line (stage $del) are open: $(printf '%s' "$undelivered" | tr '\n' ' ')"
  fi
  # what the delivery rests on: a Sources section, and every [[note]] it or a proof file cites must be a live library note
  if [ -s "$dir/DELIVERY.md" ]; then
    grep -Eq '^(## Sources|Sources:)' "$dir/DELIVERY.md" || echo "DELIVERY.md needs a '## Sources' section: the library notes ([[id]]) and files it rests on, or 'Sources: none (searched: <terms>)'"
    cites "$dir/DELIVERY.md"
  fi
  printf '%s\n' "$rows" | while IFS=$US read -r kind s m id card needs ev why own; do
    [ "$kind" = I ] && [ "$m" = x ] && [ -n "$ev" ] && [ -f "$dir/$ev" ] && cites "$dir/$ev" "$id: "
  done
  if [ -n "$has_tc" ] && [ "$cur" -ge 2 ]; then
    if [ -z "$tgt" ]; then echo "stage 1 is behind, but target: is empty in TRACK.md: write the number the work must reach, taken from the criteria, the metric or the raw material"
    elif [ -z "$chk" ]; then echo "check: is empty in TRACK.md: write the command that measures the target (exit 0 when met, the value on its last line), or 'none (why)'"
    else fz=$(frozen)
      if [ -z "$fz" ]; then echo "target and check are not approved by the owner yet: put them on the project card in plain words (what is measured, the number, the command); central records the answer with track.sh ok <project> check"
      elif [ "${fz%%"$TB"*}" != "$(tcsum)" ]; then echo "target or check changed since the owner approved them (${fz#*"$TB"}), or a file the check runs did: put the new ones on the project card for the owner"; fi
    fi
  fi
  if [ -n "$tcpending" ] && [ -z "$undelivered" ] && [ "$stages" -gt 0 ]; then
    echo "the delivery is closed, but the owner's delivery OK with the check result is missing: put it on the project card; central records it with track.sh ok <project> delivery, which runs the check"
  fi
  # every stage needs a reviewer item, so no stage passes on the word of the agent that did the work
  printf '%s\n' "$rows" | awk -F "$US" '$1 == "S" { s[$2] = 1 } $1 == "I" && $5 == "reviewer" { r[$2] = 1 }
    END { for (k in s) if (!(k in r)) print "stage " k " has no item with card: reviewer" }'
  printf '%s\n' "$rows" | while IFS=$US read -r kind s m id card needs ev why own; do
    [ "$kind" = I ] || continue
    case $m in
      ' ') [ "$s" -lt "$cur" ] && echo "stage $s is behind the current stage $cur, but $id is open"
           [ "$state" = done ] && echo "STATE.md status is done, but $id is open" ;;
      x)   if [ -z "$ev" ]; then echo "$id is marked done without evidence: (the path of its proof file)"
           else case $ev in
             /*|*..*|TRACK.md|STATE.md|CLAUDE.md|./TRACK.md|./STATE.md|./CLAUDE.md) echo "$id: evidence $ev must be a proof file inside the project folder, not a control file or a path outside" ;;
             *) if [ ! -e "$dir/$ev" ] && [ -e "$dir/${ev%% *}" ]; then echo "$id: evidence must be the file path alone (found \"$ev\"); write evidence: ${ev%% *} and put any note in that file"
                elif [ ! -e "$dir/$ev" ]; then echo "$id is marked done, but its evidence $ev does not exist"
                elif [ -L "$dir/$ev" ] || [ ! -f "$dir/$ev" ]; then echo "$id: evidence $ev must be a regular file, not a folder or a link"
                elif [ ! -s "$dir/$ev" ]; then echo "$id: evidence $ev is empty"; fi ;;
           esac; fi
           [ "$own" = ok ] && ! grep -q "^$id$(printf '\t')" "$OKF" 2>/dev/null &&
             echo "$id closes only with the owner's OK: put the question on the project card; central records the answer with track.sh ok, which the owner approves"
           for n in $(printf '%s' "$needs" | tr ',' ' '); do
             [ "$n" = - ] && continue
             case $(mark_of "$n") in
               x|-) ;;
               '') ;;
               *) echo "$id is marked done, but it needs $n, which is open" ;;
             esac
           done ;;
      -)   [ -n "$why" ] || echo "$id is marked not applicable without why: (the reason)"
           [ "$card" = reviewer ] && echo "$id is a reviewer item and cannot be marked not applicable: the independent reviewer closes it with a verdict file that judges every [-] of the stage"
           [ "$own" = ok ] && echo "$id waits on the owner's OK and cannot be marked not applicable: only the owner drops it, through central" ;;
      *)   echo "$id has the mark [$m]: use [ ] open, [x] done or [-] not applicable" ;;
    esac
  done
}

case $cmd in
  check)
    p=$(check); [ -z "$p" ] && exit 0
    printf '%s\n' "$p"; exit 1 ;;
  status)
    printf '%s\n' "$rows" | awk -F "$US" -v c="$cur" -v n="$stages" -v dl="$del" -v ok="$([ -z "$undelivered" ] && [ "$stages" -gt 0 ] && [ -z "$tcpending" ] && echo 1 || echo 0)" -v b="$(fm_get "$t" baseline | tr -cd 0-9)" -v b0="$(fm_get "$t" baseline_delivery | tr -cd 0-9)" '
      $1 == "I" { t++; if ($3 == "x" || $3 == "-") d++ } END { printf "%s\037%s\037%d\037%d\037%s\037%s\037%s\037%s\n", c, n, d, t, dl, ok, b, b0 }' ;;
  items)
    # deliverable text comes straight from the item line (the rows above leave it out)
    printf '%s\n' "$rows" | awk -F "$US" 'NR != FNR { if (/^- \[.\] /) { sub(/\r$/, ""); k = split(substr($0, 7), f, / \| /); i = f[1]; gsub(/^ +| +$/, "", i); t = f[2]; gsub(/^ +| +$/, "", t); desc[i] = t }; next }
      $1 == "I" { m[$4] = $3 } { r[++nr] = $0 } END {
      for (i = 1; i <= nr; i++) { split(r[i], f, FS); if (f[1] == "S") { print r[i]; continue }
        if (f[1] != "I") continue
        st = f[3] == "x" ? "done" : f[3] == "-" ? "na" : "ready"
        if (st == "ready") { k = split(f[6], a, /, */); for (j = 1; j <= k; j++) if (a[j] != "-" && a[j] != "" && m[a[j]] != "x" && m[a[j]] != "-") st = "blocked" }
        print "I\037" f[2] "\037" st "\037" f[4] "\037" f[5] "\037" f[6] "\037" desc[f[4]] } }' - "$t"
    ;;
  ok)
    # the owner's OK on an item: only central records it, and the PreToolUse hook makes the owner approve the command
    case ${CLAUDE_PROJECT_DIR:-$PWD} in */central|*/central/*) ;; *) echo "track.sh ok: only central records the owner's OK" >&2; exit 1 ;; esac
    id=${3:-}; shift 3 2>/dev/null || { echo "usage: track.sh ok <project_dir> <item|check|delivery> <the owner's words>" >&2; exit 2; }
    case $id in
      check) [ -n "$has_tc" ] && [ -n "$tgt" ] && [ -n "$chk" ] || { echo "track.sh ok: write target: and check: in TRACK.md first" >&2; exit 1; } ;;
      delivery) [ -n "$runnable" ] || { echo "track.sh ok: the delivery OK runs the check, and TRACK.md has none to run" >&2; exit 1; } ;;
      *) printf '%s\n' "$rows" | awk -F "$US" -v i="$id" '$1 == "I" && $4 == i && $9 == "ok" { f = 1 } END { exit !f }' ||
           { echo "track.sh ok: $id is not an item of this track marked owner: ok" >&2; exit 1; } ;;
    esac
    # a shared workspace: only the project's own member gives its OK
    case $(printf '%s' "$forged" | tr 'A-Z' 'a-z') in *.owner-ok*) echo "track.sh ok: .owner-ok came from the team repo (git tracks it): remove it from git first (git rm --cached)" >&2; exit 1 ;; esac
    mine || { echo "track.sh ok: this project is $(fm_get "$dir/STATE.md" member)'s; only their central records its OK" >&2; exit 1; }
    w=$(printf '%s' "$*" | tr -d '\000-\037' | cut -c1-300); x=
    if [ "$id" = check ]; then x="${TB}freeze=$(tcsum)$({ wg merge-base HEAD '@{u}' || wg rev-parse -q --verify HEAD; } 2>/dev/null | head -n 1 | sed "s/^/$TB""head=/")"; _fl=$(tcfiles)
      echo "the owner approves the target '$tgt' and the command '$chk'${_fl:+, frozen with its files: $_fl}"
    elif [ -n "$runnable" ] && { [ "$id" = delivery ] || [ "$(printf '%s\n' "$rows" | awk -F "$US" -v i="$id" '$1 == "I" && $4 == i { print $2 }')" -ge "$del" ]; }; then
      # the delivery OK: the frozen check runs now, in front of the owner; a failing one needs the owner's waiver
      fz=$(frozen)
      [ -n "$fz" ] || { echo "track.sh ok: the owner never approved target and check: record track.sh ok <project> check first" >&2; exit 1; }
      [ "${fz%%"$TB"*}" = "$(tcsum)" ] || { echo "track.sh ok: target or check changed since the owner approved them: approve the new ones first (track.sh ok <project> check)" >&2; exit 1; }
      _s=$(teamsent) && { echo "track.sh ok: a teammate changed $_s in this project after the owner approved the check: the owner reads the change and approves again (track.sh ok <project> check)" >&2; exit 1; }
      runcheck; printf '%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$rc" "$val" >> "$dir/.check-runs"
      if [ "$rc" = 0 ]; then x="${TB}check=$res${TB}freeze=${fz%%"$TB"*}"
      else case $(printf '%s' "$w" | tr 'A-Z' 'a-z') in
        'waive:'*|'waive '*) x="${TB}check=waived $res${TB}freeze=${fz%%"$TB"*}"; echo "WAIVED: the check fails ($res) and the owner accepted it" ;;
        *) echo "track.sh ok: the check fails: $([ "$rc" = 1 ] && echo "$val" || echo "$res") (target: $tgt). The owner can still accept it: record 'waive: <the reason>'." >&2; exit 1 ;; esac
      fi
    fi
    o="$dir/.owner-ok"; [ -f "$o" ] && chmod u+w "$o"
    printf '%s\t%s\t%s%s%s\n' "$id" "$(date '+%F %H:%M')" "${_m:+$_m: }" "$w" "$x" >> "$o"; chmod 444 "$o"
    echo "recorded the owner's OK on $id${x:+ (${x#"$TB"})}" ;;
  verify)
    [ -n "$runnable" ] || { echo "check: nothing to run (TRACK.md check: ${chk:-empty})"; exit 0; }
    mine || { echo "verify: this project is $(fm_get "$dir/STATE.md" member)'s; only their own computer runs its check" >&2; exit 1; }
    # only a command the owner approved on this computer runs: .owner-ok never syncs, TRACK.md and STATE.md do
    fz=$(frozen); [ -n "$fz" ] && [ "${fz%%"$TB"*}" = "$(tcsum)" ] ||
      { echo "verify: the owner has not approved this check on this computer, or it changed since: nothing runs until central records it with track.sh ok <project> check" >&2; exit 1; }
    _s=$(teamsent) && { echo "verify: a teammate changed $_s in this project after the owner approved the check: nothing runs until the owner reads the change and approves again (track.sh ok <project> check)" >&2; exit 1; }
    runcheck; printf '%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$rc" "$val" >> "$dir/.check-runs"
    echo "check: $res$([ "$rc" = 1 ] && echo " (target: $tgt)")"; [ "$rc" = 0 ] ;;
  baseline)
    # once: a second run would reset the yardstick that shows items removed or the delivery line moved
    [ -n "$(fm_get "$t" baseline)" ] && { echo "baseline is already recorded in TRACK.md; it is not rewritten" >&2; exit 1; }
    [ -e "$dir/.owner-items" ] && { echo ".owner-items is already recorded; it is not rewritten" >&2; exit 1; }
    fm_set "$t" baseline "$(printf '%s\n' "$rows" | grep -c "^I$US")"
    fm_set "$t" baseline_delivery "$del"
    { printf '%s\n' "$rows" | awk -F "$US" '$1 == "I" && $9 == "ok" { print $4 }'; [ -n "$has_tc" ] && echo target:; } > "$dir/.owner-items"; chmod 444 "$dir/.owner-items" ;;
  brief)
    if [ -n "$has_tc" ] && [ -n "$tgt" ]; then
      l=$(tail -n 1 "$dir/.check-runs" 2>/dev/null | cut -f2,3 | tr '\t' ' ' | sed 's/^0 /pass /; s/^1 /fail /' | tr -d '\000-\037')
      echo "Target: $tgt. Check: ${chk:-none}.${l:+ Last run: $l.} Run it with track.sh verify; the owner's delivery OK runs it too."
    fi
    now=; wait=
    while IFS=$US read -r kind s m id card needs ev why own; do
      [ "$kind" = I ] && [ "$s" = "$cur" ] && [ "$m" = ' ' ] || continue
      o=$(open_needs "$needs")
      if [ -z "$o" ]; then now="$now${now:+, }$id ($card${own:+, closes with the owner OK through the card})"; else wait="$wait${wait:+; }$id needs ${o%, }"; fi
    done <<EOF
$rows
EOF
    if [ -z "$undelivered" ]; then
      case $state in
        delivered|done) if [ -n "$tcpending" ]; then echo "Not delivered yet: the delivery waits on the owner. Put the delivery OK on the project card; central runs the check (track.sh ok <project> delivery)."
          else echo "Delivered: the original request is done (DELIVERY.md, delivery line at stage $del). New work is a proposal on the project card unless the owner approved it."; fi ;;
        *) echo "Delivery line reached (stage $del): before anything else, write DELIVERY.md and set STATE.md status: delivered.${tcpending:+ Then put the delivery OK of the owner on the project card: central runs the check (track.sh ok <project> delivery).}" ;;
      esac
      [ "$cur" -le "$del" ] && exit 0
    fi
    if [ -z "$now" ]; then now="none, the stage can pass its gate"; [ -n "$wait" ] && now="nothing until the prerequisites below are closed"; fi
    printf 'Track %s, stage %s of %s (%s), delivery line at stage %s. Open now: %s.%s\n' "$(fm_get "$t" track)" "$cur" "$stages" "$sname" "$del" \
      "$now" "${wait:+ Waiting on prerequisites: $wait.}" ;;
  *) echo "usage: track.sh check|brief|status|items|baseline|verify <project_dir> | track.sh ok <project_dir> <item|check|delivery> <words>" >&2; exit 2 ;;
esac
