#!/bin/sh
# PreToolUse hook on AskUserQuestion: only a project's coordinator asks the owner. In a project folder (marker kind:
# project) that is the session at its registered root (lib.sh cos_owner); hooks/projects.tsx also stops a thread the
# coordinator started there. In the older workspace layout, central/ and a session in projects/<slug>/.
# Exit 2 blocks the tool call and shows stderr to the model.
. "$(dirname "$0")/lib.sh"

dir=${CLAUDE_PROJECT_DIR:-$PWD}
root=$(cos_root "$dir") || exit 0
cos_owner "$root" "$dir" && exit 0
cos_isproj "$root" || case ${dir#"$root"/} in
  central|central/*|projects/?*) exit 0 ;;
esac
echo "Blocked by chief-of-staff: only the project's coordinator (the owner's conversation at the root of the project folder) asks the owner. Write the question as one line on the project's card in $root/board/ with status: waiting-owner, recommendation first, then continue with the work that does not depend on it. (To confirm the origin of an order before an irreversible step, ask in one plain sentence instead.)" >&2
exit 2
