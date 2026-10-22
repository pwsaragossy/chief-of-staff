#!/bin/sh
# Protocol gates. One script for four hook events, so the rules live in one place:
#   UserPromptSubmit  starts a new turn record and restates the protocol (every turn, survives compaction)
#   PostToolUse       records what the turn did: specialists (Agent), library lookups, web research, saves
#   PreToolUse        on WebSearch/WebFetch: blocked until the library was searched this turn
#   Stop              blocks the end of a substantive turn that skipped specialists, or researched
#                     without saving to the library. One push per turn (stop_hook_active), then it lets go.
# Silent outside a workspace. Every turn is logged to <workspace>/.protocol.log (the adherence metric).
. "$(dirname "$0")/lib.sh"

in=$(cat)
root=$(cos_root "${CLAUDE_PROJECT_DIR:-$PWD}") || exit 0

# Flat JSON field (hook input is compact JSON); good enough for ids, names and booleans.
jget() { printf '%s' "$in" | sed -n "s/.*\"$1\" *: *\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1; }

sid=$(jget session_id | tr -cd 'A-Za-z0-9_-')
[ -n "$sid" ] || exit 0
st="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/chief-of-staff}/turns/$sid"
mkdir -p "$st"
mark() { : > "$st/$1"; echo x >> "$st/$1.count"; }
count() { [ -f "$st/$1.count" ] && wc -l < "$st/$1.count" | tr -d ' ' || echo 0; }

case $(jget hook_event_name) in
  UserPromptSubmit)
    rm -f "$st"/*
    echo "Chief-of-staff protocol for this request (checked by hooks at the end of the turn):"
    echo "- A deliverable for other people, a decision that crosses areas, or research goes through the specialists skill: at least one specialist and one independent reviewer, as subagents."
    echo "- Research starts in the library: sh \"$(dirname "$0")/library.sh\" search <terms> (workspace: $root). Web search only for what the library lacks, and every new finding is saved as a note in $root/knowledge/notes/."
    ;;
  PostToolUse)
    tool=$(jget tool_name)
    case $tool in
      Agent) mark agent ;;
      WebSearch|WebFetch) mark web ;;
      Write|Edit|MultiEdit)
        case $in in
          *"$root/knowledge/"*) mark saved ;;
          *.md\"*|*.html\"*|*.pptx\"*|*.docx\"*|*.pdf\"*) case $in in *STATE.md\"*|*"/board/"*) ;; *) mark deliverable ;; esac ;;
        esac ;;
    esac
    case $in in *library.sh*search*|*"$root/knowledge"*) [ "$tool" = Write ] || [ "$tool" = Edit ] || mark library ;; esac
    ;;
  PreToolUse)
    case $(jget tool_name) in
      WebSearch|WebFetch)
        [ -f "$st/library" ] && exit 0
        echo "Blocked by chief-of-staff: search the library first, then search the web only for what it lacks. Run: sh \"$(dirname "$0")/library.sh\" search <terms>" >&2
        exit 2 ;;
    esac
    ;;
  Stop)
    # ponytail: "substantive" is a heuristic (deliverable file, web research, or a long answer);
    # replace with a model-graded check if it misfires in real use.
    size=$(printf '%s' "$in" | wc -c | tr -d ' ')
    substantive=0
    { [ -f "$st/deliverable" ] || [ -f "$st/web" ] || [ "$size" -gt 2500 ]; } && substantive=1
    agents=$(count agent)
    printf '%s turn=%s substantive=%s agents=%s library=%s web=%s saved=%s pushed=%s\n' "$(date '+%F %T')" "$sid" \
      "$substantive" "$agents" "$([ -f "$st/library" ] && echo 1 || echo 0)" "$([ -f "$st/web" ] && echo 1 || echo 0)" \
      "$([ -f "$st/saved" ] && echo 1 || echo 0)" "$(jget stop_hook_active)" >> "$root/.protocol.log"
    [ "$(jget stop_hook_active)" = true ] && exit 0
    reason=
    [ "$substantive" = 1 ] && [ "$agents" -lt 2 ] && reason="This turn produced a deliverable, research or a long answer with $agents subagent call(s). Before finishing, run the specialists skill: at least one senior specialist and one independent reviewer as subagents, then revise the answer with what they found."
    [ -f "$st/web" ] && [ ! -f "$st/saved" ] && reason="${reason:+$reason }This turn searched the web but saved nothing to the library. Save each new finding as a note in $root/knowledge/notes/ (template in knowledge/templates/note.md) before finishing."
    [ -n "$reason" ] || exit 0
    echo "$reason" >&2
    exit 2
    ;;
esac
exit 0
