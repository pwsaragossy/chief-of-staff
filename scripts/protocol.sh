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
            case $lc in *.chief*|*.library*) case $lc in *">"*|*tee*|*sed*|*mv*|*cp*|*rm*|*perl*|*python*|*ln*|*dd*|*install*|*rsync*|*touch*|*awk*|*truncate*|*chmod*|*chflags*|*unlink*|*node*|*ruby*|*php*|*git*|*ed\ *|*ex\ *) blk=1 ;; esac ;; esac
            if [ -z "$blk" ]; then
              # moving the library sends every note somewhere: the owner confirms each time
              case $lc in *library.sh*off*|*offload*)
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this moves the whole library (and may push it to a git remote). Only approve if you asked for it."}}' ;;
              *library.sh*" use "*|*library.sh*" join "*|*library.sh*" leave "*)
                echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"chief-of-staff: this changes which library a project uses, or connects or disconnects a team library: what is shared with whom. Only approve if you asked for it."}}' ;; esac
              exit 0
            fi ;;
          *) case $(printf '%s' "$lc" | sed -n 's/.*"file_path" *: *"\([^"]*\)".*/\1/p' | head -n 1) in */.chief-of-staff|*/.library-id|*/.library|*/.chief-of-staff/*) ;; *) exit 0 ;; esac ;;
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
    if [ -f "$st/start" ]; then
      while IFS="$TAB" read -r n q; do
        [ -n "$n" ] || continue
        cos_libpath "$root" "$n" >/dev/null || continue   # offline or broken: nothing to gate there
        # ctime, not mtime: mv, cp -p or touch -t keep or set an old mtime, never an old ctime
        ch=$(find "$q/notes" -name '*.md' -type f -cnewer "$st/start" 2>/dev/null | head -n 21)
        [ -n "$ch" ] || continue
        more=; [ "$(printf '%s\n' "$ch" | wc -l)" -gt 20 ] && more="More than 20 notes changed this turn in '$n'; only 20 were checked: run library.sh --lib $n doctor."
        set --; while IFS= read -r f; do [ -n "$f" ] && set -- "$@" "$f"; done <<NOTES
$(printf '%s\n' "$ch" | head -n 20)
NOTES
        g=$(sh "$L" --lib "$n" gate "$@" | grep -v ': warning: ' | head -n 20)${more:+
$more}
        if [ -n "$g" ]; then lgaps="${lgaps:+$lgaps
}$g"; elif [ "$n" != personal ]; then push="$push$q$TAB"; fi
      done <<LIBS
$(cos_libs "$root")
LIBS
    fi
    # team notes that passed go to the team now, in the background (the hook has 5 s); conflicts become a card
    printf '%s' "$push" | tr "$TAB" '\n' | while IFS= read -r q; do
      [ -n "$q" ] && sh "$(dirname "$0")/sync.sh" push "$q" "${project:-central}" "$root" </dev/null >/dev/null 2>&1 &
    done
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
