# Shared helpers. Sourced by the other scripts; POSIX sh, no GNU- or macOS-only flags.

# Print the workspace root (the nearest folder holding a .chief-of-staff marker) or fail.
cos_root() {
  d=${1:-$PWD}
  case $d in /*) ;; *) return 1 ;; esac   # a relative path never reaches "/"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.chief-of-staff" ] && { printf '%s\n' "$d"; return 0; }
    d=${d%/*}   # no dirname: this runs in every hook call, and a fork per level is slow on WSL drives
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
# cos_cache NAME KEY -> a file for this computer's cache (never in a library or the workspace), one per KEY
cos_cache() { printf '%s/%s-%s' "${CLAUDE_PLUGIN_DATA:-$HOME/.cache/chief-of-staff}" "$1" "$(printf '%s' "$2" | cksum | cut -d' ' -f1)"; }
# cos_ids LIB -> the note ids of LIB, one per line, from a cache that stays valid until notes/ changes (adding,
# removing or renaming a note changes the folder's mtime; ids are file names, so an edit inside a note cannot
# change them). Saves a stat per note per hook on slow disks (WSL drives, cloud folders)
cos_ids() {
  [ -d "$1/notes" ] || return 0
  _k=$(cos_cache ids "$1")
  [ "$_k" -nt "$1/notes" ] || { mkdir -p "${_k%/*}"; ls "$1/notes" 2>/dev/null | sed -n 's/\.md$//p' > "$_k.$$" && mv -f "$_k.$$" "$_k"; }
  cat "$_k" 2>/dev/null
}
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
# A question line under "## For the owner to decide" carries the time it was asked: "- (asked 2026-10-25 18:00 -0300) ...".
# The Stop hook stamps each new top-level line, so the oldest open question keeps its age when asked: is rewritten
# or a later question is added (asked: alone, the old format, still counts)
COS_ASKED='/^\(asked [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]( [+-][0-2][0-9][0-5][0-9])?\) */'
# cos_questions CARD -> the question lines under "## For the owner to decide", without the template's placeholder
# and without their (asked ...) stamp
cos_questions() {
  awk '{ sub(/\r$/, "") } /^## / { on = ($0 ~ /^## For the owner to decide/); next }
    on { sub(/^[-*] +/, ""); if (match($0, '"$COS_ASKED"')) $0 = substr($0, RLENGTH + 1); if ($0 != "" && $0 !~ /^\(/) print }' "$1" 2>/dev/null | tr -d '\000-\010\013-\037' | cut -c1-300 | head -n 10
}
# cos_board ROOT -> one line per board card in one pass (hooks run it every turn), fields split by \037:
#   file member project status asked due questions unstamped stamps lines bytes long text qstamps
# questions: open question lines; unstamped: top-level ones without (asked ...); stamps: their times, split by \036;
# lines, bytes, long: the card's size and its lines over 300 characters; text: the questions as cos_questions prints them;
# qstamps: the (asked ...) time of each question in text, in the same order, empty when unstamped, split by \036
cos_board() {
  for _c in "$1"/board/*.md; do [ -f "$_c" ] || continue
    LC_ALL=C awk '
      function cl(s) { gsub(/[\001-\037\177]/, "", s); return s }
      function out() { if (fn != "") printf "%s\037%s\037%s\037%s\037%s\037%s\037%d\037%d\037%s\037%d\037%d\037%d\037%s\037%s\n", fn, V["member"], V["project"], V["status"], V["asked"], V["due"], nq, nu, sp, nl, nb, lg, qt, qs }
      FNR == 1 { out(); fn = FILENAME; split("", V); fm = 0; on = 0; nq = nu = nl = nb = lg = 0; sp = qt = qs = "" }
      { nb += length($0) + 1; nl++; if (length($0) > 300) lg++; sub(/\r$/, "") }
      FNR == 1 && $0 == "---" { fm = 1; next }
      fm { if ($0 == "---") fm = 0
           else if (match($0, /^[a-z_]+:/)) { k = substr($0, 1, RLENGTH - 1); if (!(k in V)) { v = substr($0, RLENGTH + 1); sub(/^ +/, "", v); V[k] = substr(cl(v), 1, 200) } }
           next }
      /^## / { on = ($0 ~ /^## For the owner to decide/); next }
      on { l = $0; top = (l ~ /^[-*] +/); sub(/^[-*] +/, "", l); t = ""
           if (match(l, '"$COS_ASKED"')) { t = substr(l, 8, RLENGTH - 7); sub(/\) *$/, "", t); l = substr(l, RLENGTH + 1) }
           if (l == "" || l ~ /^\(/) next
           nq++; if (top && t == "") nu++; if (t != "") sp = sp (sp == "" ? "" : "\036") t
           if (nq <= 10) { qt = qt (qt == "" ? "" : "\036") substr(cl(l), 1, 300); qs = qs (nq == 1 ? "" : "\036") t } }
      END { out() }' "$1"/board/*.md 2>/dev/null
    return 0; done
}
# cos_stamp CARD WHEN -> stamp every unstamped top-level question line of CARD with (asked WHEN)
cos_stamp() {
  W=$2 awk '{ r = $0; sub(/\r$/, "") }
    /^## / { on = ($0 ~ /^## For the owner to decide/); print r; next }
    on && match($0, /^[-*] +/) { p = substr($0, 1, RLENGTH); l = substr($0, RLENGTH + 1)
      if (l != "" && l !~ /^\(/) { print p "(asked " ENVIRON["W"] ") " l; next } }
    { print r }' "$1" > "$1.tmp.$$" && mv "$1.tmp.$$" "$1"
}
# cos_decisions FILE -> the decisions in force in a project's DECISIONS.md, "when<TAB>decision<TAB>who", oldest first.
# Line format: "- YYYY-MM-DD HH:MM | decision | who | replaces: <when of an earlier line, or ->"; a later line
# replaces an earlier one, and "revoked: <why>" as the decision withdraws it. Lines are never edited
cos_decisions() {
  LC_ALL=C awk -F ' [|] ' '{ sub(/\r$/, "") } /^- [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9] [|] / {
      id = substr($1, 3); r = $4; sub(/^ *replaces: */, "", r); sub(/ *$/, "", r); if (r != "" && r != "-") R[r] = 1
      n++; I[n] = id; D[n] = $2; Wh[n] = $3 }
    END { for (i = 1; i <= n; i++) if (!(I[i] in R) && D[i] !~ /^revoked:/) { d = D[i]; w = Wh[i]; gsub(/[\001-\037]/, "", d); gsub(/[\001-\037]/, "", w); print I[i] "\t" d "\t" w } }' "$1" 2>/dev/null
}
# cos_shared ROOT -> true when the workspace is shared by a team (setup.sh create --share, or join)
cos_shared() { grep -qx 'shared: yes' "$1/.chief-of-staff" 2>/dev/null; }
# cos_fast ROOT -> true in hackathon pace (pace: fast in the marker, which only the owner can write):
# internal work needs one specialist or the reviewer; the reviewer is for what goes outside
cos_fast() { grep -qx 'pace: fast' "$1/.chief-of-staff" 2>/dev/null; }
# cos_member ROOT -> this person's name in a shared workspace (git config cos.member, local to this computer)
cos_member() { git -C "$1" config cos.member 2>/dev/null | tr -d '\000-\037' | cut -c1-60; }
