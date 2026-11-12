#!/bin/sh
# Protocol gates. One script for four hook events, so the rules live in one place:
#   UserPromptSubmit  starts a new turn record and restates the protocol (every turn, survives compaction)
#   PostToolUse       records what the turn did: specialists (Agent), library lookups, web research, saves
#   PreToolUse        on WebSearch/WebFetch: blocked until the library was searched this turn;
#                     on Agent: blocked unless the brief names an existing role card (specialists/<role>.md)
#   SubagentStop      a specialist cannot finish without its never-skip checklist and its ## Versions
#   Stop              blocks the end of a substantive turn that skipped specialists or the reviewer, researched
#                     without saving to the library, or left the project's TRACK.md with a gate problem
#                     (track.sh check). One push per turn (stop_hook_active), then it lets go and logs a violation.
# Silent outside a workspace, unless the owner listed the folder in <plugin data>/everywhere (one absolute path per
# line, / for all): there the specialists gate runs with the plugin's own role cards (templates/specialists), and
# nothing of a workspace (library, board, track, rotation) is read or written. Every turn is logged to
# <workspace>/.protocol.log, or <plugin data>/protocol.log outside one (the adherence metric).
. "$(dirname "$0")/lib.sh"

in=$(cat)
DATA=${CLAUDE_PLUGIN_DATA:-$HOME/.cache/chief-of-staff}
# everywhere DIR -> the plugin's templates folder (it holds specialists/) when DIR is under a folder the owner listed
everywhere() { [ -f "$DATA/everywhere" ] || return 1
  while IFS= read -r _e; do _e=${_e%/}; case $_e in /*|'') case "$1/" in "$_e/"*) (cd "$(dirname "$0")/../templates" && pwd -P); return ;; esac ;; esac
  done < "$DATA/everywhere"; return 1; }
lite=
root=$(cos_root "${CLAUDE_PROJECT_DIR:-$PWD}") || { root=$(everywhere "${CLAUDE_PROJECT_DIR:-$PWD}") && lite=1; } || exit 0
# outside a workspace only the turn's specialists, research and files count: a Read, Grep or Glob names no library
[ -n "$lite" ] && case $in in *'"hook_event_name":"PostToolUse"'*) case $in in *'"tool_name":"Agent"'*|*'"tool_name":"Web'*|*'"tool_name":"Write"'*|*'"tool_name":"Edit"'*|*'"tool_name":"MultiEdit"'*) ;; *) exit 0 ;; esac ;; esac
# fast path, no fork: a Read, Grep or Glob only counts when it names a library (the turn searched it), so
# one that names none of the library folders written in the marker, nor library.sh, ends here
case $in in *'"hook_event_name":"PostToolUse"'*)
  case $in in *'"tool_name":"Read"'*|*'"tool_name":"Grep"'*|*'"tool_name":"Glob"'*)
    # the project's own knowledge/, or the owner's one library in <plugin data>/library
    case $in in *library.sh*|*"$root/knowledge"*) ;; *)
      hit=; _p=$(head -n 1 "$DATA/library" 2>/dev/null) && case $_p in /?*) case $in in *"$_p"*) hit=1 ;; esac ;; esac
      [ -n "$hit" ] || exit 0 ;; esac ;; esac ;; esac
rel=${CLAUDE_PROJECT_DIR:-$PWD}; rel=${rel#"$root"}; rel=${rel#/}
# the session's library and its state; lst != 0: offline or misconfigured (library.sh where)
if [ -n "$lite" ]; then lname=; lib=/nonexistent-library; lst=1
else lname=$(cos_libname "$root" "${CLAUDE_PROJECT_DIR:-$PWD}"); lib=$(cos_libpath "$root" "$lname"); lst=$?; fi
L="$(dirname "$0")/library.sh"; TAB=$(printf '\t')
# a path with .., symlinks and letter case resolved (macOS ignores case); "" when a part that does not exist yet holds ..
real() { realp "$1" | tr 'A-Z' 'a-z'; }
realp() { d=$1 r=; k=0
  while [ -L "$d" ] && [ $k -lt 20 ]; do t=$(readlink "$d"); case $t in /*) d=$t ;; *) d=${d%/*}/$t ;; esac; k=$((k+1)); done   # a symlinked file
  while [ ! -d "$d" ]; do r="/${d##*/}$r"; d=${d%/*}; [ -n "$d" ] || d=/; done
  case $r in */..|*/../*|*/.|*/./*) return 0 ;; esac; printf '%s%s' "$(cd "$d" && pwd -P)" "$r"; }
# the project this session works in: the project folder itself (none in a folder listed in everywhere)
project=; pdir=; [ -z "$lite" ] && { project=${root##*/}; pdir=$root; }
# the role cards: the workspace's own, or the plugin's (a project folder without specialists/, or a folder listed in everywhere)
SPEC=$root/specialists; [ -d "$SPEC" ] || SPEC=$(cd "$(dirname "$0")/../templates/specialists" && pwd -P)
# who records the owner's OK: the coordinator, the owner's session at the root of the registered project folder
isowner() { cos_owner "$root" "${CLAUDE_PROJECT_DIR:-$PWD}"; }

