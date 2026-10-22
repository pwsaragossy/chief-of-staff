# Shared helpers. Sourced by the other scripts; POSIX sh, no GNU- or macOS-only flags.

# Print the workspace root (the nearest folder holding a .chief-of-staff marker) or fail.
cos_root() {
  d=${1:-$PWD}
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.chief-of-staff" ] && { printf '%s\n' "$d"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}

# fm_get FILE KEY -> value of KEY in the YAML front matter (first --- block), empty if absent.
# Tolerates CRLF line endings.
fm_get() {
  K=$2 awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, ENVIRON["K"] ":") == 1 { v = substr($0, length(ENVIRON["K"]) + 2); sub(/^ +/, "", v); print v; exit }
  ' "$1" 2>/dev/null
}

# fm_set FILE KEY VALUE -> replace KEY in the front matter (adds it if missing).
# Values go through the environment so awk does not interpret backslashes.
fm_set() {
  tmp="$1.tmp.$$"
  K=$2 V=$3 awk '
    { sub(/\r$/, "") }
    NR == 1 { print; infm = ($0 == "---"); next }
    infm && $0 == "---" { if (!done) print ENVIRON["K"] ": " ENVIRON["V"]; infm = 0; print; next }
    infm && index($0, ENVIRON["K"] ":") == 1 { print ENVIRON["K"] ": " ENVIRON["V"]; done = 1; next }
    { print }
  ' "$1" > "$tmp" && mv "$tmp" "$1"
}
