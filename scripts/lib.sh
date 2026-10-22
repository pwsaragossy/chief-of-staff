# Shared helpers. Sourced by the other scripts; POSIX sh, no GNU- or macOS-only flags.

# Print the workspace root (the nearest folder holding a .chief-of-staff marker) or fail.
cos_root() {
  d=${1:-$PWD}
  case $d in /*) ;; *) return 1 ;; esac   # a relative path never reaches "/": dirname would loop on "."
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

# cos_lib ROOT -> prints the library folder: ROOT/knowledge, or the "library: /absolute/path" line of the
# marker (set by library.sh offload). Returns 1 when that folder is not reachable (offline: disk unplugged),
# 2 when it exists without the .library-id file offload writes (an empty mount point, or a wrong path),
# 3 when the line is not one absolute path.
cos_lib() {
  _l=$(sed -n 's/^library: *//p' "$1/.chief-of-staff" 2>/dev/null | head -n 1)
  [ -n "$_l" ] || { printf '%s\n' "$1/knowledge"; return 0; }
  printf '%s\n' "$_l"
  case $_l in /*) ;; *) return 3 ;; esac
  case $_l in */../*|*/..|*/./*) return 3 ;; esac
  [ -d "$_l" ] || return 1
  [ -f "$_l/.library-id" ] && [ -d "$_l/notes" ] || return 2
}