# Flat JSON field (hook input is compact JSON); good enough for ids, names and booleans.
jget() { printf '%s' "$in" | sed -n "s/.*\"$1\" *: *\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1; }
# the role a brief names: "Role card: <role>", or the card's path "Role card: <root>/specialists/<role>.md", which
# the subagent reads itself (pasting 8-12 KB cards into every brief crowded out the task). A path elsewhere names no card
# A path may hold spaces (a folder in "My Drive"): it runs up to /specialists/<role>.md
roleof() { _r=$(printf '%s' "$in" | grep -o 'Role card: */[^"\\]*/specialists/[a-z-]*\.md' | head -n 1 | sed 's/^Role card: *//')
  if [ -n "$_r" ]; then case $_r in "$SPEC/"*) _r=${_r#"$SPEC/"}; _r=${_r%.md} ;; *) _r= ;; esac
  else _r=$(printf '%s' "$in" | grep -o 'Role card: *[^ "\\]*' | head -n 1 | sed 's/^Role card: *//'); case $_r in */*) _r= ;; esac; fi
  printf '%s' "$_r" | sed 's/[^a-z-].*//'; }

# codemd FILE: the file sits in a git repository whose top holds a build or test manifest (no fork: a walk up the path)
codemd() { _d=${1%/*}
  while [ -n "$_d" ]; do
    if [ -e "$_d/.git" ]; then
      for _m in package.json Cargo.toml pyproject.toml go.mod Package.swift project.yml Makefile tests test __tests__ spec .claude-plugin; do
        [ -e "$_d/$_m" ] && return 0; done
      return 1; fi
    _d=${_d%/*}; done
  return 1; }

sid=$(jget session_id | tr -cd 'A-Za-z0-9_-')
[ -n "$sid" ] || exit 0
st="$DATA/turns/$sid"   # per user, never shared /tmp
mkdir -p "$st"
mark() { : > "$st/$1"; echo x >> "$st/$1.count"; }
count() { [ -f "$st/$1.count" ] && wc -l < "$st/$1.count" | tr -d ' ' || echo 0; }

case $(jget hook_event_name) in
  UserPromptSubmit)
    rm -f "$st"/*
    : > "$st/start"   # notes modified after this are the turn's notes (whatever tool or path wrote them)
    # A subagent run in the background reports back as a new prompt, so the turn that applies its report would
    # count no specialist. Such a turn is credited with the background specialists started in the last 3 hours,
    # even when the owner wrote in between; the owner's own prompt gets no credit. A notice from another plugin
    # (a security review, a finished shell command) is not a subagent's report.
    # ponytail: the hand-back is known by its text and the window by age; an owner who types the marker gets the credit
    case $in in *'[Subagent hand-back]'*|*'<task-notification>'*[Aa]gent*)
      if [ -f "$st.bg" ]; then
        awk -v now="$(date +%s)" 'now - $1 < 10800' "$st.bg" > "$st.bg.new"; mv "$st.bg.new" "$st.bg"
        while read -r _t m; do mark "$m"; done < "$st.bg"
      fi ;; esac
    # The full text once per session: at its first prompt and after a compaction or a new start (the briefing
    # leaves $st.full); every other prompt gets one line. The text stays in context, and repeating 1-2 KB on
    # every prompt crowded out the work itself
    # The text goes out first, before any slow step, and is marked as seen only once it is out
    if [ -f "$st.full" ] || [ ! -f "$st.seen" ]; then
      pt=$( echo "Chief-of-staff protocol for this request (checked by hooks at the end of the turn):"
      echo "- A deliverable for other people, a decision that crosses areas, or research goes through the specialists skill: at least one specialist and the independent reviewer, as subagents, each briefed with the line 'Role card: <role>' naming its card in $root/specialists/ (the subagent reads the card itself),$([ -z "$lite" ] && printf " a 'Library:' line,") an 'Owner said:' line with the owner's constraints and corrections word for word, and an 'Ambition: <goal behind the goal> | judge: <outside judge>' line. A new request from the owner goes through the ambition skill first."
      cos_fast "$root" && echo "- Hackathon pace (pace: fast): internal work (plans, code, cards, research for the team) needs one specialist subagent, no reviewer. The independent reviewer runs only on what goes outside: the submission, the video, the README, messages to judges, partners or users. Independent work goes to parallel sessions, not one long turn."
      [ -z "$lite" ] && echo "- Research starts in the library: sh \"$L\" search <terms> (workspace: $root). Web search only for what the library lacks. Every new finding, decision, how-to or option becomes a note: sh \"$L\" new <finding|decision|howto|option|topic> <origin> <title>, then fill it. Hooks check every note."
      echo "- Facts that change (what runs in production, balances, public links, deploy state) are measured again before they are repeated, never copied from STATE.md or a card." )
      # one write: a reader that stops at the first line (grep -q) cannot cut the text before it is marked seen
      printf '%s\n' "$pt" && { rm -f "$st.full"; : > "$st.seen"; }
    fi
    # Every other prompt gets nothing: a one-line reminder on all of them (485 prompts, 82% with no specialist due)
    # pushed specialists onto trivial questions. The full text stays in context and the Stop gate still checks
    [ -n "$lite" ] && exit 0
    # first use: trust the settings as they are
    [ -f "$(cos_cfgrec "$root")" ] || cos_cfgsave "$root"
    [ $lst = 0 ] || { sh "$L" where | sed -n 2p; exit 0; }
    # the turn-end gate reads only the turn's notes while its index is fresh: refresh it now, in the background
    ( sh "$L" index </dev/null >/dev/null 2>&1 & )
    # what the company already knows about this request; skipped for an external or very large library (hook time budget)
    case $lib in "$root"/*) ;; *) exit 0 ;; esac
    [ "$(cos_ids "$lib" | wc -l)" -le 3000 ] || exit 0
    # a library whose automatic lookup did not finish inside its budget (a slow disk) is skipped until a note is added
    slow=$(cos_cache slow "$lib")
    [ "$slow" -nt "$lib/notes" ] && { echo "Library lookup skipped (too slow on this disk): run sh \"$L\" search <terms>."; exit 0; }
    q=$(printf '%s' "$in" | LC_ALL=C awk '{ s = s $0 " " } END {
      i = index(s, "\"prompt\":"); if (!i) exit; s = substr(s, i + 9); sub(/^ *"/, "", s); o = ""
      for (j = 1; j <= length(s) && length(o) < 300; j++) { c = substr(s, j, 1)
        if (c == "\\") { j++; c = substr(s, j, 1); o = o ((c == "n" || c == "t" || c == "r") ? " " : c); continue }
        if (c == "\"") break; o = o c }
      print o }')
    [ -n "$q" ] || exit 0
    # The hook dies at 5 s and a killed hook loses everything it printed: the marker is written before the lookup
    # and removed only when the lookup ends inside its 2.5 s budget, so a lookup cut short is not tried again
    mkdir -p "${slow%/*}"; : > "$slow"
    cos_limit 2.5 sh "$L" search --auto "$q" && rm -f "$slow"
    ;;
  PostToolUse)
    tool=$(jget tool_name)
    case $tool in
      Agent)
        role=$(roleof)
        case $role in ''|utility) ;; reviewer) mark reviewer ;; *) mark specialist ;; esac
        # a background launch: Claude Code's result object says status async_launched (the hook never sees the
        # "Async agent launched" text the model reads), so its report, handed back later, carries the credit
        case $role in ''|utility) ;; *) case $in in *'"status":"async_launched"'*|*'"status": "async_launched"'*|*'"run_in_background":true'*|*'"run_in_background": true'*)
          [ "$role" = reviewer ] && m=reviewer || m=specialist; echo "$(date +%s) $m" >> "$st.bg" ;; esac ;; esac
        mark agent ;;
      WebSearch|WebFetch) mark web ;;
      Write|Edit|MultiEdit)
        # jget stops at a comma: read the whole string, and trust it only if the raw input closes it right after
        fp=$(printf '%s' "$in" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1); ok=
        case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*) ok=1 ;; esac
        fp0=$fp
        nope() { echo x >> "$st/rejected.count"; echo "Library note rejected: $1" >&2; exit 2; }
        # the library that holds the file, whichever it is (the session's, or the other one)
        wl=/nonexistent-library; wn=
        if [ "$ok" = 1 ] && [ -z "$lite" ]; then
          o=$(cos_libs "$root" | while IFS="$TAB" read -r n q; do case $fp in ("$q"/*) printf '%s\t%s\n' "$n" "$q"; break ;; esac; done)
          [ -n "$o" ] && { wn=${o%%"$TAB"*}; wl=${o#*"$TAB"}; }
        fi
        pers=; [ -n "$lite" ] || pers=$(cos_lib "$root")
        case "$ok:$fp" in
          1:"$wl/notes/"*/./*|1:"$wl/notes/"*/../*|1:"$wl/notes/"*//*|1:"$wl/notes/"./*|1:"$wl/notes/"../*)
            nope "write it by its plain path, $wl/notes/<id>.md (no ./, ../ or //)" ;;
          1:"$wl/notes/"*/*) nope "notes live directly in $wl/notes/, not in subfolders (link related notes with [[id]] instead): move $fp there" ;;
          1:"$wl/notes/"*.md)   # a note: checked now, while the agent still has it in context
            if p=$(sh "$L" --lib "$wn" check "$fp"); then mark saved; [ -n "$p" ] && echo "$p"
            else nope "fix it now, in $fp:
$p"; fi ;;
          1:"$wl/notes/"*) nope "a note is a .md file named <id>.md: rename $fp" ;;
          1:"$wl/"*) ;;   # inbox and templates: not a note, not a deliverable
          1:"$root/knowledge/"*) [ "$pers" = "$root/knowledge" ] || nope "the library moved to $pers; $root/knowledge is not read. Write the note in $pers/notes/ and delete $fp" ;;
          *) case $in in
          *.md\"*|*.html\"*|*.pptx\"*|*.docx\"*|*.pdf\"*) case $in in *STATE.md\"*|*"/board/"*) ;; *) ctl=; fp=$(jget file_path)
              # jget stops at , } or a quote: trust fp only if the raw input closes the string right after it. The
              # project's own TRACK.md / DELIVERY.md, its settings and Claude's memory (an owner preference) are not deliverables
              case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*)
                case $fp in "$root/TRACK.md"|"$root/DELIVERY.md"|*/CLAUDE.md|*/.claude/*|"$root/specialists/"*|"$root/ROUTING.md") ctl=1 ;;
                  # a .md inside a code repository (git, plus a build or test manifest at its top) is code or its docs,
                  # covered by its own tests: a skill, a template, docs/. Its README goes public and DECISIONS.md holds
                  # guarded decisions, so both still count; a letter or a deck outside a code repository always counts
                  */[Rr][Ee][Aa][Dd][Mm][Ee].md|*/DECISIONS.md) ;;
                  *.md) codemd "$fp" && ctl=1 ;; esac ;; esac
              # An Edit of a file this session already put through specialists and the reviewer is a revision the
              # owner asked for ("Sim, ajusta"), not a new deliverable: half the turn-end pushes in real use were such
              # follow-ups. A Write (a new file or a full rewrite) and DECISIONS.md (guarded decisions) always count
              [ -n "$ctl" ] || { printf '%s\n' "$fp" >> "$st/files"
                case "$tool:$fp" in Edit:*/DECISIONS.md|MultiEdit:*/DECISIONS.md|Write:*) mark deliverable ;;
                  *) grep -qxF -- "$fp" "$st.reviewed" 2>/dev/null || mark deliverable ;; esac; } ;; esac ;;
        esac ;; esac ;;
    esac
    case $in in *library.sh*search*|*"$lib/"*|*"$root/knowledge"*) [ "$tool" = Write ] || [ "$tool" = Edit ] || mark library ;; esac
    # a file written beside one with nearly its name and the same extension (THREE-MACHINE.md next to
    # THREE-MACHINES.md): two copies drift apart and each reader picks one. Same name once letter case, separators
    # and a final s are dropped; index.js beside index.html is a different file. A notice, never a block
    if [ "$tool" = Write ] && [ "$ok" = 1 ]; then case $fp0 in "$wl/"*) ;; "$root"/*)
      nd=$(ls -A "${fp0%/*}" 2>/dev/null | B="${fp0##*/}" LC_ALL=C awk 'function e(s) { s = tolower(s); return match(s, /\.[a-z0-9]+$/) ? substr(s, RSTART) : "" }
        function k(s) { s = tolower(s); sub(/\.[a-z0-9]+$/, "", s); gsub(/[^a-z0-9]/, "", s); sub(/s$/, "", s); return s }
        BEGIN { t = k(ENVIRON["B"]); x = e(ENVIRON["B"]) } $0 != ENVIRON["B"] && length(t) > 2 && e($0) == x && k($0) == t { print; exit }' | tr -d '"\\\000-\037')
      [ -n "$nd" ] && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"chief-of-staff: %s has nearly the same name as %s in the same folder: check whether one duplicates the other."}}\n' "$(printf '%s' "${fp0##*/}" | tr -d '"\\\000-\037')" "$nd" ;; esac; fi
    ;;
  PreToolUse)
    case $(jget tool_name) in
      Agent)
        role=$(roleof)
        [ "$role" = utility ] && exit 0
        # a built-in read-only helper (search, a web page, Claude Code docs) is a utility by its type: its launch was
        # blocked for a missing role card, a wasted round each time. It earns no specialist credit either way
        [ -z "$role" ] && case $(jget subagent_type) in Explore|web-fetch|claude-code-guide) exit 0 ;; esac
        if [ -n "$role" ] && [ -f "$SPEC/$role.md" ]; then
          [ -n "$lite" ] || case $in in *"Library:"*) ;; *)
            echo "Blocked by chief-of-staff: the brief must carry what the library already knows. Add a line 'Library: [[id]] [[id]] ...' with the notes from library.sh search, or 'Library: none found for <terms>'." >&2
            exit 2 ;; esac
          # a real line, not a placeholder: the goal and the judge both have to say something
          printf '%s' "$in" | grep -Eq 'Ambition: [^|]{12,}\| *judge: [^"\\]{8,}' && exit 0
          echo "Blocked by chief-of-staff: a specialist works to the goal behind the request, judged from outside (ambition skill). Add a line 'Ambition: <the goal behind the goal> | judge: <what measures THAT goal: a command that runs, a rule with its source, the arithmetic, or real numbers>'. At most 4 versions; scope beyond the request is a question for the owner, never work." >&2
          exit 2
        fi
        cards=$(ls "$SPEC" 2>/dev/null | sed -n 's/\.md$//p' | tr '\n' ' ')
        echo "Blocked by chief-of-staff: every subagent brief names its role card. Add the line 'Role card: <role>' (the role name is enough, for example 'Role card: researcher'), and tell the subagent to read $SPEC/<role>.md itself; do not paste the card. Cards: ${cards:-none found}. For a search or file-reading helper, write 'Role card: utility'." >&2
        exit 2 ;;
      WebSearch|WebFetch)
        [ -n "$lite" ] && exit 0
        [ -f "$st/library" ] && exit 0
        # only a library that is really absent (disk unplugged) lets research go on without it; a broken one does not
        [ $lst = 1 ] && { mark offline; exit 0; }
        [ $lst = 0 ] || { sh "$L" where | sed -n 2p >&2; exit 2; }
        echo "Blocked by chief-of-staff: search the library first, then search the web only for what it lacks. Run: sh \"$(dirname "$0")/library.sh\" search <terms>" >&2
        exit 2 ;;
      Write|Edit|MultiEdit|Bash)   # the marker says where the library lives: only the owner edits it
        [ -n "$lite" ] && exit 0
        # macOS file names ignore case: .CHIEF-OF-STAFF is the marker, and so is .owner-oK with a Kelvin sign (cos_fold)
        lc=$(printf '%s' "$in" | tr 'A-Z' 'a-z' | cos_fold)
        case $(jget tool_name) in
          Bash)
            # ponytail: a word list, not a shell parser; the files are also read-only on disk.
            # A command that names them and could write them is blocked
            blk=
            # the command alone, JSON escapes undone enough for matching (\t, \n, \" become plain)
            cq=$(printf '%s' "$lc" | sed -nE 's/.*"command" *: *"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\[tn]/ /g; s/\\"/"/g' | head -n 1)
            uq=$(printf '%s' "$cq" | tr -d "\"'\\\\")
            # the names, or a glob or brace that could spell them (.[c]hief, .l*, ?library, {.,x}library)
            # ponytail: a name built in a variable (a=.chi; ...${a}ef) is not seen; the files are read-only on disk
            LIT='\.chief|\.library|cos-cfg|owner-ok|owner-items|plugins/data'   # not "chief-of-staff": the plugin's own folder has that name; plugins/data holds the project list and the library setting
            # a glob at the start of a path or right after a redirect (a regex .* inside a word, foo.*bar or (.*?), is
            # not one), a glob after a piece of a name (.ch*, .l?brary, .own?r-ok), or a glob before one (?library, *-ok)
            GLOB='(^|[ /=]|(^|[^a-z_:-])[0-9]*>+ *)\.[][?*]|(^|[^a-z0-9_.-])\.(c(h(i(e(f)?)?)?)?|l(i(b(r(a(r(y)?)?)?)?)?)?|o(w(n(e(r(-(o(k)?|i(t(e(m(s)?)?)?)?)?)?)?)?)?)?)[][?*]|[][?*](l?ibrary|c?hief)|[][?*][a-z]*-(ok|items)([^a-z0-9_-]|$)'
            # the command as the shell reads it: JSON undone, quote characters dropped. In a grep command a quoted or
            # escaped * ? [ ] { } , is part of a pattern, so it is made inert there (^?? .*\.owner is no glob); in
            # any other command it stays, since python glob(), find -name or sh -c can still expand it. There an
            # opening quote, or a quote character inside quotes (python -c "glob(\".*\")"), starts a path (glob(".*")
            # reads as /.*) and a quoted space is part of a name, not a gap
            # between words (re.sub(r"by: .*") is no glob)
            GV='function dec(s,   o, i, c, d) { o = ""
                for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
                  if (c == "\\") { i++; d = substr(s, i, 1); c = d == "n" ? "\n" : (d == "t" || d == "r") ? " " : d == "u" ? "_" : d; if (d == "u") i += 4 }
                  o = o c }
                return o }
              function fix(t,   w) { gsub(M "[\"\047]", M "/", t); w = t; sub(/^[ \t(!{]*([a-z_][a-z0-9_]*=[^ ]* +)*/, "", w)
                if (w ~ /^([^ ]*\/)?[ef]?grep( |$)/) gsub(M "[][?*{},]", "_", t); else gsub(M " ", "_", t)
                gsub(M, "", t); return t }
              BEGIN { M = sprintf("%c", 1) }
              { s = dec($0); n = length(s); out = ""; seg = ""; q = 0
                for (i = 1; i <= n; i++) { c = substr(s, i, 1)
                  if (q == 0) {
                    if (c == ";" || c == "&" || c == "|" || c == "\n") { out = out fix(seg) c; seg = ""; continue }
                    if (c == "\\") { i++; seg = seg M substr(s, i, 1); continue }
                    if (c == "\047") { q = 1; seg = seg M "/"; continue }
                    if (c == "\"") { q = 2; seg = seg M "/"; continue }
                    seg = seg c; continue }
                  if ((q == 1 && c == "\047") || (q == 2 && c == "\"")) { q = 0; continue }
                  if (q == 2 && c == "\\") { i++; c = substr(s, i, 1) }
                  seg = seg M c }
                printf "%s\n", out fix(seg) }'
            gv=$(printf '%s' "$lc" | sed -nE 's/.*"command" *: *"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 | LC_ALL=C awk "$GV")
            # grep -q exits 2 on a broken pattern: count that as a match, never as a pass
            hit() { grep -Eq "$LIT|$GLOB"; [ $? != 1 ]; }
            # the names also as the shell joins them (.owner-"ok" is .owner-ok): gv marks that quote as a path start
            sus=; printf '%s\n' "$gv" | hit && sus=1
            printf '%s\n' "$uq" | grep -Eq "$LIT"; [ $? != 1 ] && sus=1
            # $'\056library': only a numeric, \x or \u escape can spell a dot or a letter ($'a\nb' cannot)
            printf '%s' "$cq" | grep -Eq "\\\$'[^']*\\\\[0-7xu]" && sus=1
            # a brace builds names: expand every one, nested and ranges too, and test what it makes. A range over
            # punctuation ({-../}) can make a dot, and too many expansions fail closed
            BX='function emit(s,   p, b, q, k, a, j, lo, hi, c) {
                if (++N > 300) { print ".chief"; return }
                if (match(s, /\{[^{} ]*,[^{} ]*\}/)) {
                  p = substr(s, 1, RSTART - 1); b = substr(s, RSTART + 1, RLENGTH - 2); q = substr(s, RSTART + RLENGTH)
                  k = split(b, a, ","); for (j = 1; j <= k; j++) emit(p a[j] q); return }
                if (match(s, /\{[^{} ]\.\.[^{} ](\.\.[0-9]+)?\}/)) {
                  p = substr(s, 1, RSTART - 1); q = substr(s, RSTART + RLENGTH)
                  lo = index(CH, substr(s, RSTART + 1, 1)); hi = index(CH, substr(s, RSTART + 4, 1))
                  if (!lo || !hi) { print ".chief"; return }
                  if (lo > hi) { c = lo; lo = hi; hi = c }
                  for (j = lo; j <= hi; j++) emit(p substr(CH, j, 1) q); return }
                print s }
              BEGIN { CH = "0123456789abcdefghijklmnopqrstuvwxyz" }
              { N = 0; emit($0) }'
            [ -z "$sus" ] && printf '%s\n' "$gv" | LC_ALL=C awk "$BX" | hit && sus=1
            # 2>&1 and >/dev/null write nothing. Whole words only: a folder named "firmware" is not rm.
            # Reading them is fine: sed without -i or a w/e command, awk without system() or a pipe into sh, and a
            # plain git log/show/status/blame/ls-files/cat-file/rev-parse/diff/branch (no option before the
            # subcommand, no GIT_* variable, pager, textconv, external diff or --output, which can run a command)
            if [ -n "$sus" ]; then
              case $(printf '%s' "$uq" | sed 's|[0-9]*>&[0-9]||g; s|[0-9]*>> */dev/null||g; s|[0-9]*> */dev/null||g') in *">"*) blk=1 ;; esac
              printf ' %s \n' "$uq" | grep -Eq '[^a-z0-9_.-]sed( .*)?( -[a-z]*i|--in-place|[[:space:];{}/0-9$!][we]([^a-z0-9_-]|$))|system|--output|-delete|\| *(ba|da|z)?sh([^a-z0-9_.-]|$)' && blk=1
              gr='s/(^|[^a-z0-9_.-])git +(log|show|status|blame|ls-files|cat-file|rev-parse|diff|branch)([^a-z0-9_.-]|$)/\1 \3/g'
              case $uq in *git_*|*pager*|*textconv*|*ext-diff*|*external*|*exec-path*|*config-env*|*alias.*) gr= ;; esac
              printf ' %s \n' "$uq" | sed -E "${gr:-s/^//}" |
                grep -Eq '[^a-z0-9_.-](tee|mv|cp|rm|perl[0-9.]*|python[0-9.]*|ln|dd|install|rsync|touch|truncate|chmod|chflags|chown|chgrp|xattr|unlink|shred|tar|unzip|gunzip|patch|ditto|sponge|node|deno|bun|ruby|php|lua|swift|osascript|git|ed|ex)([^a-z0-9_.-]|$)' && blk=1
            fi
            if [ -z "$blk" ]; then
              # the plugin's own read-only commands, the ones the hooks already run by themselves, skip the permission
              # prompt (not the user's decision): one call of library.sh or track.sh at this plugin's own path, a
              # read-only subcommand, no shell syntax, and paths only inside the workspace. Anything else goes on to
              # the checks below and keeps the normal prompt; Claude Code's deny and ask rules still apply over this
              ro=; [ "$(printf '%s' "$in" | grep -o '"command" *:' | wc -l | tr -d ' ')" = 1 ] &&
                ro=$(printf '%s' "$in" | sed -nE 's/.*"command" *: *"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
              case $ro in *\\[!\"]*|*\\) ro= ;; esac   # a JSON escape other than \" (\n, \t, \\, \u): no
              ro=$(printf '%s' "$ro" | sed 's/\\"/"/g'); H=$(cd "$(dirname "$0")" && pwd); r=
              case $H in *[\"\'\$\`\\]*) ro= ;; esac
              for s in library track; do for q in '"' "'" ''; do
                [ -z "$q" ] && case $H in *[!A-Za-z0-9_./-]*) continue ;; esac
                case $ro in "sh $q$H/$s.sh$q "*) r="$s ${ro#"sh $q$H/$s.sh$q "}" ;; esac; done; done
              if [ -n "$r" ] && ! printf '%s' "$r" | LC_ALL=C grep -q '[][$`\;&|<>(){}*?!#~^[:cntrl:]]' &&
                printf '%s\n' "$r" | grep -Eqx 'library (search|similar|check|gate|doctor|backlinks|brief|where|libs)( .*)?|track (check|brief|status|items) .+'; then
                # each argument as the shell reads it (quotes join words); an unbalanced quote: no
                out=1; ws=$(printf '%s\n' "$r" | awk '{ q = ""; w = ""; for (i = 1; i <= length($0); i++) { c = substr($0, i, 1)
                    if (q == "" && (c == "\"" || c == "\047")) { q = c; continue } if (c == q) { q = ""; continue }
                    if (q == "" && c == " ") { if (w != "") print w; w = ""; continue } w = w c }
                  if (q != "") exit 1; if (w != "") print w }') || out=
                # a path is absolute and, symlinks resolved, inside the workspace (a relative one is read from a folder
                # the hook does not know); track.sh, library.sh check and gate take only paths, the rest only words
                rr=$(cd "$root" && pwd -P); k=0; pa=   # compared as written: on Linux Ws and ws are two folders
                while IFS= read -r w; do k=$((k + 1)); [ $k -le 2 ] && { [ $k = 2 ] && case $r in track*|"library check"*|"library gate"*) pa=1 ;; esac; continue; }
                  case $w in */*|.*) [ -n "$pa" ] || out= ;; *) [ -z "$pa" ] || out= ;; esac
                  [ -n "$pa" ] && case $w in /*) case $(realp "$w") in "$rr"|"$rr"/*) ;; *) out= ;; esac ;; *) out= ;; esac; done <<WS
$ws
WS
                [ -n "$out" ] && { echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"chief-of-staff: its own read-only command"}}'; exit 0; }
              fi
              # ponytail: a word match, not a shell parser. Quotes, backslashes and tabs are dropped first, so u''se or
              # "join" count, and a script name anywhere in a word counts (a renamed copy, my-library.sh, too)
              nq=$(printf '%s' "$cq" | tr -d "\"'\\\\")
              # a variable that holds a script (L=.../library.sh) is that script wherever it is used, and the
              # assignment alone runs nothing: rewrite "$L" as library.sh and drop the assignment, then match as usual
              for _s in library track project; do
                for _v in $(printf '%s\n' "$nq" | grep -oE "(^|[^a-z0-9_])[a-z_][a-z0-9_]*=[^ ;&|]*$_s\\.sh" | sed -E 's/^[^a-z_]*//; s/=.*//' | sort -u); do
                  nq=$(printf '%s\n' "$nq" | sed -E "s/(^|[^a-z0-9_])$_v=[^ ;&|]*$_s\\.sh/\\1$_v=/g; s/\\\$\\{?$_v\\}?([^a-z0-9_]|\$)/$_s.sh\\1/g")
                done
              done
              # A script reads its subcommand from its first argument (library.sh: after --lib <name>), so it is the
              # word right after the script name. That word is ok/use/join/... , or it is not literal: a variable,
              # $(...), a brace or a glob ($ ` { ? * [). A script fed from stdin (xargs, find -exec, source, its text
              # piped into a shell) has no visible subcommand and counts too.
              DYN='[^ ;&|]*[][$`{?*]'
              FEED='[^;&]*\| *([^ ]*/)?(xargs|sh|bash|zsh|dash|ksh|source|eval)([^a-z0-9_.-]|$)'
              # the dot command sits where a command starts, or right after an opening backtick: the dot ending a
              # sentence ("(freeze f78). Owner", "`portal`. Then") is none
              FROM='((^|[^a-z0-9_.-])(xargs|parallel|-exec|-execdir|source)|(^|[ ;&|({!]|(^|[ =(])`)\.)( [^;&|]*)? [^ ;&|]*'
              # the owner's OK on a project step, and any script run with ok first (a renamed copy of track.sh)
              if printf '%s\n' "$nq" | grep -Eq "track\\.sh +($DYN|ok([^a-z0-9_.-]|\$))|[^ ]\\.sh +ok([^a-z0-9_.-]|\$)|track\\.sh$FEED|<+ *[^ ;&|]*track\\.sh|${FROM}track\\.sh *([)\`;&|]|\$)"; then
                # the session's own folder comes from Claude Code, not from the shell: a cd cannot fake the coordinator
                isowner || { echo "Blocked by chief-of-staff: only the project's coordinator (the owner's conversation at the root of the project folder) records the owner's OK. Write the request on the project's card; the coordinator asks the owner. (To read track.sh, use the Read or Grep tool.)" >&2; exit 2; }
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this records YOUR OK on a project step (scope freeze, submission, or the target and check, which approves and later runs the check command shown in its output). Only approve if you gave that OK."}}'; exit 0
              fi
              # a script called with a list of words (subprocess.run([sh,track.sh,ok]), spawn(sh,[library.sh,use])):
              # no space after its name, so its subcommand may be any later word. A plain grep runs nothing (not with a
              # filter, ugrep --filter runs a command, nor with $(...), backticks or <(...) inside). With a space after the name the word right after it is the
              # subcommand, handled above (track.sh dispatches on $1 only, so sh track.sh x y ok records nothing)
              segs=$(printf '%s\n' "$nq" | tr ';&|' '\n\n\n')
              case $nq in *--filter*|*--pre*) ;; *) segs=$(printf '%s\n' "$segs" | grep -Ev '^[ (]*([^ ]*/)?[ef]?grep [^$`(){}<>]*$') ;; esac
              if printf '%s\n' "$segs" | grep -Eq 'track\.sh[^ a-z0-9_.-](.*[^a-z0-9_.-])?ok([^a-z0-9_.-]|$)'; then
                isowner || { echo "Blocked by chief-of-staff: only the project's coordinator (the owner's conversation at the root of the project folder) records the owner's OK. Write the request on the project's card; the coordinator asks the owner. (To read track.sh, use the Read or Grep tool.)" >&2; exit 2; }
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this may record YOUR OK on a project step. Only approve if you gave that OK."}}'; exit 0
              fi
              # a script called with a list of words (spawn(sh,[project.sh,init])): any later word may be the subcommand
              printf '%s\n' "$segs" | grep -Eq 'project\.sh[^ a-z0-9_.-](.*[^a-z0-9_-])?(init|library|trust)([^a-z0-9_-]|$)' && nq="$nq ; project.sh init"
              # registering a project folder makes its root session a coordinator, setting the library chooses where every
              # note goes, and trust records the project's settings as the owner checked them: the owner approves
              # each run (new-project registers through project.sh, which the owner approves)
              if printf '%s\n' "$nq" | grep -Eq "project\\.sh +((init|library|trust)([^a-z0-9_-]|\$)|$DYN)|project\\.sh$FEED|<+ *[^ ;&|]*project\\.sh|${FROM}project\\.sh *([)\`;&|]|\$)"; then
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this registers a project folder (its root conversation becomes the coordinator that asks you), sets your library, or records the settings of a project as you checked them. Only approve if you asked for it."}}'
              # a push whose commits change a term that a decision in force guards ("guard: <term>" in the project's
              # DECISIONS.md) asks first: a teammate's later change must not undo a decision without anyone seeing it
              elif [ -n "$project" ] && [ -f "$pdir/DECISIONS.md" ] && printf '%s\n' "$nq" | grep -Eq '(^|[^a-z0-9_.-])git .*push([^a-z0-9_-]|$)'; then
                gt=$(cos_decisions "$pdir/DECISIONS.md" | cut -f2 | sed -n 's/.*guard: *\([^;|)]*\).*/\1/p' | sed 's/ *$//' | grep .)
                if [ -n "$gt" ]; then
                  # what the push sends: past the branch's upstream, else past the same branch on origin, else past
                  # origin's default branch (a new branch, push -u). With none of them it cannot be told: ask (fail closed)
                  gb=$(git -C "$PWD" rev-parse --abbrev-ref HEAD 2>/dev/null); base=
                  for r in '@{u}' "origin/$gb" origin/HEAD origin/main origin/master; do
                    git -C "$PWD" rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1 && { base=$r; break; }; done
                  if [ -z "$base" ]; then
                    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this project has guarded decisions in DECISIONS.md and this push has no remote branch to compare with, so what it changes cannot be checked. Approve only if it does not undo a decision."}}'; exit 0
                  fi
                  dv=$(git -C "$PWD" diff "$base...HEAD" 2>/dev/null | grep '^[-+]' | grep -v '^[-+][-+][-+] ')
                  hitg=$(printf '%s\n' "$gt" | while IFS= read -r t; do printf '%s\n' "$dv" | grep -qiF -- "$t" && printf '%s, ' "$t"; done | tr -d '"\\\000-\037')
                  [ -n "$hitg" ] && echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this push changes '"${hitg%, }"', guarded by a decision in DECISIONS.md. Approve only if that decision still holds or was replaced by a new line."}}'
                fi
              fi
              exit 0
            fi ;;
          *) # the library's git data and the plugin's own files. The path is resolved (.., symlinks, letter case) before it is compared
             fp=$(printf '%s' "$in" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1)
             case $fp in /*) rp=$(real "$fp")
               [ -n "$rp" ] || { echo "Blocked by chief-of-staff: write $fp by its plain path, without . or .. parts." >&2; exit 2; } ;; *) rp= ;; esac
             o=$(cos_libs "$root" | while IFS="$TAB" read -r n q; do [ -d "$q" ] || continue
               case $rp in ("$(cd "$q" && pwd -P | tr 'A-Z' 'a-z')"/*) echo "$n"; break ;; esac; done)
             case $rp in */.git/*|*/.git) [ -n "$o" ] && { echo "Blocked by chief-of-staff: $fp is inside the git data of the library; only git writes there." >&2; exit 2; } ;; esac
             # the project list, the library setting and the board list of the global panel (project.sh writes them)
             case $rp in "$(real "$DATA")/projects"|"$(real "$DATA")/library"|"$(real "$DATA")/boards"|*/plugins/data/*/projects|*/plugins/data/*/library|*/plugins/data/*/boards) rp=blocked ;; esac
             [ "$rp" = blocked ] || case $(printf '%s' "$lc" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1) in */.chief-of-staff|*/.library-id|*/.library|*/.chief-of-staff/*|*/.owner-ok|*/.owner-items) ;; *) exit 0 ;; esac ;;
        esac
        echo "Blocked by chief-of-staff: .chief-of-staff (the project's marker and settings), .library-id, .owner-ok (the owner's OKs), .owner-items, and the plugin's data folder (the project list, the library setting, the board list) are changed only through track.sh ok and project.sh, which the owner confirms.$([ "$(jget tool_name)" = Bash ] && printf ' If the command only mentions one of these names (a commit message, an echo), rephrase it without the name.')" >&2
        exit 2 ;;
    esac
    ;;
  SubagentStop)
    [ "$(jget stop_hook_active)" = true ] && exit 0
    case $in in *"Role: utility"*) exit 0 ;; *"Role: "*) ;; *) exit 0 ;; esac
    case $in in *"Never-skip checklist"*) ;; *)
      echo "Your role card requires a '## Never-skip checklist' section: mark each item of your card's 'Never skip' list as done or not applicable (why). Add it, then finish." >&2
      exit 2 ;; esac
    # the reviewer judges; every other specialist shows its versions (ambition skill)
    case $in in *"Role: reviewer"*) exit 0 ;; esac
    case $in in *"## Versions"*)
      # each verdict shows what the judge printed or wrote, so no version (failed or passed) is made up
      # a <placeholder> copied from the role card's output format is no evidence
      printf '%s' "${in#*'## Versions'}" | grep -Eq '(evidence|passed): *[^ "\\<]' && exit 0
      echo "Your '## Versions' lines need the judge's evidence: end each with 'evidence: <the command and its output, or the file that shows it>'. A first version that passed is fine as 'v1 passed: <what the judge printed>'; never invent a failed version." >&2
      exit 2 ;; esac
    echo "Your brief carries an Ambition line: add a '## Versions' section, one line per version (the lens, what changed, the verdict of the judge named in your brief, and its evidence: the command output or the file). A first version that passed is written 'v1 passed: <what the judge printed>'; then say why that judge measures the goal behind the goal." >&2
    exit 2
    ;;
  Stop)
    # a question to the owner is timed from when it was asked (asked:), not from a file date that git resets
    # an open question (a line under "For the owner to decide") that a project session wrote this turn makes its
    # card wait on the owner, even when the agent forgot the status: the coordinator moves answered lines to "## Decided"
    # Each new question line is stamped with its own time too, so a later rewrite of asked: or a newer question
    # never resets the age of an older one. One pass over the board (cos_board).
    fresh=; [ -n "$project" ] && [ -f "$st/start" ] && fresh=$(find "$root/board" -name '*.md' -type f -cnewer "$st/start" 2>/dev/null)
    now=$(date '+%F %H:%M %z'); US=$(printf '\037')
    [ -n "$lite" ] && : > "$st/board" || cos_board "$root" > "$st/board"
    while IFS=$US read -r c cm cp cs a _d nq nu sp _r; do
      [ -n "$project" ] && [ "$nq" -gt 0 ] && printf '%s\n' "$fresh" | grep -qxF "$c" &&
        case $cs in ''|in-progress) true ;; *) false ;; esac && { fm_set "$c" status waiting-owner; cs=waiting-owner; }
      if [ "$cs" = waiting-owner ]; then [ -n "$a" ] || fm_set "$c" asked "$now"
        # a card from v0.4 (asked: set, no line stamped yet): its questions keep that time, not the migration's
        w=$now; [ -z "$sp" ] && case $a in [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]" "[0-2][0-9]:[0-5][0-9]|[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]" "[0-2][0-9]:[0-5][0-9]" "[+-][0-2][0-9][0-5][0-9]) w=$a ;; esac
        [ "$nu" -gt 0 ] && cos_stamp "$c" "$w"
      elif [ -n "$a" ]; then fm_set "$c" asked ""; fi
    done < "$st/board"
    # ponytail: "substantive" is a heuristic (deliverable file, web research, or a long answer);
    # replace with a model-graded check if it misfires in real use.
    # The answer itself is measured (last_assistant_message), not the whole hook JSON: paths and ids add ~400 B,
    # and a 2-3 KB status report forced specialists on every turn. Over 6000 characters (about 1000 words) the
    # answer is a deliverable written in the chat; files and research are caught by their own marks
    size=$(printf '%s' "$in" | LC_ALL=C awk '{ s = s $0 "\n" } END { i = index(s, "\"last_assistant_message\":"); if (!i) { print 0; exit }
      s = substr(s, i + 25); sub(/^ *"/, "", s); n = 0
      for (j = 1; j <= length(s); j++) { c = substr(s, j, 1); if (c == "\\") { j++; n++; continue } if (c == "\"") break; n++ }
      print n }')
    substantive=0
    { [ -f "$st/deliverable" ] || [ -f "$st/web" ] || [ "${size:-0}" -gt 6000 ]; } && substantive=1
    agents=$(count agent); specialists=$(count specialist); reviewers=$(count reviewer)
    reason=
    if cos_fast "$root"; then
      [ $((specialists + reviewers)) -ge 1 ] && [ -f "$st/files" ] && cat "$st/files" >> "$st.reviewed"
      [ "$substantive" = 1 ] && [ $((specialists + reviewers)) -lt 1 ] && reason="This turn produced a deliverable, research or a long answer with no specialist. Before finishing, run one senior specialist as a subagent, briefed with its role card from $root/specialists/ (and the independent reviewer too if this goes outside: submission, video, README, a message to judges or partners), then revise the answer with what it found."
    else
      [ "$specialists" -ge 1 ] && [ "$reviewers" -ge 1 ] && [ -f "$st/files" ] && cat "$st/files" >> "$st.reviewed"
      [ "$substantive" = 1 ] && { [ "$specialists" -lt 1 ] || [ "$reviewers" -lt 1 ]; } && reason="This turn produced a deliverable, research or a long answer with $specialists specialist(s) and $reviewers reviewer(s). Before finishing, run the specialists skill: at least one senior specialist and the independent reviewer as subagents, each briefed with its role card from $root/specialists/, then revise the answer with what they found."
    fi
    [ -f "$st/web" ] && [ ! -f "$st/saved" ] && [ $lst = 0 ] && reason="${reason:+$reason }This turn searched the web but saved nothing to the library. Save each new finding as a note in $lib/notes/ (sh \"$L\" new ...) before finishing."
    lgaps=; push=; lslow=
    gap() { lgaps="${lgaps:+$lgaps
}$1"; }
    # a step cut by its time budget (slow disk) is not the agent's fault: it blocks once, never counts as a violation,
    # and fails closed
    slow() { lslow="${lslow:+$lslow
}$1"; }
    if [ -z "$lite" ]; then   # the library and the settings record: a project folder's only
    if [ -f "$st/start" ]; then
      while IFS="$TAB" read -r n q; do
        [ -n "$n" ] && [ "$n" = "$lname" ] || continue   # a session gates only its own library (it writes no other)
        cos_libpath "$root" "$n" >/dev/null || continue   # offline or broken: nothing to gate there
        # ctime, not mtime: mv, cp -p or touch -t keep or set an old mtime, never an old ctime
        ch=$(find "$q/notes" -name '*.md' -type f -cnewer "$st/start" 2>/dev/null | while IFS= read -r f; do printf '%s\n' "${f#"$q/"}"; done)
        [ -n "$ch" ] || continue
        set --
        while IFS= read -r f; do
          case $f in notes/*/*|*' '*|*'"'*) ;; notes/*.md) set -- "$@" "$q/$f" ;; esac
        done <<CH
$ch
CH
        [ $# -gt 0 ] || continue
        if [ $# -gt 20 ]; then gap "More than 20 notes changed in '$n'; only 20 can be checked in one turn: run library.sh doctor, and save fewer notes per turn."; set --; fi
        [ $# -gt 0 ] || continue
        # each slow step has its own budget inside the hook's 5 s; one that runs out fails closed, saying what to run
        g=$(cos_limit 1.5 env COS_SINCE="$st/start" sh "$L" gate "$@") || [ $? != 124 ] || { g=; slow "The library check of this turn's notes did not finish in time (slow disk): run sh \"$L\" doctor and fix what it lists."; }
        g=$(printf '%s\n' "$g" | grep -v ': warning: ' | head -n 20)
        [ -n "$g" ] && gap "$g"
      done <<LIBS
$(cos_libs "$root")
LIBS
    fi
    r=$(cos_cfgrec "$root")
    [ -f "$r" ] && [ "$(cat "$r")" != "$(cos_cfg "$root")" ] && gap "The project's settings (.chief-of-staff) changed without the owner. Put the marker back as it was (git -C \"$root\" checkout -- .chief-of-staff, if git has it), or ask the owner to confirm it: sh \"$(dirname "$0")/project.sh\" trust \"$root\"."
    fi
    [ -n "$lgaps" ] && reason="${reason:+$reason }Library notes written this turn have problems:
$lgaps
Fix each note (format: $lib/templates/note.md). When a new note is better than an old one, or merges several, retire the old: sh \"$L\" retire <old-id> <new-id> \"<why it lost>\". Valid alternatives stay: write [[id]] coexists (reason)."
    gaps=
    if [ -n "$project" ]; then
      gaps=$(cos_limit 1.5 sh "$(dirname "$0")/track.sh" check "$pdir") || [ $? != 124 ] ||
        { gaps=; slow "track.sh check did not finish in time (slow disk): run sh \"$(dirname "$0")/track.sh\" check $pdir and close what it lists."; }
      gaps=$(printf '%s\n' "$gaps" | head -n 20 | grep .)
    fi
    [ -n "$gaps" ] && reason="${reason:+$reason }Track gate (${pdir#"$root/"}/TRACK.md) not met:
$gaps
Close each item with its proof file (evidence: path relative to the project folder), mark it [-] with why: when it does not apply, or move stage: back. A stage passes only when every item is closed."
    # Rotation: a conversation past rotate_tokens of context (the last usage the transcript records), or one Claude
    # Code compacted, has lost or is about to lose detail. Due from then until the project's STATE.md is written
    # again; after that, due again only 40k tokens later. Subagents start clean: not here.
    sf=; [ -n "$project" ] && sf=$pdir/STATE.md
    if [ -n "$sf" ]; then
      tp=$(jget transcript_path); tok=0
      [ -f "$tp" ] && tok=$(tail -c 400000 "$tp" | grep '"type":"assistant"' | grep -v '"isSidechain":true' | grep -o '"usage":{[^}]*}' | tail -n 1 | LC_ALL=C awk -F '[:,}]' '{ for (i = 1; i < NF; i++) if ($i ~ /"(input_tokens|cache_creation_input_tokens|cache_read_input_tokens)"$/) n += $(i + 1) } END { print n + 0 }')
      lim=$(sed -n 's/^rotate_tokens: *\([0-9][0-9]*\)$/\1/p' "$root/.chief-of-staff" 2>/dev/null | head -n 1); lim=${lim:-140000}
      last=$(cat "$st.rotated" 2>/dev/null | tr -cd 0-9); [ -n "$last" ] && [ "$tok" -lt "$last" ] && last=   # compacted since: count afresh
      [ ! -f "$st.rotate" ] && { [ -f "$st.compacted" ] || { [ "$tok" -ge "$lim" ] && { [ -z "$last" ] || [ "$tok" -ge $((last + 40000)) ]; }; }; } &&
        { : > "$st.rotate"; [ -f "$st/start" ] && touch -r "$st/start" "$st.rotate"; }   # due from the turn's start: a handoff written in this turn counts
      if [ -f "$st.rotate" ] && [ -f "$sf" ] && [ "$sf" -nt "$st.rotate" ]; then
        echo "$tok" > "$st.rotated"; rm -f "$st.rotate" "$st.compacted"
      elif [ -f "$st.rotate" ]; then
        rel_sf=${sf#"$root/"}
        reason="${reason:+$reason }Rotation: this conversation is long ($tok tokens of context, limit $lim) or was compacted, so its detail is being lost. Run the handoff skill now: write $rel_sf as the snapshot of now (what is in flight, what was promised, the sessions started, the next action). Then end the answer saying the work continues in a new session in this folder; a thread writes that on its card for the coordinator, and the dispatcher starts it when dispatch: ready."
      fi
    fi
    pushed=$(jget stop_hook_active)
    violation=0; [ "$pushed" = true ] && [ -n "$reason" ] && violation=1
    [ -n "$lslow" ] && reason="${reason:+$reason }Not checked this turn (slow disk):
$lslow"
    printf '%s t=%s turn=%s project=%s substantive=%s agents=%s specialists=%s reviewers=%s library=%s web=%s saved=%s track=%s pushed=%s violation=%s notes=%s offline=%s rejected=%s slow=%s\n' \
      "$(date '+%F %T')" "$(date +%s)" "$sid" "${project:--}" "$substantive" "$agents" "$specialists" "$reviewers" \
      "$([ -f "$st/library" ] && echo 1 || echo 0)" "$([ -f "$st/web" ] && echo 1 || echo 0)" "$([ -f "$st/saved" ] && echo 1 || echo 0)" \
      "$(printf '%s' "$gaps" | grep -c .)" "${pushed:-false}" "$violation" "$(printf '%s' "$lgaps" | grep -c .)" "$([ $lst = 0 ] && echo 0 || echo 1)" "$(count rejected)" "$(printf '%s' "$lslow" | grep -c .)" >> "$([ -n "$lite" ] && echo "$DATA/protocol.log" || echo "$root/.protocol.log")"
    [ "$pushed" = true ] && exit 0
    [ -n "$reason" ] || exit 0
    echo "$reason" >&2
    exit 2
    ;;
esac
exit 0
