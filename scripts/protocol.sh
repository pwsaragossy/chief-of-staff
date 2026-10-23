#!/bin/sh
# Protocol gates. One script for four hook events, so the rules live in one place:
#   UserPromptSubmit  starts a new turn record and restates the protocol (every turn, survives compaction)
#   PostToolUse       records what the turn did: specialists (Agent), library lookups, web research, saves
#   PreToolUse        on WebSearch/WebFetch: blocked until the library was searched this turn;
#                     on Agent: blocked unless the brief names an existing role card (specialists/<role>.md)
#   SubagentStop      a specialist cannot finish without its never-skip checklist
#   Stop              blocks the end of a substantive turn that skipped specialists or the reviewer, researched
#                     without saving to the library, or left the project's TRACK.md with a gate problem
#                     (track.sh check). One push per turn (stop_hook_active), then it lets go and logs a violation.
# Silent outside a workspace. Every turn is logged to <workspace>/.protocol.log (the adherence metric).
. "$(dirname "$0")/lib.sh"

in=$(cat)
root=$(cos_root "${CLAUDE_PROJECT_DIR:-$PWD}") || exit 0
rel=${CLAUDE_PROJECT_DIR:-$PWD}; rel=${rel#"$root"}; rel=${rel#/}
# the session's library (its project's, or personal) and its state; lst != 0: offline or misconfigured (library.sh where)
lname=$(cos_libname "$root" "${CLAUDE_PROJECT_DIR:-$PWD}"); lib=$(cos_libpath "$root" "$lname"); lst=$?
L="$(dirname "$0")/library.sh"; TAB=$(printf '\t')
# a team library's paths changed here or committed and not pushed yet, deletions left out (they leak nothing)
# the sentences of a note's body (40+ characters), with quote, list and quotation marks dropped, so a sentence
# copied into a quote or a list is still the same sentence. With -v want=FILE: print "sentence<TAB>file" for
# each sentence of the given notes that FILE (one sentence per line) also holds
SENT='
  BEGIN { if (want != "") while ((getline w < want) > 0) W[w] = 1 }
  function out(t) { gsub(/^[[:space:]"(>*+-]+|[[:space:]").!?;:]+$/, "", t)
    if (length(t) < 40 || t ~ /^<?https?:\/\/[^ ]*>?$/) return
    if (want == "") print t; else if (t in W) print t "\t" FILENAME }
  FNR == 1 { fm = 0; if (/^---/) { fm = 1; next } }
  fm { if (/^---/) fm = 0; next }
  /^(~~~|Compared:|#)/ { next }
  { l = $0; sub(/^[[:space:]>*+-]+/, "", l); n = split(l, a, /[.!?;:][[:space:]]+/); for (k = 1; k <= n; k++) out(a[k]) }'
sentences() { LC_ALL=C awk -v want="${want:-}" "$SENT" "$@"; }
libchanges() {
  { git -C "$1" status --porcelain -uall --no-renames 2>/dev/null | grep -Ev '^(D.|.D) ' | cut -c4-
    if git -C "$1" rev-parse -q --verify '@{u}' >/dev/null; then git -C "$1" diff --name-only --diff-filter=d '@{u}...HEAD'
    else git -C "$1" diff --name-only --diff-filter=d "$(git -C "$1" rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)" HEAD 2>/dev/null; fi; } | sort -u
}
# a path with .., symlinks and letter case resolved (macOS ignores case); "" when a part that does not exist yet holds ..
real() { d=$1 r=; k=0
  while [ -L "$d" ] && [ $k -lt 20 ]; do t=$(readlink "$d"); case $t in /*) d=$t ;; *) d=${d%/*}/$t ;; esac; k=$((k+1)); done   # a symlinked file
  while [ ! -d "$d" ]; do r="/${d##*/}$r"; d=${d%/*}; [ -n "$d" ] || d=/; done
  case $r in */..|*/../*|*/.|*/./*) return 0 ;; esac; printf '%s%s' "$(cd "$d" && pwd -P)" "$r" | tr 'A-Z' 'a-z'; }
case $rel in projects/?*) project=${rel#projects/}; project=${project%%/*} ;; *) project= ;; esac

# Flat JSON field (hook input is compact JSON); good enough for ids, names and booleans.
jget() { printf '%s' "$in" | sed -n "s/.*\"$1\" *: *\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1; }

sid=$(jget session_id | tr -cd 'A-Za-z0-9_-')
[ -n "$sid" ] || exit 0
st="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/chief-of-staff}/turns/$sid"   # per user, never shared /tmp
mkdir -p "$st"
mark() { : > "$st/$1"; echo x >> "$st/$1.count"; }
count() { [ -f "$st/$1.count" ] && wc -l < "$st/$1.count" | tr -d ' ' || echo 0; }

case $(jget hook_event_name) in
  UserPromptSubmit)
    rm -f "$st"/*
    : > "$st/start"   # notes modified after this are the turn's notes (whatever tool or path wrote them)
    # first use: trust the settings as they are, but only while there is no team to share with
    [ -f "$(cos_cfgrec "$root")" ] || cos_libs "$root" | cut -f1 | grep -qvx personal || cos_cfgsave "$root"
    # what each other team library holds now, so the turn end blames this session only for what it changed there
    cos_libs "$root" | while IFS="$TAB" read -r n q; do [ "$n" = personal ] || [ "$n" = "$lname" ] || [ ! -d "$q/.git" ] && continue
      { git -C "$q" rev-parse -q --verify HEAD; git -C "$q" status --porcelain -uall --no-renames; } > "$st/snap-$n" 2>/dev/null; done
    echo "Chief-of-staff protocol for this request (checked by hooks at the end of the turn):"
    echo "- A deliverable for other people, a decision that crosses areas, or research goes through the specialists skill: at least one specialist and the independent reviewer, as subagents, each briefed with its role card from $root/specialists/ (the brief contains the line 'Role card: <role>' and the card's text)."
    echo "- Research starts in the library: sh \"$L\" search <terms> (workspace: $root). Web search only for what the library lacks. Every new finding, decision, how-to or option becomes a note: sh \"$L\" new <finding|decision|howto|option|topic> <origin> <title>, then fill it. Hooks check every note."
    [ $lst = 0 ] || { sh "$L" where | sed -n 2p; exit 0; }
    # what the company already knows about this request; skipped for an external or very large library (hook time budget)
    case $lib in "$root"/*) ;; *) exit 0 ;; esac
    [ "$(ls "$lib/notes" 2>/dev/null | wc -l)" -le 3000 ] || exit 0
    q=$(printf '%s' "$in" | LC_ALL=C awk '{ s = s $0 " " } END {
      i = index(s, "\"prompt\":"); if (!i) exit; s = substr(s, i + 9); sub(/^ *"/, "", s); o = ""
      for (j = 1; j <= length(s) && length(o) < 300; j++) { c = substr(s, j, 1)
        if (c == "\\") { j++; c = substr(s, j, 1); o = o ((c == "n" || c == "t" || c == "r") ? " " : c); continue }
        if (c == "\"") break; o = o c }
      print o }')
    [ -n "$q" ] && sh "$L" search --auto "$q"
    ;;
  PostToolUse)
    tool=$(jget tool_name)
    case $tool in
      Agent)
        role=$(printf '%s' "$in" | grep -o 'Role card: [a-z-]*' | head -n 1 | sed 's/Role card: //')
        case $role in ''|utility) ;; reviewer) mark reviewer ;; *) mark specialist ;; esac
        mark agent ;;
      WebSearch|WebFetch) mark web ;;
      Write|Edit|MultiEdit)
        # jget stops at a comma: read the whole string, and trust it only if the raw input closes it right after
        fp=$(printf '%s' "$in" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1); ok=
        case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*) ok=1 ;; esac
        nope() { echo x >> "$st/rejected.count"; echo "Library note rejected: $1" >&2; exit 2; }
        # the library that holds the file, whichever it is (the session's, personal or another team's)
        wl=/nonexistent-library; wn=
        if [ "$ok" = 1 ]; then
          o=$(cos_libs "$root" | while IFS="$TAB" read -r n q; do case $fp in ("$q"/*) printf '%s\t%s\n' "$n" "$q"; break ;; esac; done)
          [ -n "$o" ] && { wn=${o%%"$TAB"*}; wl=${o#*"$TAB"}; }
        fi
        pers=$(cos_lib "$root")
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
          *.md\"*|*.html\"*|*.pptx\"*|*.docx\"*|*.pdf\"*) case $in in *STATE.md\"*|*"/board/"*) ;; *) ctl=; fp=$(jget file_path); r=${fp#"$root/projects/"}
              # only a project's own TRACK.md / DELIVERY.md (projects/<slug>/FILE) is a control file; the path comes from file_path, not from the content
              # jget stops at , } or a quote: trust fp only if the raw input closes the string right after it
              case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*) ;; *) r= ;; esac
              case $r in */*/*|.*) ;; */TRACK.md|*/DELIVERY.md) [ "$r" != "$fp" ] && ctl=1 ;; esac
              [ -n "$ctl" ] || mark deliverable ;; esac ;;
        esac ;; esac ;;
    esac
    case $in in *library.sh*search*|*"$lib/"*|*"$root/knowledge"*) [ "$tool" = Write ] || [ "$tool" = Edit ] || mark library ;; esac
    ;;
  PreToolUse)
    case $(jget tool_name) in
      Agent)
        role=$(printf '%s' "$in" | grep -o 'Role card: [a-z-]*' | head -n 1 | sed 's/Role card: //')
        [ "$role" = utility ] && exit 0
        if [ -n "$role" ] && [ -f "$root/specialists/$role.md" ]; then
          case $in in *"Library:"*) exit 0 ;; esac
          echo "Blocked by chief-of-staff: the brief must carry what the library already knows. Add a line 'Library: [[id]] [[id]] ...' with the notes from library.sh search, or 'Library: none found for <terms>'." >&2
          exit 2
        fi
        cards=$(ls "$root/specialists" 2>/dev/null | sed -n 's/\.md$//p' | tr '\n' ' ')
        echo "Blocked by chief-of-staff: every subagent brief names its role card. Add the line 'Role card: <role>' and paste the card's text from $root/specialists/<role>.md. Cards: ${cards:-none found}. For a search or file-reading helper, write 'Role card: utility'." >&2
        exit 2 ;;
      WebSearch|WebFetch)
        [ -f "$st/library" ] && exit 0
        # only a library that is really absent (disk unplugged) lets research go on without it; a broken one does not
        [ $lst = 1 ] && { mark offline; exit 0; }
        [ $lst = 0 ] || { sh "$L" where | sed -n 2p >&2; exit 2; }
        echo "Blocked by chief-of-staff: search the library first, then search the web only for what it lacks. Run: sh \"$(dirname "$0")/library.sh\" search <terms>" >&2
        exit 2 ;;
      Write|Edit|MultiEdit|Bash)   # the marker says where the library lives: only the owner edits it
        lc=$(printf '%s' "$in" | tr 'A-Z' 'a-z')   # macOS file names ignore case: .CHIEF-OF-STAFF is the marker
        case $(jget tool_name) in
          Bash)
            # ponytail: a word list, not a shell parser; the files are also read-only on disk (offload, setup).
            # A command that names them and could write them is blocked
            blk=
            # the command alone, JSON escapes undone enough for matching (\t, \n, \" become plain)
            cq=$(printf '%s' "$lc" | sed -nE 's/.*"command" *: *"(([^"\\]|\\.)*)".*/\1/p' | sed 's/\\[tn]/ /g; s/\\"/"/g' | head -n 1)
            uq=$(printf '%s' "$cq" | tr -d "\"'\\\\")
            # the names, or a glob that could spell them (.[c]hief, .l*, .ch?ef, ?library), next to a write.
            # ponytail: a name built in a variable (a=.chi; ...${a}ef) is not seen; the files are read-only on disk
            sus=; case $uq in *.chief*|*.library*|*cos-foreign*|*cos-cfg*) sus=1 ;; esac   # not "chief-of-staff": the plugin's own folder has that name
            printf '%s\n' "$uq" | grep -Eq '\.[][?*]|(^|[^a-z0-9_.-])\.(c(h(i(e(f)?)?)?)?|l(i(b(r(a(r(y)?)?)?)?)?)?)([^a-z0-9_-]|$)|[][?*](l?ibrary|c?hief)|(^|[^$])\{[^}]*,[^}]*\}' && sus=1   # also {.,x}library
            case $cq in *"\$'"*) sus=1 ;; esac   # $'\056library' (quotes are gone from uq)
            # whole words only: a folder named "firmware" or a random temp name is not rm
            # 2>&1 and >/dev/null write nothing
            case $sus in 1) case $(printf '%s' "$uq" | sed 's|[0-9]*>&[0-9]||g; s|[0-9]*>> */dev/null||g; s|[0-9]*> */dev/null||g') in *">"*) blk=1 ;; *) printf ' %s \n' "$uq" |
              grep -Eq '[^a-z0-9_.-](tee|sed|mv|cp|rm|perl[0-9.]*|python[0-9.]*|ln|dd|install|rsync|touch|g?awk|truncate|chmod|chflags|unlink|node|ruby|php|git|ed|ex)([^a-z0-9_.-]|$)' && blk=1 ;; esac ;; esac
            if [ -z "$blk" ]; then
              # ponytail: a word match, not a shell parser (a renamed copy of library.sh is not seen). Quotes,
              # backslashes and tabs are dropped first, so u''se or "join" count; a subcommand from a variable,
              # $(...), stdin or another command after library.sh asks too
              nq=$(printf '%s' "$cq" | tr -d "\"'\\\\")
              # moving the library sends every note somewhere: the owner confirms each time
              case $nq in *library.sh*off*|*offload*)
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this moves the whole library (and may push it to a git remote). Only approve if you asked for it."}}' ;;
              # any use, join or leave word after library.sh (a search for "use" asks too: rare, and safe)
              *) printf '%s\n' "$nq" | grep -Eq 'library\.sh(.*[^a-z0-9_-](use|join|leave|trust)([^a-z0-9_-]|$)|[^;&|]*[$`]| *([;&|)]|$))' &&
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this changes which library a project uses, or connects or disconnects a team library: what is shared with whom. Only approve if you asked for it."}}' ;; esac
              exit 0
            fi ;;
          *) # each session writes only its own library: a team's notes never come from a personal or another
             # team's session. The path is resolved (.., symlinks, letter case) before it is compared
             fp=$(printf '%s' "$in" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1)
             case $fp in /*) rp=$(real "$fp")
               [ -n "$rp" ] || { echo "Blocked by chief-of-staff: write $fp by its plain path, without . or .. parts." >&2; exit 2; } ;; *) rp= ;; esac
             o=$(cos_libs "$root" | while IFS="$TAB" read -r n q; do [ -d "$q" ] || continue
               case $rp in ("$(cd "$q" && pwd -P | tr 'A-Z' 'a-z')"/*) echo "$n"; break ;; esac; done)
             case $rp in */.git/*|*/.git) [ -n "$o" ] && { echo "Blocked by chief-of-staff: $fp is inside the git data of the library '$o'; sync.sh keeps it." >&2; exit 2; } ;; esac
             if [ -n "$o" ] && [ "$o" != "$lname" ]; then
               echo "Blocked by chief-of-staff: $fp is in the library '$o', and this session works in '$lname'. A session writes only its own library, so nothing personal or from another team leaks into a shared one. Write the note in $lib/notes/." >&2; exit 2
             fi
             case $(printf '%s' "$lc" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1) in */.chief-of-staff|*/.library-id|*/.library|*/.chief-of-staff/*) ;; *) exit 0 ;; esac ;;
        esac
        echo "Blocked by chief-of-staff: .chief-of-staff (where the libraries live), .library-id and a project's .library (which library it shares with) are changed only through library.sh offload, join, leave or use, which the owner confirms." >&2
        exit 2 ;;
    esac
    ;;
  SubagentStop)
    [ "$(jget stop_hook_active)" = true ] && exit 0
    case $in in *"Role: utility"*) exit 0 ;; *"Role: "*) ;; *) exit 0 ;; esac
    case $in in *"Never-skip checklist"*) exit 0 ;; esac
    echo "Your role card requires a '## Never-skip checklist' section: mark each item of your card's 'Never skip' list as done or not applicable (why). Add it, then finish." >&2
    exit 2
    ;;
  Stop)
    # a question to the owner is timed from when it was asked (asked:), not from a file date that git resets
    for c in "$root"/board/*.md; do
      [ -f "$c" ] || continue; a=$(fm_get "$c" asked)
      if [ "$(fm_get "$c" status)" = waiting-owner ]; then [ -n "$a" ] || fm_set "$c" asked "$(date '+%F %H:%M')"
      elif [ -n "$a" ]; then fm_set "$c" asked ""; fi
    done
    # ponytail: "substantive" is a heuristic (deliverable file, web research, or a long answer);
    # replace with a model-graded check if it misfires in real use.
    size=$(printf '%s' "$in" | wc -c | tr -d ' ')
    substantive=0
    { [ -f "$st/deliverable" ] || [ -f "$st/web" ] || [ "$size" -gt 2500 ]; } && substantive=1
    agents=$(count agent); specialists=$(count specialist); reviewers=$(count reviewer)
    reason=
    [ "$substantive" = 1 ] && { [ "$specialists" -lt 1 ] || [ "$reviewers" -lt 1 ]; } && reason="This turn produced a deliverable, research or a long answer with $specialists specialist(s) and $reviewers reviewer(s). Before finishing, run the specialists skill: at least one senior specialist and the independent reviewer as subagents, each briefed with its role card from $root/specialists/, then revise the answer with what they found."
    [ -f "$st/web" ] && [ ! -f "$st/saved" ] && [ $lst = 0 ] && reason="${reason:+$reason }This turn searched the web but saved nothing to the library. Save each new finding as a note in $lib/notes/ (sh \"$L\" new ...) before finishing."
    lgaps=; push=
    gap() { lgaps="${lgaps:+$lgaps
}$1"; }
    if [ -f "$st/start" ]; then
      while IFS="$TAB" read -r n q; do
        [ -n "$n" ] || continue
        cos_libpath "$root" "$n" >/dev/null || continue   # offline or broken: nothing to gate there
        team=; [ "$n" != personal ] && [ -d "$q/.git" ] && team=1
        if [ -n "$team" ]; then
          # what would leave this computer: every path git sees changed here or committed and not pushed
          # (a teammate's pulled note is neither), so the push set is exactly the gated set
          ch=$(libchanges "$q")
        else
          # ctime, not mtime: mv, cp -p or touch -t keep or set an old mtime, never an old ctime
          ch=$(find "$q/notes" -name '*.md' -type f -cnewer "$st/start" 2>/dev/null | while IFS= read -r f; do printf '%s\n' "${f#"$q/"}"; done)
        fi
        [ -n "$ch" ] || continue
        if [ "$n" != "$lname" ]; then   # changed by hand (Bash) from a session of another library: never pushed by anyone
          if [ -n "$team" ] && [ -f "$st/snap-$n" ]; then
            # only what changed during this turn: another session's pending notes there are not this session's
            h0=$(head -n 1 "$st/snap-$n"); tail -n +2 "$st/snap-$n" > "$st/snap0"
            mine=$( { git -C "$q" status --porcelain -uall --no-renames 2>/dev/null | grep -vxF -f "$st/snap0" | cut -c4-
              [ -n "$h0" ] && git -C "$q" log --format= --name-only "$h0..HEAD" --not '@{u}' 2>/dev/null; } | grep . | sort -u)
            [ -n "$mine" ] && { printf '%s\n' "$mine" >> "$q/.git/cos-foreign"
              gap "Notes changed in the team library '$n', which this session does not use ('$lname'): $(printf '%s' "$mine" | tr '\n' ' ')
Restore only those files in $q (git checkout -- <file>, or delete it if it is new) and write in $lib/notes/."; }
          fi
          continue
        fi
        bad=; set --
        while IFS= read -r f; do
          case $f in
            notes/.gitkeep) continue ;;
            notes/*/*|*' '*|*'"'*) bad="$bad $f" ;;
            notes/*.md) [ -n "$team" ] && [ -f "$q/.git/cos-foreign" ] && grep -qxF "$f" "$q/.git/cos-foreign" &&
                { gap "$q/$f was written from a session of another library: delete it (git -C \"$q\" checkout -- $f, or rm it if new); its project's session writes it."; continue; }
              set -- "$@" "$q/$f" ;;
            *) bad="$bad $f" ;;
          esac
        done <<CH
$ch
CH
        [ -n "$team" ] && dl=$(git -C "$q" status --porcelain --no-renames -- notes 2>/dev/null | grep -E '^(D.|.D) ' | cut -c4- | tr '\n' ' ') &&
          [ -n "$dl" ] && gap "Deleting a note does not reach the team library '$n': retire it instead (library.sh retire), then restore the file (git -C \"$q\" checkout -- $dl)."
        [ -n "$team" ] && [ -n "$bad" ] && gap "Only notes (notes/<id>.md) go to the team library '$n'. Remove or move these first:$bad"
        [ -n "$team" ] && [ -f "$q/.git/cos-foreign" ] && { printf '%s\n' "$ch" | grep -xF -f - "$q/.git/cos-foreign" > "$q/.git/cos-foreign.new"; mv -f "$q/.git/cos-foreign.new" "$q/.git/cos-foreign"; }
        [ $# -gt 0 ] || continue
        if [ $# -gt 20 ]; then gap "More than 20 notes changed in '$n'; only 20 can be checked in one turn: run library.sh --lib $n doctor, and save fewer notes per turn."; set --; fi
        [ $# -gt 0 ] || continue
        g=$(sh "$L" --lib "$n" gate "$@" | grep -v ': warning: ' | head -n 20)
        [ -n "$g" ] && gap "$g"
        if [ -n "$team" ]; then
          # a verbatim copy carries no [[link]]: a sentence of 40+ characters found in another library blocks it.
          # Body prose only (a shared source link is not a copy); one pass per other library, inside the hook's 5 s
          sentences "$@" | sort -u > "$st/lines"
          if [ -s "$st/lines" ]; then
            cos_libs "$root" | while IFS="$TAB" read -r n2 q2; do [ "$n2" = "$n" ] || [ ! -d "$q2/notes" ] && continue
              find "$q2/notes" -name '*.md' -type f -exec env LC_ALL=C awk -v want="$st/lines" "$SENT" {} + 2>/dev/null; done > "$st/hits"
            if [ -s "$st/hits" ]; then for f in "$@"; do
              o=$(sentences "$f" | while IFS= read -r t; do awk -F "$TAB" -v t="$t" '$1 == t { print $2; exit }' "$st/hits"; done | head -n 1)
              [ -n "$o" ] && gap "$f: copies text from $o, a note of another library. A team note is written for the team, not copied from personal or another team's notes: drop the copied text, and if the owner wants that fact shared, ask them and state it in new words."
            done; fi
          fi
          [ -z "$lgaps" ] && push="$q"
          for f in "$@"; do push="$push$TAB${f#"$q/"}"; done
        fi
      done <<LIBS
$(cos_libs "$root")
LIBS
    fi
    # team notes that passed go to the team now, in the background (the hook has 5 s); conflicts become a card.
    # Only this session's library, only the files just gated, and only when nothing in this turn failed
    if [ -z "$lgaps" ] && [ -n "$push" ]; then
      ( IFS=$TAB; set -f; set -- $push; q=$1; shift
        sh "$(dirname "$0")/sync.sh" push "$q" "${project:-central}" "$root" "$@" </dev/null >/dev/null 2>&1 & )
    fi
    r=$(cos_cfgrec "$root")
    [ ! -f "$r" ] && cos_libs "$root" | cut -f1 | grep -qvx personal && gap "The record of the library settings is missing. Ask the owner to check library.sh libs from central and confirm library.sh trust."
    [ -f "$r" ] && [ "$(cat "$r")" != "$(cos_cfg "$root")" ] && gap "The library settings (.chief-of-staff or a project's .library) changed without library.sh join, use or leave, which the owner approves. Restore them: git -C \"$root\" checkout -- .chief-of-staff projects (or delete a new .library)."
    [ -n "$lgaps" ] && reason="${reason:+$reason }Library notes written this turn have problems:
$lgaps
Fix each note (format: $lib/templates/note.md). When a new note is better than an old one, or merges several, retire the old: sh \"$L\" retire <old-id> <new-id> \"<why it lost>\". Valid alternatives stay: write [[id]] coexists (reason)."
    gaps=
    [ -n "$project" ] && gaps=$(sh "$(dirname "$0")/track.sh" check "$root/projects/$project" | head -n 20)
    [ -n "$gaps" ] && reason="${reason:+$reason }Track gate (projects/$project/TRACK.md) not met:
$gaps
Close each item with its proof file (evidence: path relative to the project folder), mark it [-] with why: when it does not apply, or move stage: back. A stage passes only when every item is closed."
    pushed=$(jget stop_hook_active)
    violation=0; [ "$pushed" = true ] && [ -n "$reason" ] && violation=1
    printf '%s t=%s turn=%s project=%s substantive=%s agents=%s specialists=%s reviewers=%s library=%s web=%s saved=%s track=%s pushed=%s violation=%s notes=%s offline=%s rejected=%s\n' \
      "$(date '+%F %T')" "$(date +%s)" "$sid" "${project:--}" "$substantive" "$agents" "$specialists" "$reviewers" \
      "$([ -f "$st/library" ] && echo 1 || echo 0)" "$([ -f "$st/web" ] && echo 1 || echo 0)" "$([ -f "$st/saved" ] && echo 1 || echo 0)" \
      "$(printf '%s' "$gaps" | grep -c .)" "${pushed:-false}" "$violation" "$(printf '%s' "$lgaps" | grep -c .)" "$([ $lst = 0 ] && echo 0 || echo 1)" "$(count rejected)" >> "$root/.protocol.log"
    [ "$pushed" = true ] && exit 0
    [ -n "$reason" ] || exit 0
    echo "$reason" >&2
    exit 2
    ;;
esac
exit 0
