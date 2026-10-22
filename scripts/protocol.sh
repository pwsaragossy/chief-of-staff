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
lib=$(cos_lib "$root"); lst=$?   # the library folder; lst != 0: offline or misconfigured (library.sh where)
L="$(dirname "$0")/library.sh"
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
        fp=$(jget file_path); ok=
        case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*) ok=1 ;; esac
        case "$ok:$fp" in
          1:"$lib/notes/"*.md)   # a note: checked now, while the agent still has it in context
            printf '%s\n' "$fp" >> "$st/notes"
            if p=$(sh "$L" check "$fp"); then mark saved; [ -n "$p" ] && echo "$p"
            else echo "Library note rejected: fix it now, in $fp:
$p" >&2; exit 2; fi ;;
          1:"$lib/"*|1:"$root/knowledge/"*) ;;   # inbox and templates: not a note, not a deliverable
          *) case $in in
          *.md\"*|*.html\"*|*.pptx\"*|*.docx\"*|*.pdf\"*) case $in in *STATE.md\"*|*"/board/"*) ;; *) ctl=; fp=$(jget file_path); r=${fp#"$root/projects/"}
              # only a project's own TRACK.md / DELIVERY.md (projects/<slug>/FILE) is a control file; the path comes from file_path, not from the content
              # jget stops at , } or a quote: trust fp only if the raw input closes the string right after it
              case $in in *"\"file_path\":\"$fp\""*|*"\"file_path\": \"$fp\""*) ;; *) r= ;; esac
              case $r in */*/*|.*) ;; */TRACK.md|*/DELIVERY.md) [ "$r" != "$fp" ] && ctl=1 ;; esac
              [ -n "$ctl" ] || mark deliverable ;; esac ;;
        esac ;; esac ;;
      Bash)   # notes written by a shell command bypass the check above; the turn-end gate catches them
        printf '%s' "$in" | LIB="$lib/notes/" awk '{ s = s $0 } END { l = ENVIRON["LIB"]
          while ((i = index(s, l))) { s = substr(s, i); match(s, /^[^"\047 <>|;&]*/); t = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
            sub(/\\$/, "", t); if (t ~ /\.md$/) print t } }' >> "$st/notes" ;;
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
        [ $lst = 0 ] || { mark offline; exit 0; }   # library unreachable: research goes on, the turn is logged offline=1
        echo "Blocked by chief-of-staff: search the library first, then search the web only for what it lacks. Run: sh \"$(dirname "$0")/library.sh\" search <terms>" >&2
        exit 2 ;;
      Write|Edit|MultiEdit|Bash)   # the marker says where the library lives: only the owner edits it
        case $(jget tool_name) in
          Bash) case $in in *.chief-of-staff*) case $in in *">"*|*"tee "*|*"sed -i"*|*"mv "*|*"cp "*|*"rm "*|*perl*|*python*|*"ln "*) ;; *) exit 0 ;; esac ;; *) exit 0 ;; esac ;;
          *) [ "$(jget file_path)" = "$root/.chief-of-staff" ] || exit 0 ;;
        esac
        echo "Blocked by chief-of-staff: $root/.chief-of-staff marks the workspace and says where the library lives; agents do not change it. To move the library, central runs library.sh offload after the owner agrees." >&2
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
    # ponytail: "substantive" is a heuristic (deliverable file, web research, or a long answer);
    # replace with a model-graded check if it misfires in real use.
    size=$(printf '%s' "$in" | wc -c | tr -d ' ')
    substantive=0
    { [ -f "$st/deliverable" ] || [ -f "$st/web" ] || [ "$size" -gt 2500 ]; } && substantive=1
    agents=$(count agent); specialists=$(count specialist); reviewers=$(count reviewer)
    reason=
    [ "$substantive" = 1 ] && { [ "$specialists" -lt 1 ] || [ "$reviewers" -lt 1 ]; } && reason="This turn produced a deliverable, research or a long answer with $specialists specialist(s) and $reviewers reviewer(s). Before finishing, run the specialists skill: at least one senior specialist and the independent reviewer as subagents, each briefed with its role card from $root/specialists/, then revise the answer with what they found."
    [ -f "$st/web" ] && [ ! -f "$st/saved" ] && [ $lst = 0 ] && reason="${reason:+$reason }This turn searched the web but saved nothing to the library. Save each new finding as a note in $root/knowledge/notes/ (template in knowledge/templates/note.md) before finishing."
    lgaps=
    if [ -s "$st/notes" ] && [ $lst = 0 ]; then
      set --
      while IFS= read -r f; do [ -f "$f" ] && set -- "$@" "$f"; done <<NOTES
$(sort -u "$st/notes" | head -n 20)
NOTES
      [ $# -gt 0 ] && lgaps=$(sh "$L" gate "$@" | grep -v ': warning: ' | head -n 20)
    fi
    [ -n "$lgaps" ] && reason="${reason:+$reason }Library notes written this turn have problems:
$lgaps
Fix each note (format: $root/knowledge/templates/note.md). When a new note is better than an old one, or merges several, retire the old: sh \"$L\" retire <old-id> <new-id> \"<why it lost>\". Valid alternatives stay: write [[id]] coexists (reason)."
    gaps=
    [ -n "$project" ] && gaps=$(sh "$(dirname "$0")/track.sh" check "$root/projects/$project" | head -n 20)
    [ -n "$gaps" ] && reason="${reason:+$reason }Track gate (projects/$project/TRACK.md) not met:
$gaps
Close each item with its proof file (evidence: path relative to the project folder), mark it [-] with why: when it does not apply, or move stage: back. A stage passes only when every item is closed."
    pushed=$(jget stop_hook_active)
    violation=0; [ "$pushed" = true ] && [ -n "$reason" ] && violation=1
    printf '%s t=%s turn=%s project=%s substantive=%s agents=%s specialists=%s reviewers=%s library=%s web=%s saved=%s track=%s pushed=%s violation=%s notes=%s offline=%s\n' \
      "$(date '+%F %T')" "$(date +%s)" "$sid" "${project:--}" "$substantive" "$agents" "$specialists" "$reviewers" \
      "$([ -f "$st/library" ] && echo 1 || echo 0)" "$([ -f "$st/web" ] && echo 1 || echo 0)" "$([ -f "$st/saved" ] && echo 1 || echo 0)" \
      "$(printf '%s' "$gaps" | grep -c .)" "${pushed:-false}" "$violation" "$(printf '%s' "$lgaps" | grep -c .)" "$([ $lst = 0 ] && echo 0 || echo 1)" >> "$root/.protocol.log"
    [ "$pushed" = true ] && exit 0
    [ -n "$reason" ] || exit 0
    echo "$reason" >&2
    exit 2
    ;;
esac
exit 0
