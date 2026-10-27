#!/usr/bin/env python3
"""Local panel for a chief-of-staff workspace: health per project, track progress, cards waiting on
the owner, the last 24 hours in three counts (turns, protocol breaks, rejected notes), and an import box that drops files or links into
knowledge/inbox/. Standard library only. Listens on 127.0.0.1; every request needs the token in the URL.

Usage: python3 panel.py <workspace> [port]     (port 0 or omitted = a free port)
"""
import hashlib, http.server, io, json, os, re, secrets, shutil, subprocess, sys, tarfile, threading, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_UPLOAD = 50 * 1024 * 1024
# the same patterns library.awk blocks in notes
SECRET = re.compile(rb"AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40}|sk-[A-Za-z0-9_-]{32}|xox[baprs]-[A-Za-z0-9-]{10}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{10}[.]eyJ[A-Za-z0-9_-]{10}[.]")
US = "\x1f"


def find_root(path):
    d = os.path.abspath(path)
    while d != os.path.dirname(d):
        if os.path.isfile(os.path.join(d, ".chief-of-staff")):
            return d
        d = os.path.dirname(d)
    return None


def front_matter(path):
    out = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return out
    if not lines or lines[0].strip() != "---":
        return out
    for line in lines[1:]:
        if line.strip() == "---":
            break
        k, sep, v = line.partition(":")
        if sep:
            out[k.strip()] = v.strip()
    return out


def sh(script, *args, cwd=None, strict=False):
    """stdout of a plugin script; "" on timeout, or TimeoutError with strict (an empty answer would look healthy)."""
    try:
        r = subprocess.run(["sh", os.path.join(HERE, script), *args], capture_output=True, text=True, timeout=20,
                           cwd=cwd, env=dict(os.environ, CLAUDE_PROJECT_DIR=cwd or os.getcwd()))
    except subprocess.TimeoutExpired:
        if strict:
            raise TimeoutError(script)
        return ""
    return r.stdout


MAX_NODES = 500  # the canvas graph stays fluid up to here; the lists below stay complete



def rows(text):
    """Lines of a script's output. Not str.splitlines(): that also splits on \x1c-\x1e, which rows use inside fields."""
    return [l for l in text.split("\n") if l]

# a progress line on a card: "- [2026-10-25] [11:30 UTC] (who): what happened", with a date or a time or both
PROGRESS = re.compile(r"^\s*[-*] \**((\d{4}-\d{2}-\d{2})?\s*(\d{1,2}:\d{2})?)(?: ?[A-Z]{2,4})?(?: check)?\**\s*\(([^)]{1,80})\):\s*(.+)$")


def progress(root, slug, keep=3):
    """The latest progress line of each open card of a project, newest card first, so the panel moves
    before a whole track item closes. ponytail: a line without a date counts as the card's updated: day."""
    out = []
    board = os.path.join(root, "board")
    try:
        names = [n for n in os.listdir(board) if n.endswith(".md")]
    except OSError:
        return out
    for n in names:
        path = os.path.join(board, n)
        fm = front_matter(path)
        if fm.get("project") != slug or fm.get("status", "") in ("done", "closed", "cancelled", "dropped"):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        best = None
        for line in text.split("\n"):
            m = PROGRESS.match(line)
            if not m or not (m.group(2) or m.group(3)):
                continue
            day, hm = m.group(2) or fm.get("updated", ""), m.group(3) or ""
            key = (day, hm.zfill(5))
            if best is None or key > best[0]:
                best = (key, hm, m.group(4), m.group(5))
        if best:
            what = re.sub(r"[`*]", "", best[3]).strip()
            out.append({"card": n[:-3], "when": " ".join(x for x in (best[0][0], best[1]) if x), "who": best[2],
                        "what": what[:180] + ("…" if len(what) > 180 else ""), "key": best[0]})
    out.sort(key=lambda x: x["key"], reverse=True)
    for x in out:
        del x["key"]
    return out[:keep]


def tasks(root):
    """Every open card's "## Tasks" lines ("Leo: deploy by 13:00"), grouped by who does them. Unlike
    "For the owner to decide" they carry no wait timer and no colour: they are work, not questions."""
    who = {}
    board = os.path.join(root, "board")
    try:
        names = sorted(n for n in os.listdir(board) if n.endswith(".md"))
    except OSError:
        return []
    for n in names:
        path = os.path.join(board, n)
        fm = front_matter(path)
        if fm.get("status", "") in ("done", "closed", "cancelled", "dropped"):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
        except OSError:
            continue
        on = False
        for line in lines:
            if line.startswith("## "):
                on = line.strip().lower() == "## tasks"
                continue
            t = re.sub(r"^\s*[-*] +", "", line).strip() if on else ""
            if not t or t.startswith("("):
                continue
            t = re.sub(r"[\x00-\x1f`*]", "", t)
            name, sep, rest = t.partition(":")
            if not sep or len(name) > 40:
                name, rest = "Unassigned", t
            name = name.split(",")[0].strip() or "Unassigned"
            who.setdefault(name, []).append({"task": rest.strip()[:300], "card": n[:-3], "project": fm.get("project", "")})
    return [{"who": k, "items": v} for k, v in sorted(who.items(), key=lambda kv: (kv[0] == "Unassigned", kv[0].lower()))]


def libraries(root):
    """Every library (personal and each team's): name, folder, state, notes, last sync."""
    out = []
    for line in rows(sh("library.sh", "libs", cwd=os.path.join(root, "central"))):
        f = line.split("\t")
        if len(f) >= 5:
            out.append({"name": f[0], "path": f[1], "state": f[2], "notes": f[3], "sync": f[4],
                        "sync_color": "green" if f[0] == "personal" else sync_color(f[4])})
    return out


def library(root, name="personal"):
    """The library view, computed on demand from library.sh (graph + where): never a stored index."""
    where = rows(sh("library.sh", "--lib", name, "where", cwd=root))
    path = where[0] if where else os.path.join(root, "knowledge")
    if len(where) > 1:
        return {"state": "offline" if "offline" in where[1] else "error", "path": path, "message": where[1],
                "color": "yellow", "nodes": [], "edges": [], "problems": [], "dangling": [], "stale": [], "pairs": []}
    nodes, edges, dangling, pairs, retired, issues = [], [], [], [], 0, {}
    try:
        graph = sh("library.sh", "--lib", name, "graph", cwd=root, strict=True)
    except TimeoutError:
        return {"state": "error", "path": path, "message": "Checking the library took over 20 s; run library.sh doctor.",
                "color": "yellow", "nodes": [], "edges": [], "problems": [], "dangling": [], "stale": [], "pairs": []}
    for line in rows(graph):
        f = line.split("\t")
        if f[0] == "N" and len(f) >= 9:
            f += [""] * (12 - len(f))  # confidence, updated, review_by: absent from an older library.awk
            nodes.append({"id": f[1], "title": f[2], "type": f[3], "state": f[4], "origin": f[5], "group": f[6],
                          "problems": int(f[7] or 0), "in": int(f[8] or 0),
                          "confidence": f[9], "updated": f[10], "review_by": f[11]})
        elif f[0] == "M" and len(f) >= 3:
            issues.setdefault(f[1], []).append(f[2])
        elif f[0] == "E" and len(f) >= 3:
            edges.append([f[1], f[2]])
        elif f[0] == "D" and len(f) >= 3:
            dangling.append([f[1], f[2]])
        elif f[0] == "R" and len(f) >= 3:
            edges.append([f[1], f[2]]); retired += 1
        elif f[0] == "P" and len(f) >= 3:
            pairs.append([f[1], f[2]])
    problems = [n["id"] for n in nodes if n["problems"]]
    stale = [n["id"] for n in nodes if n["state"] == "stale"]
    shown = sorted(nodes, key=lambda n: (n["state"] == "retired", -n["in"]))[:MAX_NODES]
    keep = {n["id"] for n in shown}
    for n in shown:
        n["issues"] = issues.get(n["id"], [])
    color = "yellow" if problems or dangling or pairs else "green"
    return {"state": "online", "path": path, "color": color, "total": len(nodes), "retired": retired,
            "nodes": shown, "edges": [e for e in edges if e[0] in keep and e[1] in keep],
            "problems": problems, "dangling": dangling, "stale": stale, "pairs": pairs,
            "origins": sorted({n["origin"] for n in nodes if n["origin"]})}


def shared(root):
    """In a shared workspace: this person's name and the last sync of the workspace with the team."""
    try:
        with open(os.path.join(root, ".chief-of-staff"), encoding="utf-8") as f:
            if "shared: yes" not in f.read().splitlines():
                return None
    except OSError:
        return None
    try:
        with open(os.path.join(root, ".git", "cos-sync"), encoding="utf-8", errors="replace") as f:
            sync = f.readline().strip()[:160]
    except OSError:
        sync = ""
    me = subprocess.run(["git", "-C", root, "config", "cos.member"], capture_output=True, text=True).stdout.strip()[:60]
    return {"member": me, "sync": sync or "never", "color": sync_color(sync or "never"), **data_age(sync[:19])}


LATE_MINUTES = 15  # teammates' data older than this gets an "as of sync HH:MM" label


