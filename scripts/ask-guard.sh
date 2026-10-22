#!/bin/sh
# PreToolUse hook on AskUserQuestion: inside a workspace, only central/ may ask the owner.
# Exit 2 blocks the tool call and shows stderr to the model.
. "$(dirname "$0")/lib.sh"

dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || exit 0
case ${dir#"$root"/} in
  central|central/*) exit 0 ;;
esac
echo "Blocked by chief-of-staff: only the central session asks the owner. Write the question as one line on this project's card in $root/board/ with status: waiting-owner, recommendation first, then continue with the work that does not depend on it. (To confirm the origin of an order before an irreversible step, ask in one plain sentence instead.)" >&2
exit 2
