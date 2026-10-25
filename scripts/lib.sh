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
# marker (set by library.sh offload). Returns 1 when its disk is unplugged (offline: a missing or empty mount
# point under /Volumes, /mnt or /media), 2 when it is missing anywhere else, or exists without the
# .library-id file offload writes (an empty mount point, or a wrong path),
# 3 when the line is not one absolute path.
cos_lib() {
  _l=$(sed -n 's/^library: *//p' "$1/.chief-of-staff" 2>/dev/null | head -n 1)
  [ -n "$_l" ] || { printf '%s\n' "$1/knowledge"; return 0; }
  printf '%s\n' "$_l"
  case $_l in /*) ;; *) return 3 ;; esac
  case $_l in */../*|*/..|*/./*) return 3 ;; esac
    # offline only when the disk that holds it is unplugged; a library missing anywhere else was moved or
  # deleted (an agent cannot make it "offline" to skip the gates): broken
  if [ ! -d "$_l" ]; then
    # a mount point: /Volumes/<disk> (macOS), /media/<user>/<disk> or /mnt/<disk> (Linux); any other path is broken
    case $_l in
      /Volumes/?*/*|/mnt/?*/*) _m=$(printf '%s' "$_l" | cut -d/ -f1-3) ;;
      /media/?*/?*/*) _m=$(printf '%s' "$_l" | cut -d/ -f1-4) ;;
      *) return 2 ;;
    esac
    [ -d "$_m" ] && [ -n "$(ls -A "$_m" 2>/dev/null)" ] && return 2   # a mounted disk without the library: moved or deleted
    return 1
  fi
  [ -f "$_l/.library-id" ] && [ -d "$_l/notes" ] || return 2
}

# Several libraries: "personal" (cos_lib) and one per team, marker line "team: <slug> /absolute/path".
# cos_libs ROOT -> "name<TAB>path" for every library, personal first.
cos_libs() {
  printf 'personal\t%s\n' "$(cos_lib "$1")"
  awk '$1 == "team:" && $2 ~ /^[a-z0-9][a-z0-9-]*$/ { n = $2; sub(/^team: +[^ ]+ +/, ""); print n "\t" $0 }' "$1/.chief-of-staff" 2>/dev/null
}
# cos_libname ROOT DIR -> the library a session in DIR uses: the team slug in projects/<p>/.library, else personal
cos_libname() {
  _r=${2#"$1"}; _r=${_r#/}; _n=
  case $_r in projects/?*) _p=${_r#projects/}; _p=${_p%%/*}; _n=$(head -n 1 "$1/projects/$_p/.library" 2>/dev/null | tr -cd 'a-z0-9-') ;; esac
  printf '%s\n' "${_n:-personal}"
}
# cos_libpath ROOT NAME -> the folder of library NAME; returns as cos_lib, and 4 when no library has that name
cos_libpath() {
  [ "$2" = personal ] && { cos_lib "$1"; return; }
  _l=$(cos_libs "$1" | awk -F '\t' -v n="$2" '$1 == n { print $2; exit }')
  [ -n "$_l" ] || { printf '%s\n' "$1/libraries/$2"; return 4; }
  printf '%s\n' "$_l"
  case $_l in /*) ;; *) return 3 ;; esac
  [ -f "$_l/.library-id" ] && [ -d "$_l/notes" ] || return 2
}
# cos_cfg ROOT -> one checksum of every library setting (the marker and each project's .library); library.sh
# records it after join, use, leave and offload, so a change made any other way shows at the turn end
# (pace: counts too: the owner sets it and then records it, cos_cfgsave, like the library settings)
cos_cfg() { { cat "$1/.chief-of-staff"; for _f in "$1"/projects/*/.library; do [ -f "$_f" ] && { printf '%s\n' "$_f"; cat "$_f"; }; done; } 2>/dev/null | cksum | tr -d ' \t'; }
cos_cfgrec() { printf '%s/cos-cfg-%s' "${CLAUDE_PLUGIN_DATA:-$HOME/.cache/chief-of-staff}" "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
cos_cfgsave() { _c=$(cos_cfgrec "$1"); mkdir -p "$(dirname "$_c")" && { [ -f "$_c" ] && chmod u+w "$_c"; cos_cfg "$1" > "$_c"; chmod 444 "$_c"; }; }
# cos_libof ROOT FILE -> "name<TAB>path" of the library whose notes/ holds FILE (empty when none)
cos_libof() {
  cos_libs "$1" | while IFS="$(printf '\t')" read -r _n _p; do
    case $2 in "$_p/notes/"*) printf '%s\t%s\n' "$_n" "$_p"; break ;; esac
  done
}
# cos_epoch "YYYY-MM-DD HH:MM" (or a T between, or a date alone = the end of that day) -> seconds since 1970;
# empty for anything else. Local time, unless an offset follows ("2026-10-25 18:00 -0300", or -03:00): teammates
# in other time zones read the same instant only with the offset written
cos_epoch() {
  _v=$(printf '%s' "$1" | tr T ' ' | sed 's/ *\([+-][0-2][0-9]\):\{0,1\}\([0-5][0-9]\)$/ \1\2/'); _z=
  case $_v in
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) _v="$_v 23:59" ;;
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]' '[0-2][0-9]:[0-5][0-9]) ;;
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]' '[0-2][0-9]:[0-5][0-9]' '[+-][0-2][0-9][0-5][0-9]) _z=${_v##* }; _v=${_v% *} ;;
    *) return 0 ;;
  esac
  if [ -n "$_z" ]; then date -j -f '%Y-%m-%d %H:%M:%S %z' "$_v:00 $_z" +%s 2>/dev/null || date -d "$_v $_z" +%s 2>/dev/null
  else date -j -f '%Y-%m-%d %H:%M:%S' "$_v:00" +%s 2>/dev/null || date -d "$_v" +%s 2>/dev/null; fi
}
# cos_ago MINUTES -> "12 min", "3 h 5 min", "2 d"
cos_ago() { if [ "$1" -lt 60 ]; then echo "$1 min"; elif [ "$1" -lt 1440 ]; then echo "$(($1 / 60)) h $(($1 % 60)) min"; else echo "$(($1 / 1440)) d"; fi; }
# cos_questions CARD -> the question lines under "## For the owner to decide", without the template's placeholder
cos_questions() {
  awk '{ sub(/\r$/, "") } /^## / { on = ($0 ~ /^## For the owner to decide/); next }
    on { sub(/^[-*] +/, ""); if ($0 != "" && $0 !~ /^\(/) print }' "$1" 2>/dev/null | tr -d '\000-\010\013-\037' | cut -c1-300 | head -n 10
}
# cos_shared ROOT -> true when the workspace is shared by a team (setup.sh create --share, or join)
cos_shared() { grep -qx 'shared: yes' "$1/.chief-of-staff" 2>/dev/null; }
# cos_fast ROOT -> true in hackathon pace (pace: fast in the marker, which only the owner can write):
# internal work needs one specialist or the reviewer; the reviewer is for what goes outside
cos_fast() { grep -qx 'pace: fast' "$1/.chief-of-staff" 2>/dev/null; }
# cos_member ROOT -> this person's name in a shared workspace (git config cos.member, local to this computer)
cos_member() { git -C "$1" config cos.member 2>/dev/null | tr -d '\000-\037' | cut -c1-60; }
