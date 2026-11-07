#!/bin/sh
# The release check, sized to what changed since the last release: the module tests always (seconds); the full
# selftest (minutes) only when something it reads changed: scripts, templates, skills, hooks.json or the README.
# ALL=1 runs the full selftest anyway.
set -u
cd "$(dirname "$0")/.." || exit 1
base=$(git log -1 --format=%h --grep='^Release ')
changed=$( { git diff --name-only "${base:-HEAD}"; git ls-files --others --exclude-standard; } | sort -u)
echo "changed since ${base:-HEAD}:"; printf '  %s\n' $changed
claude plugin validate . >/dev/null || { echo "FAIL claude plugin validate"; exit 1; }
claude plugin test . || exit 1
if [ "${ALL:-}" = 1 ] || printf '%s\n' "$changed" | grep -Eq '^(scripts/|templates/|skills/|hooks/hooks\.json$|README\.md$)'; then
  log=$(mktemp); sh scripts/selftest.sh > "$log" 2>&1; r=$?; grep '^FAIL' "$log"; tail -n 1 "$log"; rm -f "$log"; exit $r
fi
echo "selftest skipped: nothing it reads changed (ALL=1 runs it)"
