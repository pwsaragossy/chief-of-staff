#!/bin/sh
# SessionStart hook: prints a short factual briefing when the session opens inside a workspace.
# Silent anywhere else, so installing the plugin does not touch unrelated projects.
. "$(dirname "$0")/lib.sh"

dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || exit 0
rel=${dir#"$root"}
rel=${rel#/}

out() { printf '%s\n' "$*"; }

waiting() { # list cards waiting on the owner; $1 = project slug filter (empty = all)
  for c in "$root"/board/*.md; do
    [ -f "$c" ] || continue
    [ "$(fm_get "$c" status)" = "waiting-owner" ] || continue
    [ -z "$1" ] || [ "$(fm_get "$c" project)" = "$1" ] || continue
    out "- $(basename "$c" .md) (project: $(fm_get "$c" project), since $(fm_get "$c" updated))"
  done
}

{
  out "Chief-of-staff workspace: $root"
  case $rel in
    central|central/*)
      out "This session is central: the only one that asks the owner. Cards waiting on the owner:"
      w=$(waiting ""); out "${w:-- none}"
      out "Projects:"
      for s in "$root"/projects/*/STATE.md; do
        [ -f "$s" ] || continue
        p=$(basename "$(dirname "$s")")
        out "- $p: status $(fm_get "$s" status), updated $(fm_get "$s" updated), next: $(fm_get "$s" next)"
      done
      n=$(ls "$root"/knowledge/inbox 2>/dev/null | wc -l | tr -d ' ')
      out "Knowledge inbox: $n item(s) waiting to be processed."
      ;;
    projects/*)
      p=${rel#projects/}; p=${p%%/*}
      s="$root/projects/$p/STATE.md"
      out "This session is the agent of project '$p'. It does not ask the owner; questions go to the project card with status waiting-owner."
      if [ -f "$s" ]; then
        out "STATE.md: status $(fm_get "$s" status), updated $(fm_get "$s" updated), dispatch $(fm_get "$s" dispatch)."
        out "Next action recorded: $(fm_get "$s" next)"
        out "Protocol: the arrival synthesis in STATE.md is written before any other action."
      fi
      w=$(waiting "$p"); [ -n "$w" ] && { out "Cards of this project waiting on the owner:"; out "$w"; }
      notes=$(for f in "$root"/knowledge/notes/*.md; do
        [ -f "$f" ] && [ "$(fm_get "$f" status)" = "new" ] || continue
        case "[$(fm_get "$f" projects | tr -d '[] ')]," in
          (*"[$p]"*|*"[$p,"*|*",$p,"*|*",$p]"*) out "- $(basename "$f" .md) (confidence $(fm_get "$f" confidence))" ;;
        esac
      done)
      [ -n "$notes" ] && { out "New knowledge notes linked to this project, to integrate or discard:"; out "$notes"; }
      ;;
    *)
      out "This session is outside central/ and projects/. It does not ask the owner either."
      ;;
  esac
} | awk '{ n += length($0) + 1; if (n > 1900) { print "(briefing truncated: read the board and STATE.md for the rest)"; exit } print }'