def data_age(stamp):
    """Age of the team's data from a sync line's "YYYY-MM-DD HH:MM:SS": as_of HH:MM, minutes, late."""
    try:
        t = time.mktime(time.strptime(stamp, "%Y-%m-%d %H:%M:%S"))
    except ValueError:
        return {"as_of": "", "age": None, "late": True}
    age = max(0, int((time.time() - t) // 60))
    return {"as_of": stamp[11:16], "age": age, "late": age > LATE_MINUTES}


def decisions(pdir, keep=5):
    """The decisions in force in the project's DECISIONS.md (lib.sh cos_decisions), newest first."""
    path = os.path.join(pdir, "DECISIONS.md")
    if not os.path.isfile(path):
        return []
    try:
        out = subprocess.run(["sh", "-c", '. "$0/lib.sh"; cos_decisions "$1"', HERE, path],
                             capture_output=True, text=True, timeout=10).stdout
    except subprocess.TimeoutExpired:
        return []
    got = [dict(zip(("when", "what", "who"), (l.split("\t") + ["", ""])[:3])) for l in rows(out)]
    return [{k: v[:200] for k, v in d.items()} for d in got[-keep:][::-1]]


def outside(field):
    """health.sh's public_urls and prod_ref results: "public <url> <code> ok|closed", "prod <url> <commit> ok|down|other"."""
    out = []
    for e in field.split("\x1e"):
        k = e.split(" ")
        if len(k) == 4 and k[0] in ("public", "prod"):
            out.append({"kind": k[0], "url": k[1], "code" if k[0] == "public" else "commit": k[2], "state": k[3]})
    return out


VIEW = {"at": 0, "commit": "", "dir": "", "error": ""}
VIEW_LOCK = threading.Lock()


def team_view(root, fetch=False):
    """In a shared workspace, the projects, cards and tasks as GitHub has them, so every member sees the
    same state: fetch the upstream when the owner presses Fetch (and once at start), export that commit
    to a cache folder and read from there. The working folder and its branch are never touched. Without an upstream: the local folder."""
    if not shared(root):
        return root, None
    git = ["git", "-C", root]
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    with VIEW_LOCK:
        if fetch or not VIEW["dir"]:
            VIEW["at"] = time.time()
            try:
                up = subprocess.run(git + ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
                                    capture_output=True, text=True, timeout=10).stdout.strip()
                if not up:
                    return root, None
                f = subprocess.run(git + ["fetch", "--quiet", up.split("/")[0]], capture_output=True, text=True, timeout=20, env=env)
                VIEW["error"] = "" if f.returncode == 0 else "GitHub fetch failed, showing the last state fetched"
                commit = subprocess.run(git + ["rev-parse", up], capture_output=True, text=True, timeout=10).stdout.strip()
                if commit and commit != VIEW["commit"]:
                    base = os.path.join(os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.expanduser("~/.cache/chief-of-staff"),
                                        "team-view-" + hashlib.sha1(root.encode()).hexdigest()[:10])
                    new = os.path.join(base, commit)
                    if not os.path.isdir(new):
                        tar = subprocess.run(git + ["archive", "--format=tar", commit], capture_output=True, timeout=30).stdout
                        tmp = new + ".tmp"
                        shutil.rmtree(tmp, ignore_errors=True)
                        # links are dropped: the export is the team's content and is never followed out
                        with tarfile.open(fileobj=io.BytesIO(tar)) as t:
                            t.extractall(tmp, filter=lambda m, path: None if (m.issym() or m.islnk()) else tarfile.data_filter(m, path))
                        os.replace(tmp, new)
                    for old in os.listdir(base):  # keep only the commit shown
                        if old != commit:
                            shutil.rmtree(os.path.join(base, old), ignore_errors=True)
                    VIEW.update(commit=commit, dir=new)
                VIEW["stamp"] = time.strftime("%Y-%m-%d %H:%M:%S")
            except (subprocess.TimeoutExpired, OSError, tarfile.TarError, TypeError) as e:
                VIEW["error"] = "GitHub view failed (%s), showing the last state fetched" % type(e).__name__
            VIEW["fetched"] = time.strftime("%H:%M:%S")
        if not VIEW["dir"] or not os.path.isfile(os.path.join(VIEW["dir"], ".chief-of-staff")):
            return root, {"error": VIEW["error"] or "No GitHub state yet, showing this computer's copy"}
        # the owner's OKs never leave this computer (the sync skips them), so the export has none: bring this
        # computer's copies, read fresh each time, or every track with owner items reads as tampered
        for slug in os.listdir(os.path.join(root, "projects")) if os.path.isdir(os.path.join(root, "projects")) else []:
            dst = os.path.join(VIEW["dir"], "projects", slug)
            # the export is the team's content: never follow a link a teammate committed in it
            if os.path.islink(dst) or not os.path.isdir(dst) or \
                    not os.path.realpath(dst).startswith(os.path.realpath(VIEW["dir"]) + os.sep):
                continue
            for name in (".owner-ok", ".owner-items", ".check-runs"):
                src, target = os.path.join(root, "projects", slug, name), os.path.join(dst, name)
                try:
                    if os.path.lexists(target):
                        os.unlink(target)
                    if os.path.isfile(src):
                        with open(src, "rb") as f:
                            data = f.read()
                        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
                        with os.fdopen(fd, "wb") as f:
                            f.write(data)
                except OSError:
                    pass
        return VIEW["dir"], {"commit": VIEW["commit"][:7], "fetched": VIEW.get("fetched", ""), "error": VIEW["error"],
                             **data_age(VIEW.get("stamp", ""))}


def sync_color(text):
    return "red" if ("conflict" in text or "failed" in text) else "yellow" if ("never" in text or "busy" in text) else "green"


def snapshot(root, libname="personal", fetch=False):
    view, source = team_view(root, fetch)   # projects, cards and tasks as the team sees them; library and log stay local
    projects = []
    for line in rows(sh("health.sh", view)):
        f = (line.split(US) + [""] * 18)[:18]
        slug, color, reason, stage, stages, closed, total, delivery, delivered, baseline, baseline_delivery, deadline, member, target, check, runs, why, out = f
        # every reason, red first, each "red <text>" or "yellow <text>"; an older health.sh gives only the first
        reasons = [{"color": r.split(" ", 1)[0], "text": r.split(" ", 1)[1]} for r in why.split("\x1e") if r.split(" ", 1)[0] in ("red", "yellow") and " " in r]
        pdir = os.path.join(view, "projects", slug)
        stage_names, items = [], []
        for row in rows(sh("track.sh", "items", pdir)):
            r = row.split(US)
            if r[0] == "S" and len(r) >= 3:
                stage_names.append({"n": r[1], "name": r[2]})
            elif r[0] == "I" and len(r) >= 7:
                items.append({"stage": r[1], "state": r[2], "id": r[3], "card": r[4],
                              "needs": [n.strip() for n in r[5].split(",") if n.strip() not in ("", "-")], "what": r[6]})
        projects.append({
            "slug": slug, "color": color, "reason": reason,
            "stage": stage, "stages": stages, "closed": closed, "total": total,
            "delivery": delivery, "delivered": delivered == "1", "baseline": baseline, "baseline_delivery": baseline_delivery,
            "deadline": int(deadline) if deadline.isdigit() else None, "member": member,
            "target": target, "check": check, "runs": runs,
            "stage_names": stage_names, "items": items,
            "brief": " ".join(l for l in rows(sh("track.sh", "brief", pdir)) if not l.startswith("Target: ")).strip().split(" Waiting on prerequisites:")[0],
            "next": front_matter(os.path.join(pdir, "STATE.md")).get("next", ""),
            "progress": progress(view, slug),
            "reasons": reasons or ([{"color": color, "text": reason}] if color != "green" else []),
            "outside": outside(out), "decisions": decisions(pdir),
        })
    libs = libraries(root)
    if libname not in [x["name"] for x in libs]:
        libname = "personal"
    lib = library(root, libname)
    lib["name"] = libname
    rank = {"red": 2, "yellow": 1, "green": 0}
    overall = max([p["color"] for p in projects] + [lib["color"]], key=lambda c: rank.get(c, 0))

    todo = tasks(view)
    cards = []  # what waits on the owner, from health.sh (the one place that times and colors it)
    for line in rows(sh("health.sh", "cards", view)):
        f = (line.split(US) + [""] * 14)[:14]
        if f[0] == "C" and f[3] == "waiting-owner":
            qs, ages = f[10].split("\x1e"), f[13].split("\x1e")  # ages: minutes per question, empty when unstamped
            cards.append({"title": f[1], "project": f[2], "member": f[4], "color": f[5], "waited": int(f[6] or 0),
                          "limit": f[7], "questions": [q for q in qs if q], "deputy": f[11], "size": f[12],
                          "ages": [int(a) if i < len(ages) and (a := ages[i]).isdigit() else None for i, q in enumerate(qs) if q]})

    # the last 24 h of the protocol log, as three counts: turns, turns that broke the protocol, notes rejected
    try:
        with open(os.path.join(root, ".protocol.log"), encoding="utf-8", errors="replace") as f:
            lines = f.readlines()[-2000:]
    except OSError:
        lines = []
    last, since = {}, time.time() - 86400
    for line in lines:  # keep the last line of each turn (after any push)
        kv = dict(p.split("=", 1) for p in line.split() if "=" in p)
        if "turn" in kv and kv.get("t", "0").isdigit() and int(kv["t"]) >= since:
            last[kv["turn"]] = kv
    counts = {"turns": len(last), "violations": sum(k.get("violation") == "1" for k in last.values()),
              "rejected": sum(int(k.get("rejected", "0") or 0) for k in last.values() if k.get("rejected", "0").isdigit())}

    inbox = os.path.join(lib["path"], "inbox")
    n_inbox = len([n for n in os.listdir(inbox) if not n.startswith(".")]) if os.path.isdir(inbox) else 0
    n_notes = lib.get("total", 0)
    sh_ws = shared(root)
    rank_c = [c["color"] for c in cards] + [x["sync_color"] for x in libs] + ([sh_ws["color"]] if sh_ws else [])
    overall = max([overall] + rank_c, key=lambda c: rank.get(c, 0))
    return {"library": lib, "libs": libs, "workspace": root, "overall": overall, "projects": projects, "cards": cards, "tasks": todo, "source": source,
            "counts": counts, "shared": sh_ws,
            "inbox": n_inbox, "notes": n_notes, "time": time.strftime("%H:%M:%S")}


def safe_name(name):
    base = os.path.basename(name or "").strip() or "item"
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base).lstrip(".") or "item"
    return time.strftime("%Y%m%d-%H%M%S-") + base[:120]


PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Chief of staff</title>
<style>
:root{--bg:#f6f6f4;--fg:#1d1d1f;--muted:#6e6e73;--card:#fff;--line:#e3e3e0;
--green:#2e9b55;--yellow:#c98a00;--red:#d6453d;--edge:#b9b9b4;
--t-finding:#0072b2;--t-decision:#c4501a;--t-howto:#00806a;--t-option:#b0508a;--t-topic:#6b7280}
@media (prefers-color-scheme:dark){:root{--bg:#161617;--fg:#f2f2f2;--muted:#a1a1a6;--card:#1f1f21;--line:#333;--edge:#56565c;
--t-finding:#56b4e9;--t-decision:#f08a4b;--t-howto:#2fc29a;--t-option:#e59ac8;--t-topic:#a3a8b0}}
*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,system-ui,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:22px;margin:0}h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:28px 0 10px}
.top{display:flex;align-items:center;gap:12px}.muted{color:var(--muted);font-size:13px}
.dot{width:12px;height:12px;border-radius:50%;flex:none;display:inline-block}
.green{background:var(--green)}.yellow{background:var(--yellow)}.red{background:var(--red)}
.box{background:var(--card);border:1px solid var(--line);border-radius:12px}
.row{display:flex;gap:12px;padding:14px 16px;border-top:1px solid var(--line);align-items:flex-start}.row:first-child{border-top:0}
.row .dot{margin-top:5px}.grow{flex:1;min-width:0}.name{font-weight:600}
.bar{height:6px;background:var(--line);border-radius:3px;margin:8px 0 6px;overflow:hidden}.bar i{display:block;height:100%;background:var(--green)}
table{width:100%;border-collapse:collapse;font-size:13px}td,th{text-align:left;padding:8px 12px;border-top:1px solid var(--line)}th{color:var(--muted);font-weight:500;border:0}
#drop{padding:22px;text-align:center;border:2px dashed var(--line);border-radius:12px;cursor:pointer}
#drop.over{border-color:var(--green)}
form{display:flex;gap:8px;margin-top:10px}input[type=text]{flex:1;padding:9px 12px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--fg);font:inherit}
button{padding:9px 16px;border:0;border-radius:8px;background:var(--fg);color:var(--bg);font:inherit;cursor:pointer}
#msg{min-height:20px;margin-top:8px;font-size:13px}
.empty{padding:16px;color:var(--muted)}
.why{margin:2px 0 0;padding:0;list-style:none}.why li{display:flex;gap:6px;align-items:baseline}.why .dot{width:8px;height:8px;flex:none}
.why details summary{cursor:pointer;color:var(--muted);font-size:13px}
.pill{display:inline-flex;align-items:baseline;gap:6px;max-width:100%;border:1px solid var(--yellow);border-radius:12px;padding:1px 9px;font-size:12px;color:var(--fg);margin:4px 6px 0 0}
.pill.red{background:none;border-color:var(--red)}.pill .dot{width:8px;height:8px}
.facts{font-size:13px;margin-top:6px}.facts b{font-weight:600}.facts ul{margin:2px 0 0;padding-left:18px;color:var(--muted)}
.age{color:var(--muted);font-size:12px;white-space:nowrap}.pill .dot{flex:none}
@media (max-width:639px){#cards .row{flex-wrap:wrap}#cards .row>span:last-child{flex-basis:100%;padding-left:24px}}
.toggle{background:none;color:var(--fg);border:1px solid var(--line);padding:4px 10px;font-size:12px;margin-top:8px}
.map{overflow-x:auto;margin-top:10px}
.cols{display:flex;gap:28px;position:relative;padding:22px 2px 10px 40px;width:max-content}
.col{display:flex;flex-direction:column;gap:8px;width:160px;flex:none;position:relative;z-index:1}
.col h3{font-size:12px;margin:0 0 2px;color:var(--muted);font-weight:600}
.node{border:1.5px solid var(--line);border-radius:8px;padding:6px 8px;font-size:12px;background:var(--card)}
.node b{display:block;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.node small{color:var(--muted)}
.node.done{border-color:var(--green);box-shadow:inset 3px 0 0 var(--green)}
.node.na,.node.blocked{border-style:dashed;border-color:var(--edge);color:var(--muted)}.node.na b{text-decoration:line-through}
.node.ready{border-color:var(--fg)}
.node .dep{display:block;font-size:11px;color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.node.pre{outline:2px solid var(--fg);outline-offset:1px}.node.post{outline:2px dashed var(--fg);outline-offset:1px}
.node:focus-visible{outline:2px solid var(--fg);outline-offset:2px}
.finish{flex:none;width:0;border-left:2px dashed var(--yellow);position:relative;z-index:1}
.finish span{position:absolute;top:-20px;transform:translateX(-50%);font-size:11px;font-weight:600;color:var(--yellow);white-space:nowrap}
.finish.reached{border-color:var(--green)}.finish.reached span{color:var(--green)}
.legend{font-size:12px;color:var(--muted);margin-top:4px}
svg.edges{position:absolute;left:0;top:0;pointer-events:none;z-index:0;overflow:visible}
svg.edges path{fill:none;stroke:var(--edge);stroke-width:1.5}
svg.edges path.ok{stroke:var(--green);opacity:.6}svg.edges path.hot{stroke:var(--fg);opacity:1;stroke-width:2}
.gtool{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:center;padding:10px 16px;border-top:1px solid var(--line);font-size:12px}
.gtool input[type=search]{flex:1 1 200px;min-width:0;padding:6px 10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--fg);font:inherit}
.gtool select{margin:0}.gtool label{display:inline-flex;gap:5px;align-items:center}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{display:inline-flex;align-items:center;gap:6px;background:none;color:var(--fg);border:1px solid var(--line);border-radius:999px;padding:3px 10px;font-size:12px}
.chip i{width:10px;height:10px;border-radius:50%}.chip i.sq{border-radius:2px}.chip[aria-pressed=false]{color:var(--muted);text-decoration:line-through}.chip[aria-pressed=false] i{opacity:.3}
.gwrap{position:relative;height:min(70vh,640px);border-top:1px solid var(--line);overflow:hidden}
.gwrap canvas{display:block;width:100%;height:100%;touch-action:none;cursor:grab}
.gwrap canvas:focus-visible{outline:2px solid var(--fg);outline-offset:-2px}
.gzoom{position:absolute;left:10px;top:10px;display:flex;flex-direction:column;gap:4px}
.gzoom button{min-width:34px;height:34px;padding:0 8px;background:var(--card);color:var(--fg);border:1px solid var(--line);font-size:14px}
.gtip{position:absolute;pointer-events:none;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 9px;font-size:12px;max-width:280px;box-shadow:0 2px 10px rgba(0,0,0,.15)}
.gdet{position:absolute;top:0;right:0;bottom:0;width:320px;background:var(--card);border-left:1px solid var(--line);padding:14px 16px;overflow:auto;font-size:13px}
.gdet h3{font-size:15px;margin:0 32px 8px 0;overflow-wrap:anywhere}.gdet dl{display:grid;grid-template-columns:auto 1fr;gap:2px 12px;margin:0 0 10px}
.gdet dt{color:var(--muted)}.gdet dd{margin:0;min-width:0;overflow-wrap:anywhere}.gdet ul{margin:4px 0 10px;padding-left:18px}
.gdet .x{position:absolute;top:8px;right:8px;width:32px;height:32px;padding:0;background:none;color:var(--fg);font-size:20px}
.linkb{background:none;color:var(--fg);padding:1px 0;border-radius:0;text-align:left;text-decoration:underline;text-underline-offset:2px;font-size:13px}
.gmsg{position:absolute;inset:0;display:flex;flex-direction:column;gap:10px;align-items:center;justify-content:center;color:var(--muted);pointer-events:none}.gmsg button{pointer-events:auto}
.glegend{padding:8px 16px 0}.glist{padding:8px 16px;font-size:13px}.glist summary{cursor:pointer;color:var(--muted)}
.glist ul{max-height:260px;overflow:auto;margin:6px 0 0;padding-left:18px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
@media (max-width:639px){.gwrap{height:420px}.gdet{top:auto;left:0;width:auto;max-height:65%;border-left:0;border-top:1px solid var(--line);border-radius:12px 12px 0 0;box-shadow:0 -4px 16px rgba(0,0,0,.18)}}
.counts{display:grid;grid-template-columns:repeat(3,1fr)}.counts div{padding:14px 16px;border-left:1px solid var(--line)}.counts div:first-child{border-left:0}
.counts b{display:block;font-size:24px;font-weight:600}.q{margin:4px 0 0;padding-left:18px;font-size:13px}
.lists{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:0;border-top:1px solid var(--line)}
.lists div{padding:12px 16px;font-size:13px}.lists b{display:block;margin-bottom:4px}.lists ul{margin:0;padding-left:16px;color:var(--muted)}
select{font:inherit;font-size:12px;padding:3px 6px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg);margin-left:8px}
</style></head><body><main>
<div class="top"><span id="overall" class="dot"></span><h1>Chief of staff</h1><span class="grow"></span><span id="time" class="muted"></span></div>
<div id="ws" class="muted"></div><button id="fetch" class="toggle" hidden>Fetch</button>
<h2>Projects</h2><div id="projects" class="box"></div>
<h2>Waiting on the owner</h2><div id="cards" class="box"></div>
<h2>Tasks</h2><div id="tasks" class="box"></div>
<h2>Import knowledge</h2>
<div id="drop" class="box">Drop files here or click to choose<input id="file" type="file" multiple hidden></div>
<form id="linkform"><input id="link" type="text" placeholder="Link or text" aria-label="Link or text"><button>Save</button></form>
<div id="msg" class="muted" role="status"></div>
<div id="lib" class="muted"></div>
<h2>Library</h2><div id="library" class="box"></div>
<h2>Last 24 hours</h2><div id="turns" class="box counts"></div>
</main><script>
const T=new URLSearchParams(location.search).get("t");
const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e};
const ago=m=>m<60?m+" min":m<1440?Math.floor(m/60)+" h "+(m%60)+" min":Math.floor(m/1440)+" d";
function empty(box,text){box.replaceChildren(el("div","empty",text))}
let last=null,origin="",libName="personal";
// library graph: canvas for nodes and edges, DOM for tooltip, detail and focus; state survives the 30 s refresh
const TYPES=["finding","decision","howto","option","topic"],MOTION=!matchMedia("(prefers-reduced-motion: reduce)").matches;
const G={pos:new Map(),nodes:[],byId:new Map(),adj:new Map(),out:new Map(),inn:new Map(),dang:new Map(),links:[],vis:new Set(),match:null,E:[],order:[],
  cam:{x:0,y:0,k:1},userCam:false,first:true,sel:null,hover:null,kb:null,focused:false,hid:new Set(),bad:false,noRetired:false,q:"",
  alpha:0,target:0,raf:0,t0:0,need:false,sig:"",origins:"",w:0,h:0,widths:new Map()};
const hash=s=>{let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return h>>>0};
const trunc=(s,n)=>s.length>n?s.slice(0,n-1)+"…":s;
const rs=n=>n.r*Math.min(1.6,Math.max(.6,G.cam.k));  // radius on screen
const sx=p=>p.x*G.cam.k+G.cam.x,sy=p=>p.y*G.cam.k+G.cam.y;
const shown=id=>G.vis.has(id)||id===G.sel;
function graphEl(){
  if(G.el)return G.el;
  const w=el("div","graph"),bar=el("div","gtool"),q=el("input"),os=el("select"),chips=el("span","chips"),bad=el("label"),ret=el("label");
  q.type="search";q.placeholder="Search title or id";q.setAttribute("aria-label","Search notes by title or id");
  q.oninput=()=>{clearTimeout(G.qt);G.qt=setTimeout(()=>{G.q=q.value.trim().toLowerCase();refilter()},150)};
  q.onkeydown=e=>{if(e.key!=="Enter")return;e.preventDefault();clearTimeout(G.qt);G.q=q.value.trim().toLowerCase();refilter();
    const m=G.nodes.filter(n=>G.match&&G.match.has(n.id)).sort((a,b)=>b.deg-a.deg)[0];if(m){select(m.id);center(m.id)}};
  os.setAttribute("aria-label","Origin");os.onchange=()=>{origin=os.value;refilter()};
  const cb=(lab,txt,key)=>{const i=el("input");i.type="checkbox";i.onchange=()=>{G[key]=i.checked;refilter()};lab.append(i,txt);return i};
  G.cbBad=cb(bad,"Only with problems","bad");G.cbRet=cb(ret,"Hide retired","noRetired");
  bar.append(q,os,chips,bad,ret);
  const box=el("div","gwrap"),cv=el("canvas"),zoom=el("div","gzoom"),tip=el("div","gtip"),det=el("aside","gdet"),msg=el("div","gmsg"),live=el("div","sr");
  cv.tabIndex=0;cv.setAttribute("role","img");tip.hidden=det.hidden=msg.hidden=true;live.setAttribute("aria-live","polite");
  det.setAttribute("aria-label","Note detail");
  [["+","Zoom in",()=>zoomBy(1.25)],["−","Zoom out",()=>zoomBy(.8)],["Fit","Fit the graph in view",()=>fit()]].forEach(([t,a,f])=>{
    const b=el("button","",t);b.setAttribute("aria-label",a);b.title=a;b.onclick=f;zoom.append(b)});
  box.append(cv,zoom,msg,tip,det,live);
  const leg=el("div","legend glegend","Size: links. Dashed yellow ring: past review date. Outline only: retired. Red dot: has problems. Square: topic. Drag a note to pin it, double-click to release it. Keys: Tab, arrows, Enter, Esc, + − 0.");
  const list=el("details","glist"),sum=el("summary"),ul=el("ul");list.append(sum,ul);
  w.append(bar,box,leg,list);
  Object.assign(G,{el:w,cv,ctx:cv.getContext("2d"),tip,det,msg,live,qIn:q,os,chips,ul,sum});
  new ResizeObserver(()=>{const r=box.getBoundingClientRect(),d=devicePixelRatio||1;if(!r.width)return;
    const first=!G.w;G.w=r.width;G.h=r.height;cv.width=Math.round(r.width*d);cv.height=Math.round(r.height*d);
    if(first||(!G.userCam&&G.alpha<.001))fit(true);redraw()}).observe(box);
  pointer(cv);keys(cv);
  return w}
function gUpdate(L){
  graphEl();
  const ids=new Set(L.nodes.map(n=>n.id));let changed=G.first;
  for(const id of [...G.pos.keys()])if(!ids.has(id)){G.pos.delete(id);changed=true}
  G.nodes=L.nodes;G.byId=new Map(L.nodes.map(n=>[n.id,n]));
  G.adj=new Map(),G.out=new Map(),G.inn=new Map(),G.dang=new Map();
  L.nodes.forEach(n=>{G.adj.set(n.id,new Set());G.out.set(n.id,[]);G.inn.set(n.id,[])});
  const E=L.edges.filter(e=>e[0]!==e[1]&&G.byId.has(e[0])&&G.byId.has(e[1]));
  E.forEach(([s,t])=>{G.adj.get(s).add(t);G.adj.get(t).add(s);G.out.get(s).push(t);G.inn.get(t).push(s)});
  (L.dangling||[]).forEach(([s,t])=>{if(G.byId.has(s)){if(!G.dang.has(s))G.dang.set(s,[]);G.dang.get(s).push(t)}});
  L.nodes.forEach(n=>{n.deg=G.adj.get(n.id).size;n.r=Math.min(18,5+2*Math.sqrt(n.deg))});
  const spread=25*Math.sqrt(L.nodes.length+1);
  L.nodes.forEach(n=>{if(G.pos.has(n.id))return;changed=true;
    const h=hash(n.id),a=h/4294967296*2*Math.PI,nb=[...G.adj.get(n.id)].map(x=>G.pos.get(x)).find(Boolean);  // deterministic seed, near a placed neighbour
    const d=nb?30:spread*(.2+(hash(n.id+"r")%1000)/1250);
    G.pos.set(n.id,{x:(nb?nb.x:0)+d*Math.cos(a),y:(nb?nb.y:0)+d*Math.sin(a),vx:0,vy:0,fx:null,fy:null})});
  const sig=E.map(e=>e.join(">")).join("|");if(sig!==G.sig){G.sig=sig;changed=true}
  G.E=E;
  const cnt=new Map();E.forEach(([s,t])=>{cnt.set(s,(cnt.get(s)||0)+1);cnt.set(t,(cnt.get(t)||0)+1)});
  G.links=E.map(([s,t])=>({s:G.pos.get(s),t:G.pos.get(t),k:1/Math.min(cnt.get(s),cnt.get(t)),b:cnt.get(s)/(cnt.get(s)+cnt.get(t))}));
  G.sim=[...G.pos.values()];
  ["sel","kb","hover"].forEach(k=>{if(G[k]&&!G.byId.has(G[k]))G[k]=null});
  const os=L.origins.join("\n");if(os!==G.origins){G.origins=os;  // rebuilt only when the origins change, so an open select survives
    G.os.replaceChildren(...[["","All origins"],...L.origins.map(o=>[o,o])].map(([v,x])=>{const o=el("option","",x);o.value=v;return o}))}
  G.os.hidden=L.origins.length<2;if(!L.origins.includes(origin))origin="";G.os.value=origin;
  refilter();detail();
  if(changed){const f=G.first;G.first=false;heat(f?1:.3,f)}}
function refilter(){
  const pass=n=>(!origin||n.origin===origin)&&(!G.bad||n.problems)&&(!G.noRetired||n.state!=="retired");
  const base=G.nodes.filter(pass),by=new Map();base.forEach(n=>by.set(n.type,(by.get(n.type)||0)+1));
  G.vis=new Set(base.filter(n=>!G.hid.has(TYPES.includes(n.type)?n.type:"topic")).map(n=>n.id));
  G.match=G.q?new Set(G.nodes.filter(n=>G.vis.has(n.id)&&(n.title.toLowerCase().includes(G.q)||n.id.toLowerCase().includes(G.q))).map(n=>n.id)):null;
  G.chips.replaceChildren(...TYPES.map(t=>{const b=el("button","chip"),i=el("i",t==="topic"?"sq":"");i.style.background="var(--t-"+t+")";
    const c=by.get(t)||0;b.append(i,t+" "+c);b.setAttribute("aria-pressed",String(!G.hid.has(t)));b.title=(G.hid.has(t)?"Show ":"Hide ")+t+" notes";
    b.onclick=()=>{G.hid.has(t)?G.hid.delete(t):G.hid.add(t);refilter()};return b}));
  const none=!G.nodes.length,miss=!none&&(!G.vis.size||(G.match&&!G.match.size));
  G.msg.hidden=!(none||miss);
  if(none)G.msg.replaceChildren(el("span","","No notes yet. Import files above."));
  else if(miss){const b=el("button","toggle","Clear filters");b.onclick=clearFilters;G.msg.replaceChildren(el("span","","No note matches"),b)}
  const V=G.nodes.filter(n=>G.vis.has(n.id)),ne=G.links.length,bad=V.filter(n=>n.problems).length,st=V.filter(n=>n.state==="stale").length;
  G.cv.setAttribute("aria-label","Library graph: "+V.length+" of "+G.nodes.length+" notes shown, "+ne+" links, "+bad+" with problems, "+st+" past review date. The list below has the same notes.");
  G.order=V.slice().sort((a,b)=>b.deg-a.deg).map(n=>n.id);
  G.sum.textContent="Notes as a list ("+V.length+")";
  G.ul.replaceChildren(...G.order.map(id=>{const n=G.byId.get(id);const li=el("li"),b=el("button","linkb",n.title);
    li.append(b,el("span","muted"," "+n.type+", "+n.state+(n.problems?", "+n.problems+" problem(s)":"")+", "+n.deg+" link(s)"));
    b.onclick=()=>{select(n.id);center(n.id)};return li}));
  redraw()}
function clearFilters(){G.hid.clear();G.bad=G.noRetired=false;G.cbBad.checked=G.cbRet.checked=false;G.q="";G.qIn.value="";origin="";G.os.value="";refilter()}
// forces: d3-style links and Barnes-Hut repulsion, weak pull to the centre, cooling alpha 1 -> 0.001
const DECAY=1-Math.pow(.001,1/300),CHARGE=-110,DIST=48,TH2=.81;
function qn(x,y,s){return{x,y,s,m:0,cx:0,cy:0,p:null,k:null}}
function qadd(q,p,d){q.cx=(q.cx*q.m+p.x)/(q.m+1);q.cy=(q.cy*q.m+p.y)/(q.m+1);q.m++;
  if(!q.k){if(q.m===1||d>24){(q.p||(q.p=[])).push(p);return}const o=q.p;q.p=null;q.k=[null,null,null,null];o.forEach(x=>qsub(q,x,d))}
  qsub(q,p,d)}
function qsub(q,p,d){const h=q.s/2,i=(p.x>=q.x+h?1:0)+(p.y>=q.y+h?2:0);qadd(q.k[i]||(q.k[i]=qn(q.x+(i&1?h:0),q.y+(i&2?h:0),h)),p,d+1)}
function qforce(q,p,a){
  const dx=q.cx-p.x,dy=q.cy-p.y,l=dx*dx+dy*dy;
  if(q.k&&q.s*q.s/TH2<l){const w=CHARGE*a*q.m/l;p.vx+=dx*w;p.vy+=dy*w;return}
  if(q.k){for(const c of q.k)if(c)qforce(c,p,a);return}
  for(const o of q.p)if(o!==p){let x=o.x-p.x,y=o.y-p.y,d=x*x+y*y;if(!d){x=Math.random()-.5;y=Math.random()-.5;d=x*x+y*y}
    const w=CHARGE*a/Math.max(d,1);p.vx+=x*w;p.vy+=y*w}}
function tick(){
  const a=G.alpha,P=G.sim;G.alpha+=(G.target-G.alpha)*DECAY;if(!P.length)return;
  for(const l of G.links){let x=l.t.x+l.t.vx-l.s.x-l.s.vx||1e-3,y=l.t.y+l.t.vy-l.s.y-l.s.vy||1e-3,d=Math.sqrt(x*x+y*y);
    d=(d-DIST)/d*a*l.k;x*=d;y*=d;l.t.vx-=x*l.b;l.t.vy-=y*l.b;l.s.vx+=x*(1-l.b);l.s.vy+=y*(1-l.b)}
  let x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;for(const p of P){x0=Math.min(x0,p.x);y0=Math.min(y0,p.y);x1=Math.max(x1,p.x);y1=Math.max(y1,p.y)}
  const root=qn(x0,y0,Math.max(x1-x0,y1-y0)+1);for(const p of P)qadd(root,p,0);
  for(const p of P){qforce(root,p,a);p.vx-=p.x*.02*a;p.vy-=p.y*.02*a}
  for(const p of P){if(p.fx!=null){p.x=p.fx;p.y=p.fy;p.vx=p.vy=0}else{p.vx*=.6;p.vy*=.6;p.x+=p.vx;p.y+=p.vy}}}
function heat(a,first){
  G.alpha=Math.max(G.alpha,a);if(!G.t0)G.t0=performance.now();
  if(!MOTION){for(let i=0;i<300&&G.alpha>=.001;i++)tick();G.alpha=0;settle();return}
  if(first){while(G.alpha>.3)tick();if(!G.userCam)fit(true)}  // the first view starts half settled
  kick()}
function settle(){if(G.t0){G.el.dataset.layoutMs=Math.round(performance.now()-G.t0);G.t0=0;if(!G.userCam)fit(true)}redraw()}
function frame(){G.raf=0;
  if(G.alpha>=.001||G.target){const t=performance.now();let n=0;const late=G.t0&&!G.target&&t-G.t0>1000;do{tick();n++}while((late||n<10&&performance.now()-t<12)&&G.alpha>=.001);  // past 1 s, finish without waiting on frames
    if(!G.userCam&&!G.target)fit(true);G.need=true;if(G.alpha<.001&&!G.target)settle()}
  if(G.need)draw();
  if(G.alpha>=.001||G.target)kick()}
function kick(){if(!G.raf)G.raf=requestAnimationFrame(frame)}
function redraw(){G.need=true;kick()}
function fit(auto){
  const P=G.nodes.filter(n=>shown(n.id)).map(n=>G.pos.get(n.id));if(!G.w)return;
  if(!P.length){G.cam={x:G.w/2,y:G.h/2,k:1};redraw();return}
  let x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;P.forEach(p=>{x0=Math.min(x0,p.x);y0=Math.min(y0,p.y);x1=Math.max(x1,p.x);y1=Math.max(y1,p.y)});
  const W=G.w-(G.det.hidden||G.w<640?0:320),k=Math.min(2,Math.max(.2,Math.min((W-80)/(x1-x0||1),(G.h-80)/(y1-y0||1))));
  G.cam={k,x:W/2-(x0+x1)/2*k,y:G.h/2-(y0+y1)/2*k};if(!auto)G.userCam=true;redraw()}
function zoomAt(x,y,k){k=Math.min(4,Math.max(.2,k));const c=G.cam;c.x=x-(x-c.x)*k/c.k;c.y=y-(y-c.y)*k/c.k;c.k=k;G.userCam=true;redraw()}
function zoomBy(f){zoomAt(G.w/2,G.h/2,G.cam.k*f)}
function center(id){const p=G.pos.get(id);if(!p)return;const W=G.w-(G.det.hidden||G.w<640?0:320),H=G.det.hidden||G.w>=640?G.h:G.h*.35;
  G.cam.x=W/2-p.x*G.cam.k;G.cam.y=H/2-p.y*G.cam.k;G.userCam=true;redraw()}
function onScreen(id){const p=G.pos.get(id);if(!p)return;const x=sx(p),y=sy(p);if(x<30||y<30||x>G.w-30||y>G.h-30)center(id)}
function select(id){G.sel=id;if(id)G.kb=id;detail();redraw();if(id)say(id)}
function say(id){const n=G.byId.get(id);if(n)G.live.textContent=n.title+". "+n.type+", "+n.state+", "+n.deg+" link(s)"+(n.problems?", "+n.problems+" problem(s)":"")+"."}
function detail(){
  const D=G.det,n=G.sel&&G.byId.get(G.sel);D.hidden=!n;if(!n)return;
  const x=el("button","x","×");x.setAttribute("aria-label","Close detail");x.onclick=()=>{select(null);G.cv.focus()};
  const dl=el("dl");[["Id",n.id],["Type",n.type],["State",n.state],["Origin",n.origin||"-"],["Confidence",n.confidence||"-"],["Updated",n.updated||"-"],["Review by",n.review_by||"-"]]
    .forEach(([k,v])=>dl.append(el("dt","",k),el("dd","",v)));
  const sec=(t,ids,dead)=>{const d=el("div");d.append(el("b","",t+" ("+(ids.length+(dead||[]).length)+")"));if(!ids.length&&!(dead||[]).length)return d;const u=el("ul");
    ids.forEach(i=>{const m=G.byId.get(i),b=el("button","linkb",m?m.title:i);b.title=i+(shown(i)?"":" (hidden by the filters)");b.onclick=()=>{select(i);center(i)};const li=el("li");li.append(b);u.append(li)});
    (dead||[]).forEach(i=>u.append(el("li","muted",i+" (missing note)")));d.append(u);return d};
  const pr=el("div");pr.append(el("b","","Problems ("+n.problems+")"));
  if(n.problems){const u=el("ul");(n.issues||[]).forEach(t=>u.append(el("li","",t)));if(n.problems>(n.issues||[]).length)u.append(el("li","muted","More: library.sh doctor"));pr.append(u)}
  D.replaceChildren(x,el("h3","",n.title),dl,pr,sec("Links out",G.out.get(n.id)||[],G.dang.get(n.id)),sec("Backlinks",G.inn.get(n.id)||[]))}
function hit(mx,my){let best=null,bd=Infinity;for(const n of G.nodes){if(!shown(n.id))continue;const p=G.pos.get(n.id),r=rs(n)+4,d=(sx(p)-mx)**2+(sy(p)-my)**2;
  if(d<r*r&&d<bd){bd=d;best=n.id}}return best}
function tipAt(id,x,y){const t=G.tip,n=id&&G.byId.get(id);t.hidden=!n;if(!n)return;
  t.replaceChildren(el("b","",n.title),el("div","muted",n.type+" · "+n.state+(n.problems?" · "+n.problems+" problem(s)":"")+" · "+n.deg+" link(s)"));
  const w=t.offsetWidth,h=t.offsetHeight;t.style.left=Math.min(G.w-w-6,x+14)+"px";t.style.top=(y+14+h>G.h?y-h-10:y+14)+"px"}
function pointer(cv){
  const P=new Map();let drag=null;const xy=e=>{const r=cv.getBoundingClientRect();return[e.clientX-r.left,e.clientY-r.top]};
  cv.addEventListener("wheel",e=>{e.preventDefault();const[x,y]=xy(e);zoomAt(x,y,G.cam.k*Math.exp(-e.deltaY*(e.deltaMode?.05:.0015)))},{passive:false});
  cv.onpointerdown=e=>{cv.setPointerCapture(e.pointerId);const[x,y]=xy(e);P.set(e.pointerId,[x,y]);G.tip.hidden=true;
    if(P.size===2){const[a,b]=[...P.values()];drag={pinch:1,d:Math.hypot(a[0]-b[0],a[1]-b[1])||1,k:G.cam.k,moved:true};return}
    const id=hit(x,y);drag={id,x,y,cx:G.cam.x,cy:G.cam.y,moved:false}};
  cv.onpointermove=e=>{const[x,y]=xy(e);if(P.has(e.pointerId))P.set(e.pointerId,[x,y]);
    if(!drag){const id=hit(x,y);if(id!==G.hover){G.hover=id;cv.style.cursor=id?"pointer":"grab";redraw()}tipAt(id,x,y);return}
    if(drag.pinch){if(P.size<2)return;const[a,b]=[...P.values()];zoomAt((a[0]+b[0])/2,(a[1]+b[1])/2,drag.k*Math.hypot(a[0]-b[0],a[1]-b[1])/drag.d);return}
    if(!drag.moved&&(x-drag.x)**2+(y-drag.y)**2<16)return;drag.moved=true;
    if(drag.id){const p=G.pos.get(drag.id);G.userCam=true;p.fx=(x-G.cam.x)/G.cam.k;p.fy=(y-G.cam.y)/G.cam.k;  // a dragged note stays pinned
      if(MOTION){G.target=.3;G.alpha=Math.max(G.alpha,.3);kick()}else{p.x=p.fx;p.y=p.fy;redraw()}}
    else{G.cam.x=drag.cx+x-drag.x;G.cam.y=drag.cy+y-drag.y;G.userCam=true;redraw()}};
  const up=e=>{P.delete(e.pointerId);if(!drag)return;
    if(!drag.pinch){if(drag.id){G.target=0;if(!drag.moved)select(drag.id)}else if(!drag.moved&&e.type==="pointerup")select(null)}
    if(!P.size)drag=null};
  cv.onpointerup=cv.onpointercancel=up;
  cv.onpointerleave=()=>{if(!drag&&G.hover){G.hover=null;redraw()}G.tip.hidden=true};
  cv.ondblclick=e=>{const[x,y]=xy(e),id=hit(x,y);if(!id)return;const p=G.pos.get(id);p.fx=p.fy=null;if(MOTION)heat(.3);else redraw()}}
function keys(cv){
  const kf=()=>{G.focused=true;if(!G.kb||!shown(G.kb)){const t=G.nodes.filter(n=>G.vis.has(n.id)).sort((a,b)=>b.deg-a.deg)[0];G.kb=G.sel||(t&&t.id)}
    if(G.kb){onScreen(G.kb);say(G.kb)}redraw()};
  cv.onfocus=()=>{if(cv.matches(":focus-visible"))kf()};  // the ring is for the keyboard, not a click
  cv.onblur=()=>{G.focused=false;redraw()};
  cv.onkeydown=e=>{const k=e.key;if(!G.focused)kf();
    if(k==="+"||k==="=")zoomBy(1.25);else if(k==="-"||k==="_")zoomBy(.8);else if(k==="0")fit();
    else if(k.startsWith("Arrow")&&G.kb){const d={ArrowRight:[1,0],ArrowLeft:[-1,0],ArrowDown:[0,1],ArrowUp:[0,-1]}[k],p=G.pos.get(G.kb);let best=null,bs=Infinity;
      for(const n of G.nodes){if(n.id===G.kb||!G.vis.has(n.id))continue;const q=G.pos.get(n.id),x=q.x-p.x,y=q.y-p.y,a=x*d[0]+y*d[1];if(a<=0)continue;
        const s=(a+2*Math.abs(x*d[1]-y*d[0]))*(G.adj.get(G.kb).has(n.id)?.7:1);if(s<bs){bs=s;best=n.id}}  // nearest in that direction, links first
      if(best){G.kb=best;onScreen(best);say(best);redraw()}}
    else if((k==="Enter"||k===" ")&&G.kb)select(G.kb);
    else if(k==="Escape"){if(G.sel)select(null);else return}
    else return;e.preventDefault()}}
function draw(){
  G.need=false;const c=G.ctx,W=G.w,H=G.h,dp=devicePixelRatio||1;if(!W)return;
  c.setTransform(dp,0,0,dp,0,0);c.clearRect(0,0,W,H);
  const cs=getComputedStyle(G.el),v=n=>cs.getPropertyValue(n).trim(),C={edge:v("--edge"),fg:v("--fg"),card:v("--card"),y:v("--yellow"),r:v("--red")},T={};
  TYPES.forEach(t=>T[t]=v("--t-"+t));
  const act=G.hover||(G.focused&&G.kb)||G.sel,hl=act?new Set([act,...G.adj.get(act)]):null,M=G.match;
  const lit=id=>hl?hl.has(id):M?M.has(id):true,k=G.cam.k;
  const lines=(L,col,w,al)=>{if(!L.length)return;c.globalAlpha=al;c.strokeStyle=col;c.lineWidth=w;c.beginPath();
    for(const l of L){c.moveTo(sx(l.s),sy(l.s));c.lineTo(sx(l.t),sy(l.t))}c.stroke()};
  const dim=[],on=[],hot=[];
  for(const[s,t]of G.E){if(!shown(s)||!shown(t))continue;const l={s:G.pos.get(s),t:G.pos.get(t),tn:G.byId.get(t)};
    (hl?(s===act||t===act?hot:dim):M?(M.has(s)&&M.has(t)?on:dim):on).push(l)}
  lines(dim,C.edge,1,.15);lines(on,C.edge,1,1);lines(hot,C.fg,1.5,1);
  if(k>1.5)for(const[L,col]of[[on,C.edge],[hot,C.fg]]){c.globalAlpha=1;c.fillStyle=col;for(const l of L){  // arrows only when zoomed in
    const x1=sx(l.s),y1=sy(l.s),x2=sx(l.t),y2=sy(l.t),a=Math.atan2(y2-y1,x2-x1),r=rs(l.tn)+2,ex=x2-r*Math.cos(a),ey=y2-r*Math.sin(a);
    c.beginPath();c.moveTo(ex,ey);c.lineTo(ex-7*Math.cos(a-.4),ey-7*Math.sin(a-.4));c.lineTo(ex-7*Math.cos(a+.4),ey-7*Math.sin(a+.4));c.fill()}}
  const shape=(x,y,r,sq)=>{c.beginPath();if(sq)c.rect(x-r*.89,y-r*.89,r*1.78,r*1.78);else c.arc(x,y,r,0,2*Math.PI)};
  for(const n of G.nodes){if(!shown(n.id))continue;const p=G.pos.get(n.id),x=sx(p),y=sy(p),r=rs(n);if(x<-30||y<-30||x>W+30||y>H+30)continue;
    const a=lit(n.id)?1:.15,sq=n.type==="topic",col=T[n.type]||T.topic;
    if(n.state==="retired"){c.globalAlpha=a*.4;shape(x,y,r,sq);c.strokeStyle=col;c.lineWidth=1.5;c.stroke()}
    else{c.globalAlpha=a;shape(x,y,r,sq);c.fillStyle=col;c.fill();c.strokeStyle=C.card;c.lineWidth=1;c.stroke()}
    c.globalAlpha=a;
    if(n.state==="stale"){c.setLineDash([3,3]);shape(x,y,r+3.5,sq);c.strokeStyle=C.y;c.lineWidth=2;c.stroke();c.setLineDash([])}
    if(n.problems){c.beginPath();c.arc(x+r*.8,y-r*.8,2.5,0,2*Math.PI);c.fillStyle=C.r;c.fill();c.strokeStyle=C.card;c.lineWidth=1;c.stroke()}
    if(n.id===G.sel){shape(x,y,r+5,sq);c.strokeStyle=C.fg;c.lineWidth=2.5;c.stroke()}
    if(G.focused&&n.id===G.kb){c.setLineDash([4,3]);shape(x,y,r+8,sq);c.strokeStyle=C.fg;c.lineWidth=2;c.stroke();c.setLineDash([])}}
  // labels: forced ones first, then by degree, while there is room and the zoom allows
  c.font="12px -apple-system,system-ui,sans-serif";c.textBaseline="middle";c.lineJoin="round";
  const force=hl?[...hl]:M?[...M].slice(0,40):[],budget=hl||M?0:k<.5?10:k<1?25:k<2?80:500;
  if(G.sel&&!force.includes(G.sel))force.unshift(G.sel);
  const order=force.concat(G.order.slice(0,budget)),placed=new Map(),done=new Set();
  const free=(x0,y0,x1,y1)=>{for(let i=Math.floor(x0/96);i<=Math.floor(x1/96);i++)for(let j=Math.floor(y0/16);j<=Math.floor(y1/16);j++)
    for(const b of placed.get(i+","+j)||[])if(x0<b[2]&&x1>b[0]&&y0<b[3]&&y1>b[1])return false;return true};
  for(const id of order){if(done.has(id)||!shown(id))continue;done.add(id);const n=G.byId.get(id),p=G.pos.get(id),r=rs(n),t=trunc(n.title,32);
    let w=G.widths.get(t);if(w==null){w=c.measureText(t).width;G.widths.set(t,w)}
    const x=sx(p)+r+4+w>W-4?sx(p)-r-4-w:sx(p)+r+4,y=sy(p),b=[x-2,y-8,x+w+2,y+8];  // flips left at the right edge
    if(b[0]<0||b[2]>W||b[1]<0||b[3]>H||!free(...b))continue;
    for(let i=Math.floor(b[0]/96);i<=Math.floor(b[2]/96);i++)for(let j=Math.floor(b[1]/16);j<=Math.floor(b[3]/16);j++){const q=i+","+j;if(!placed.has(q))placed.set(q,[]);placed.get(q).push(b)}
    c.globalAlpha=1;c.lineWidth=3;c.strokeStyle=C.card;c.strokeText(t,x,y);c.fillStyle=C.fg;c.fillText(t,x,y)}
  c.globalAlpha=1}
function list(title,items,fmt){const d=el("div");d.append(el("b","",title+" ("+items.length+")"));
  if(items.length){const u=el("ul");items.slice(0,8).forEach(x=>u.append(el("li","",fmt(x))));if(items.length>8)u.append(el("li","","and "+(items.length-8)+" more: library.sh doctor"));d.append(u)}
  return d}
function drawMap(p){
  const wrap=el("div","map"),cols=el("div","cols"),nodes=new Map(),stageOf=new Map(p.items.map(i=>[i.id,i.stage])),lines=[];
  const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");svg.setAttribute("class","edges");cols.append(svg);
  p.stage_names.forEach(s=>{
    const c=el("div","col");c.append(el("h3","",s.n+". "+s.name));
    p.items.filter(i=>i.stage===s.n).forEach(i=>{const n=el("div","node "+i.state);n.title=i.what+" ("+i.state+")";n.tabIndex=0;
      n.append(el("b","",i.id),el("small","",i.card));const same=i.needs.filter(x=>stageOf.get(x)===i.stage);
      if(same.length)n.append(el("small","dep","↳ "+same.join(", ")));  // a need in the same stage: a marker, not a loop
      n.onmouseenter=n.onfocus=()=>mark(i.id,true);n.onmouseleave=n.onblur=()=>mark(i.id,false);nodes.set(i.id,n);c.append(n)});
    cols.append(c);
    if(s.n===p.delivery){const f=el("div","finish"+(p.delivered?" reached":""));f.append(el("span","",p.delivered?"Delivered":"Delivery"));cols.append(f)}
  });
  const mark=(id,on)=>{const it=p.items.find(x=>x.id===id);  // what this item needs (solid) and what needs it (dashed)
    (it?it.needs:[]).forEach(x=>{const n=nodes.get(x);if(n)n.classList.toggle("pre",on)});
    p.items.filter(x=>x.needs.includes(id)).forEach(x=>nodes.get(x.id).classList.toggle("post",on));
    lines.forEach(([a,b,e])=>e.classList.toggle("hot",on&&(a===id||b===id)))};
  wrap.append(cols,el("div","legend","Outlined: can start now. Grey, dashed: waiting on a prerequisite. Struck through: not applicable. ↳ id: needs that item of the same stage. Green edge: done. Point at an item: solid outline = what it needs, dashed = what needs it."));
  requestAnimationFrame(()=>{const o=cols.getBoundingClientRect();svg.setAttribute("width",cols.scrollWidth);svg.setAttribute("height",cols.scrollHeight);
    const pos=n=>{const b=n.getBoundingClientRect();return{l:b.left-o.left,r:b.right-o.left,y:b.top-o.top+b.height/2}};
    p.items.forEach(i=>i.needs.forEach(nm=>{const a=nodes.get(nm),b=nodes.get(i.id);if(!a||!b||stageOf.get(nm)===i.stage)return;const A=pos(a),B=pos(b);
      const path=document.createElementNS("http://www.w3.org/2000/svg","path");
      const d=A.r<B.l?`M${A.r},${A.y} C${A.r+16},${A.y} ${B.l-16},${B.y} ${B.l},${B.y}`:`M${A.l},${A.y} C${A.l-14},${A.y} ${B.l-14},${B.y} ${B.l},${B.y}`;
      path.setAttribute("d",d);const st=p.items.find(x=>x.id===nm);if(st&&st.state==="done")path.setAttribute("class","ok");lines.push([nm,i.id,path]);svg.append(path)}))});
  return wrap}
async function load(){
  const r=await fetch("api?t="+encodeURIComponent(T)+"&lib="+encodeURIComponent(libName));if(!r.ok){document.getElementById("msg").textContent="Panel stopped. Start it again.";return}
  last=await r.json();render()}
function render(){
  const d=last;if(!d)return;
  document.getElementById("overall").className="dot "+d.overall;
  document.getElementById("time").textContent="Updated "+d.time;
  const ws=document.getElementById("ws");
  ws.textContent=d.workspace+(d.shared?" · shared, you are "+(d.shared.member||"unnamed")+" · last sync "+d.shared.sync:"");
  if(d.source)ws.textContent+=d.source.commit?" · showing GitHub at "+d.source.commit+", fetched "+d.source.fetched+(d.source.error?" ("+d.source.error+")":""):" · "+d.source.error;
  // teammates' data past a few minutes old: say how old, in a label that keeps the text contrast
  const lag=d.source&&d.source.commit?d.source:d.shared;
  if(lag&&(lag.late||(d.shared&&d.shared.color!=="green"))){const p=el("span","pill"+(d.shared&&d.shared.color==="red"?" red":""));
    p.append(el("span","dot "+(d.shared&&d.shared.color==="red"?"red":"yellow")),lag.as_of?"Teammate data as of sync "+lag.as_of+(lag.age!=null?" ("+ago(lag.age)+" old)":""):"Teammate data: no sync yet");
    ws.append(" ",p)}
  document.getElementById("fetch").hidden=!d.source;
  const P=document.getElementById("projects");
  if(!d.projects.length)empty(P,"No projects");else P.replaceChildren(...d.projects.map(p=>{
    const row=el("div","row"),body=el("div","grow");row.append(el("span","dot "+p.color),body);
    body.append(el("div","name",p.slug+(p.member?" · "+p.member:"")));
    const rs=p.reasons||[];if(rs.length<2)body.append(el("div","",p.reason));
    else{const li=r=>{const x=el("li");x.append(el("span","dot "+r.color),el("span","",r.text));return x},u=el("ul","why");  // every reason, worst first
      rs.slice(0,3).forEach(r=>u.append(li(r)));
      if(rs.length>3){const m=el("details"),w=el("ul","why");m.append(el("summary","",(rs.length-3)+" more reason(s)"));rs.slice(3).forEach(r=>w.append(li(r)));m.append(w);const lm=el("li");lm.append(m);u.append(lm)}
      body.append(u)}
    if((p.outside||[]).length){const f=el("div","facts");f.append(el("b","","Seen as a stranger: "));
      p.outside.forEach(o=>{const okk=o.state==="ok",x=el("span","pill"+(okk?"":" red"));x.style.borderColor=okk?"var(--line)":"";
        x.append(el("span","dot "+(okk?"green":"yellow")),o.kind==="public"?o.url.replace(/^https?:\/\//,"")+" "+o.code+(okk?" opens logged out":" closed to a logged-out visitor")
          :"production "+o.url.replace(/^https?:\/\//,"")+(o.state==="ok"?" serves "+o.commit:o.state==="down"?" does not answer":" does not serve "+o.commit));f.append(x)});
      body.append(f)}
    if((p.decisions||[]).length){const f=el("div","facts"),u=el("ul");f.append(el("b","","Decisions in force (latest "+p.decisions.length+")"));
      p.decisions.forEach(x=>u.append(el("li","",x.when+" · "+x.what+(x.who?" ("+x.who+")":""))));f.append(u);body.append(f)}
    if(p.target)body.append(el("div","muted","Target: "+p.target+(/^none( |$)/.test(p.check)?" · no outside check"+p.check.slice(4):p.check?" · check: "+p.check:"")+(p.runs?" · agent runs: first "+p.runs.replace(" -> ",", now "):"")));
    if(p.deadline&&!p.delivered){const m=Math.round((p.deadline*1000-Date.now())/60000);
      body.append(el("div","muted",m<0?"Deadline passed "+ago(-m)+" ago":"Deadline in "+ago(m)))}
    if(p.total){const b=el("div","bar"),i=el("i");i.style.width=(100*p.closed/p.total)+"%";b.append(i);
      const diff=p.baseline!==""?p.total-p.baseline:0,moved=p.baseline_delivery!==""&&p.baseline_delivery!==p.delivery;
      body.append(b,el("div","muted",p.closed+" of "+p.total+" deliverables closed"+(diff>0?", "+diff+" added since opening":"")+(diff<0?", "+(-diff)+" removed since opening":"")+(moved?", delivery line moved from stage "+p.baseline_delivery+" to "+p.delivery:"")+
        (p.delivered?". Original request delivered.":". "+p.brief)));
      body.append(drawMap(p))}
    else if(p.next)body.append(el("div","muted","Next: "+p.next));
    (p.progress||[]).forEach(g=>body.append(el("div","muted","Latest on "+g.card+" ("+g.when+", "+g.who+"): "+g.what)));
    return row}));
  const C=document.getElementById("cards");
  if(!d.cards.length)empty(C,"Nothing waiting");else C.replaceChildren(...d.cards.map(c=>{
    const row=el("div","row"),b=el("div","grow");row.append(el("span","dot "+c.color),b);
    b.append(el("div","name",c.title+(c.project?" ("+c.project+")":"")+(c.member?" · "+c.member:"")));
    if(c.questions.length){const u=el("ul","q");c.questions.forEach((x,i)=>{const li=el("li","",x+" "),a=(c.ages||[])[i];
      li.append(el("span","age",a!=null?"· asked "+ago(a)+" ago":"· no time stamp"));u.append(li)});b.append(u)}
    if(c.deputy){const x=el("div","pill red");x.append(el("span","dot red"),"Past the limit with the deadline under 3 h: if the owner cannot answer now, "+c.deputy+" (deputy) decides");b.append(x)}
    if(c.size)b.append(el("div","muted","Card too long to read ("+c.size+"): move what is done to board/archive/"));
    row.append(el("span",c.color==="red"?"":"muted","Waiting "+ago(c.waited)+(c.color==="red"?", past "+c.limit+" min":"")));return row}));
  const K=document.getElementById("tasks");
  if(!(d.tasks||[]).length)empty(K,"No tasks");else K.replaceChildren(...d.tasks.map(g=>{
    const row=el("div","row"),b=el("div","grow");row.append(b);b.append(el("div","name",g.who));
    const u=el("ul","q");g.items.forEach(x=>u.append(el("li","",x.task+" · "+x.card)));b.append(u);return row}));
  document.getElementById("lib").textContent=d.inbox+" item(s) in the inbox, "+d.notes+" note(s) in the library.";
  const B=document.getElementById("library"),L=d.library,head=el("div","row"),hb=el("div","grow");head.append(el("span","dot "+L.color),hb);
  if(d.libs.length>1){const s=el("select");s.setAttribute("aria-label","Library");d.libs.forEach(x=>{const o=el("option","",x.name+(x.name==="personal"?"":" (team)")+", "+x.notes+" notes");o.value=x.name;if(x.name===L.name)o.selected=true;s.append(o)});
    s.onchange=()=>{libName=s.value;origin="";G.sel=null;load()};hb.append(s);const cur=d.libs.find(x=>x.name===L.name);
    if(cur&&cur.sync!=="-"){const y=el("div","","Last sync: "+cur.sync);y.style.color=cur.sync_color==="green"?"var(--muted)":"var(--"+cur.sync_color+")";hb.append(y)}}
  // the graph element is never detached, so focus, camera, selection and positions survive the refresh
  if(!B.lslots){B.lslots=[el("div"),graphEl(),el("div"),el("div")];B.replaceChildren(...B.lslots)}
  const[hs,gr,more,lsl]=B.lslots;hs.replaceChildren(head);
  if(L.state!=="online"){hb.append(el("div","name",L.state==="offline"?"Library offline":"Library error"),el("div","muted",L.message));gr.hidden=true;more.replaceChildren();lsl.replaceChildren()}
  else{hb.append(el("div","name",L.total+" notes"+(L.retired?", "+L.retired+" retired":"")),el("div","muted",L.path));
    gr.hidden=false;gUpdate(L);
    more.replaceChildren(...(L.total>L.nodes.length?[el("div","empty","Showing the "+L.nodes.length+" most linked notes of "+L.total+".")]:[]));
    const ls=el("div","lists"),title=id=>{const n=G.byId.get(id);return n?n.title+" ["+id+"]":id};
    ls.append(list("With problems",L.problems,title),list("Broken links",L.dangling,x=>title(x[0])+" → "+x[1]),
      list("Past review date",L.stale,title),list("Possible duplicates",L.pairs,x=>title(x[0])+" / "+title(x[1])));
    lsl.replaceChildren(ls)}
  const U=document.getElementById("turns"),n=(v,t,c)=>{const x=el("div");const b=el("b","",String(v));if(c&&v)b.style.color="var(--"+c+")";x.append(b,el("span","muted",t));return x};
  U.replaceChildren(n(d.counts.turns,"turns"),n(d.counts.violations,"broke the protocol","red"),n(d.counts.rejected,"notes rejected","yellow"));
}
async function send(body,name,kind){
  const m=document.getElementById("msg");m.textContent="Saving…";
  const r=await fetch("import?t="+encodeURIComponent(T),{method:"POST",body,headers:{"X-Name":encodeURIComponent(name),"X-Kind":kind}});
  const t=await r.text();m.textContent=r.ok?"Saved to the inbox. Ask central to process it."+t.slice(5):t;load()}
const drop=document.getElementById("drop"),file=document.getElementById("file");
drop.onclick=()=>file.click();file.onchange=()=>[...file.files].forEach(f=>send(f,f.name,"file"));
drop.ondragover=e=>{e.preventDefault();drop.classList.add("over")};drop.ondragleave=()=>drop.classList.remove("over");
drop.ondrop=e=>{e.preventDefault();drop.classList.remove("over");[...e.dataTransfer.files].forEach(f=>send(f,f.name,"file"))};
document.getElementById("linkform").onsubmit=e=>{e.preventDefault();const v=document.getElementById("link").value.trim();
  if(v){send(v,"link.md","text");document.getElementById("link").value=""}};
load();setInterval(load,30000);
document.getElementById("fetch").onclick=async e=>{const b=e.target;b.disabled=true;b.textContent="Fetching…";
  try{const r=await fetch("fetch?t="+encodeURIComponent(T)+"&lib="+encodeURIComponent(libName),{method:"POST"});if(r.ok)await load()}finally{b.disabled=false;b.textContent="Fetch"}};
</script></body></html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    root = token = None
    timeout = 30  # a client that stalls mid-request frees its thread instead of holding it forever

    def log_message(self, *a):
        pass

    def deny(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def allowed(self):
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        got = q.get("t", [""])[0].encode("utf-8", "replace")  # compare_digest raises on non-ASCII str
        if host not in ("127.0.0.1", "localhost") or not secrets.compare_digest(got, self.token.encode()):
            self.deny(403, "Open the panel with the link it printed when it started.")
            return False
        return True

    def reply(self, ctype, body, nonce=""):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")  # the token is in the URL: never send it on
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'nonce-%s'; script-src 'nonce-%s'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" % (nonce, nonce))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.allowed():
            return
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            n = secrets.token_urlsafe(16)  # per response: an injected <script> without it does not run
            self.reply("text/html; charset=utf-8", PAGE.replace("<style>", '<style nonce="%s">' % n, 1).replace("<script>", '<script nonce="%s">' % n, 1).encode(), n)
        elif path == "/api":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            self.reply("application/json", json.dumps(snapshot(self.root, (q.get("lib") or ["personal"])[0])).encode())
        else:
            self.deny(404, "Not found.")

    def do_POST(self):
        if not self.allowed():
            return
        if urllib.parse.urlparse(self.path).path == "/fetch":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            return self.reply("application/json", json.dumps(snapshot(self.root, (q.get("lib") or ["personal"])[0], fetch=True)).encode())
        if urllib.parse.urlparse(self.path).path != "/import":
            return self.deny(404, "Not found.")
        try:
            size = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            size = -1
        if size <= 0:
            return self.deny(400, "Nothing to save: choose a file or paste a link.")
        if size > MAX_UPLOAD:
            return self.deny(413, "File over 50 MB: split it, or paste a link to it instead.")
        data = self.rfile.read(size)
        if len(data) != size:
            return self.deny(400, "The upload was cut off. Send it again.")
        name = safe_name(urllib.parse.unquote(self.headers.get("X-Name", "")))
        if self.headers.get("X-Kind") == "text":
            text = data.decode("utf-8", errors="replace").strip()
            if not text:
                return self.deny(400, "Nothing to save: choose a file or paste a link.")
            data = ("---\nsource: %s\nreceived: %s\nvia: panel\n---\n" % (text.splitlines()[0][:300], time.strftime("%Y-%m-%d"))
                    + text + "\n").encode()
        where = rows(sh("library.sh", "where", cwd=self.root))
        if len(where) != 1:
            return self.deny(503, where[1] if len(where) > 1 else "The library is not reachable.")
        inbox = os.path.join(where[0], "inbox")
        os.makedirs(inbox, exist_ok=True)
        try:
            with open(os.path.join(inbox, name), "xb") as f:
                f.write(data)
        except FileExistsError:
            return self.deny(409, "A file with that name arrived the same second. Send it again.")
        warn = b" Warning: it looks like it holds a key or token; remove it before the library is shared." if SECRET.search(data) else b""
        self.reply("text/plain; charset=utf-8", b"saved" + warn)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python3 panel.py <workspace> [port]")
    root = find_root(sys.argv[1])
    if not root:
        sys.exit("No chief-of-staff workspace at %s. Run /chief-of-staff:setup first." % sys.argv[1])
    Handler.root, Handler.token = root, secrets.token_urlsafe(18)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 0), Handler)
    print("Panel: http://127.0.0.1:%d/?t=%s" % (srv.server_address[1], Handler.token), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
