#!/usr/bin/env python3
"""Local panel for a chief-of-staff workspace: health per project, track progress, cards waiting on
the owner, the last 24 hours in three counts (turns, protocol breaks, rejected notes), and an import box that drops files or links into
knowledge/inbox/. Standard library only. Listens on 127.0.0.1; every request needs the token in the URL.

Usage: python3 panel.py <workspace> [port]     (port 0 or omitted = a free port)
"""
import http.server, json, os, re, secrets, subprocess, sys, time, urllib.parse

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


MAX_NODES = 300  # an SVG graph of thousands of notes freezes the browser; the lists below stay complete



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
    nodes, edges, dangling, pairs, retired = [], [], [], [], 0
    try:
        graph = sh("library.sh", "--lib", name, "graph", cwd=root, strict=True)
    except TimeoutError:
        return {"state": "error", "path": path, "message": "Checking the library took over 20 s; run library.sh doctor.",
                "color": "yellow", "nodes": [], "edges": [], "problems": [], "dangling": [], "stale": [], "pairs": []}
    for line in rows(graph):
        f = line.split("\t")
        if f[0] == "N" and len(f) >= 9:
            nodes.append({"id": f[1], "title": f[2], "type": f[3], "state": f[4], "origin": f[5], "group": f[6],
                          "problems": int(f[7] or 0), "in": int(f[8] or 0)})
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
    return {"member": me, "sync": sync or "never", "color": sync_color(sync or "never")}


def sync_color(text):
    return "red" if ("conflict" in text or "failed" in text) else "yellow" if ("never" in text or "busy" in text) else "green"


def snapshot(root, libname="personal"):
    projects = []
    for line in rows(sh("health.sh", root)):
        f = (line.split(US) + [""] * 16)[:16]
        slug, color, reason, stage, stages, closed, total, delivery, delivered, baseline, baseline_delivery, deadline, member, target, check, runs = f
        pdir = os.path.join(root, "projects", slug)
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
            "progress": progress(root, slug),
        })
    libs = libraries(root)
    if libname not in [x["name"] for x in libs]:
        libname = "personal"
    lib = library(root, libname)
    lib["name"] = libname
    rank = {"red": 2, "yellow": 1, "green": 0}
    overall = max([p["color"] for p in projects] + [lib["color"]], key=lambda c: rank.get(c, 0))

    cards = []  # what waits on the owner, from health.sh (the one place that times and colors it)
    for line in rows(sh("health.sh", "cards", root)):
        f = (line.split(US) + [""] * 11)[:11]
        if f[0] == "C" and f[3] == "waiting-owner":
            cards.append({"title": f[1], "project": f[2], "member": f[4], "color": f[5], "waited": int(f[6] or 0),
                          "limit": f[7], "questions": [q for q in f[10].split("\x1e") if q]})

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
    return {"library": lib, "libs": libs, "workspace": root, "overall": overall, "projects": projects, "cards": cards,
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
--green:#2e9b55;--yellow:#c98a00;--red:#d6453d}
@media (prefers-color-scheme:dark){:root{--bg:#161617;--fg:#f2f2f2;--muted:#a1a1a6;--card:#1f1f21;--line:#333}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,system-ui,sans-serif}
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
.toggle{background:none;color:var(--fg);border:1px solid var(--line);padding:4px 10px;font-size:12px;margin-top:8px}
.map{overflow-x:auto;margin-top:10px}
.cols{display:flex;gap:28px;position:relative;padding:22px 2px 10px 40px;width:max-content}
.col{display:flex;flex-direction:column;gap:8px;width:160px;flex:none;position:relative;z-index:1}
.col h3{font-size:12px;margin:0 0 2px;color:var(--muted);font-weight:600}
.node{border:1.5px solid var(--line);border-radius:8px;padding:6px 8px;font-size:12px;background:var(--card)}
.node b{display:block;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.node small{color:var(--muted)}
.node.done{border-color:var(--green);box-shadow:inset 3px 0 0 var(--green)}
.node.na{border-style:dashed;opacity:.55}
.node.ready{border-color:var(--fg)}
.node.blocked{opacity:.45}
.finish{flex:none;width:0;border-left:2px dashed var(--yellow);position:relative;z-index:1}
.finish span{position:absolute;top:-20px;transform:translateX(-50%);font-size:11px;font-weight:600;color:var(--yellow);white-space:nowrap}
.finish.reached{border-color:var(--green)}.finish.reached span{color:var(--green)}
.legend{font-size:12px;color:var(--muted);margin-top:4px}
svg.edges{position:absolute;left:0;top:0;pointer-events:none;z-index:0;overflow:visible}
svg.edges path{fill:none;stroke:var(--line);stroke-width:1.5}
svg.edges path.ok{stroke:var(--green);opacity:.6}
svg.lgraph{width:100%;height:440px;display:block;border-top:1px solid var(--line)}
svg.lgraph line{stroke:var(--line);stroke-width:1}
svg.lgraph circle{stroke:var(--card);stroke-width:1.5}
svg.lgraph circle.active{fill:var(--green)}svg.lgraph circle.stale{fill:var(--yellow)}svg.lgraph circle.retired{fill:var(--muted);opacity:.5}
svg.lgraph circle.bad{stroke:var(--red);stroke-width:3}
svg.lgraph text{font-size:10px;fill:var(--muted)}
.counts{display:grid;grid-template-columns:repeat(3,1fr)}.counts div{padding:14px 16px;border-left:1px solid var(--line)}.counts div:first-child{border-left:0}
.counts b{display:block;font-size:24px;font-weight:600}.q{margin:4px 0 0;padding-left:18px;font-size:13px}
.lists{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:0;border-top:1px solid var(--line)}
.lists div{padding:12px 16px;font-size:13px}.lists b{display:block;margin-bottom:4px}.lists ul{margin:0;padding-left:16px;color:var(--muted)}
select{font:inherit;font-size:12px;padding:3px 6px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg);margin-left:8px}
</style></head><body><main>
<div class="top"><span id="overall" class="dot"></span><h1>Chief of staff</h1><span class="grow"></span><span id="time" class="muted"></span></div>
<div id="ws" class="muted"></div>
<h2>Projects</h2><div id="projects" class="box"></div>
<h2>Waiting on the owner</h2><div id="cards" class="box"></div>
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
const openMaps=new Set();let last=null,graphOpen=false,origin="",libName="personal";
const SVG=t=>document.createElementNS("http://www.w3.org/2000/svg",t);
function drawGraph(L){
  const W=900,H=440,nodes=L.nodes.filter(n=>!origin||n.origin===origin),at=new Map();
  nodes.forEach((n,i)=>{const a=2*Math.PI*i/Math.max(nodes.length,1);at.set(n.id,{n,x:W/2+180*Math.cos(a),y:H/2+150*Math.sin(a),vx:0,vy:0})});
  const E=L.edges.filter(e=>at.has(e[0])&&at.has(e[1]));
  for(let k=0;k<220;k++){const P=[...at.values()];  // small force layout: repulsion, springs on links, pull to the centre
    for(let i=0;i<P.length;i++)for(let j=i+1;j<P.length;j++){const a=P[i],b=P[j];let dx=a.x-b.x,dy=a.y-b.y,d=dx*dx+dy*dy+.01;const f=900/d;a.vx+=dx*f;a.vy+=dy*f;b.vx-=dx*f;b.vy-=dy*f}
    E.forEach(([s,t])=>{const a=at.get(s),b=at.get(t),dx=b.x-a.x,dy=b.y-a.y;a.vx+=dx*.02;a.vy+=dy*.02;b.vx-=dx*.02;b.vy-=dy*.02});
    P.forEach(p=>{p.vx+=(W/2-p.x)*.004;p.vy+=(H/2-p.y)*.004;p.x=Math.min(W-20,Math.max(20,p.x+p.vx*.5));p.y=Math.min(H-14,Math.max(14,p.y+p.vy*.5));p.vx*=.6;p.vy*=.6})}
  const svg=SVG("svg");svg.setAttribute("class","lgraph");svg.setAttribute("viewBox","0 0 "+W+" "+H);
  E.forEach(([s,t])=>{const a=at.get(s),b=at.get(t),l=SVG("line");[["x1",a.x],["y1",a.y],["x2",b.x],["y2",b.y]].forEach(([k,v])=>l.setAttribute(k,v));svg.append(l)});
  at.forEach(p=>{const c=SVG("circle");c.setAttribute("cx",p.x);c.setAttribute("cy",p.y);c.setAttribute("r",4+Math.min(6,p.n.in));
    c.setAttribute("class",p.n.state+(p.n.problems?" bad":""));const tt=SVG("title");tt.textContent=p.n.title+" ["+p.n.id+"] "+p.n.state+(p.n.problems?", has problems":"");c.append(tt);svg.append(c);
    if(nodes.length<=60){const t=SVG("text");t.setAttribute("x",p.x+8);t.setAttribute("y",p.y+3);t.textContent=p.n.title.length>48?p.n.title.slice(0,47)+"…":p.n.title;svg.append(t)}});
  return svg}
function list(title,items,fmt){const d=el("div");d.append(el("b","",title+" ("+items.length+")"));
  if(items.length){const u=el("ul");items.slice(0,8).forEach(x=>u.append(el("li","",fmt(x))));if(items.length>8)u.append(el("li","","and "+(items.length-8)+" more: library.sh doctor"));d.append(u)}
  return d}
function drawMap(p){
  const wrap=el("div","map"),cols=el("div","cols"),nodes=new Map();
  const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");svg.setAttribute("class","edges");cols.append(svg);
  p.stage_names.forEach(s=>{
    const c=el("div","col");c.append(el("h3","",s.n+". "+s.name));
    p.items.filter(i=>i.stage===s.n).forEach(i=>{const n=el("div","node "+i.state);n.title=i.what+" ("+i.state+")";
      n.append(el("b","",i.id),el("small","",i.card));nodes.set(i.id,n);c.append(n)});
    cols.append(c);
    if(s.n===p.delivery){const f=el("div","finish"+(p.delivered?" reached":""));f.append(el("span","",p.delivered?"Delivered":"Delivery"));cols.append(f)}
  });
  wrap.append(cols,el("div","legend","Outlined: can start now. Faded: waiting on a prerequisite. Dashed: not applicable. Green edge: done."));
  requestAnimationFrame(()=>{const o=cols.getBoundingClientRect();svg.setAttribute("width",cols.scrollWidth);svg.setAttribute("height",cols.scrollHeight);
    const pos=n=>{const b=n.getBoundingClientRect();return{l:b.left-o.left,r:b.right-o.left,y:b.top-o.top+b.height/2}};
    p.items.forEach(i=>i.needs.forEach(nm=>{const a=nodes.get(nm),b=nodes.get(i.id);if(!a||!b)return;const A=pos(a),B=pos(b);
      const path=document.createElementNS("http://www.w3.org/2000/svg","path");
      const d=A.r<B.l?`M${A.r},${A.y} C${A.r+16},${A.y} ${B.l-16},${B.y} ${B.l},${B.y}`:`M${A.l},${A.y} C${A.l-14},${A.y} ${B.l-14},${B.y} ${B.l},${B.y}`;
      path.setAttribute("d",d);const st=p.items.find(x=>x.id===nm);if(st&&st.state==="done")path.setAttribute("class","ok");svg.append(path)}))});
  return wrap}
async function load(){
  const r=await fetch("api?t="+encodeURIComponent(T)+"&lib="+encodeURIComponent(libName));if(!r.ok){document.getElementById("msg").textContent="Panel stopped. Start it again.";return}
  last=await r.json();render()}
function render(){
  const d=last;if(!d)return;
  document.getElementById("overall").className="dot "+d.overall;
  document.getElementById("time").textContent="Updated "+d.time;
  document.getElementById("ws").textContent=d.workspace+(d.shared?" · shared, you are "+(d.shared.member||"unnamed")+" · last sync "+d.shared.sync:"");
  document.getElementById("ws").style.color=d.shared&&d.shared.color!=="green"?"var(--"+d.shared.color+")":"";
  const P=document.getElementById("projects");
  if(!d.projects.length)empty(P,"No projects");else P.replaceChildren(...d.projects.map(p=>{
    const row=el("div","row"),body=el("div","grow");row.append(el("span","dot "+p.color),body);
    body.append(el("div","name",p.slug+(p.member?" · "+p.member:"")),el("div","",p.reason));
    if(p.target)body.append(el("div","muted","Target: "+p.target+(/^none( |$)/.test(p.check)?" · no outside check"+p.check.slice(4):p.check?" · check: "+p.check:"")+(p.runs?" · agent runs: first "+p.runs.replace(" -> ",", now "):"")));
    if(p.deadline&&!p.delivered){const m=Math.round((p.deadline*1000-Date.now())/60000);
      body.append(el("div","muted",m<0?"Deadline passed "+ago(-m)+" ago":"Deadline in "+ago(m)))}
    if(p.total){const b=el("div","bar"),i=el("i");i.style.width=(100*p.closed/p.total)+"%";b.append(i);
      const diff=p.baseline!==""?p.total-p.baseline:0,moved=p.baseline_delivery!==""&&p.baseline_delivery!==p.delivery;
      body.append(b,el("div","muted",p.closed+" of "+p.total+" deliverables closed"+(diff>0?", "+diff+" added since opening":"")+(diff<0?", "+(-diff)+" removed since opening":"")+(moved?", delivery line moved from stage "+p.baseline_delivery+" to "+p.delivery:"")+
        (p.delivered?". Original request delivered.":". "+p.brief)));
      const t=el("button","toggle",openMaps.has(p.slug)?"Hide map":"Map");
      t.onclick=()=>{openMaps.has(p.slug)?openMaps.delete(p.slug):openMaps.add(p.slug);render()};body.append(t);
      if(openMaps.has(p.slug))body.append(drawMap(p))}
    else if(p.next)body.append(el("div","muted","Next: "+p.next));
    (p.progress||[]).forEach(g=>body.append(el("div","muted","Latest on "+g.card+" ("+g.when+", "+g.who+"): "+g.what)));
    return row}));
  const C=document.getElementById("cards");
  if(!d.cards.length)empty(C,"Nothing waiting");else C.replaceChildren(...d.cards.map(c=>{
    const row=el("div","row"),b=el("div","grow");row.append(el("span","dot "+c.color),b);
    b.append(el("div","name",c.title+(c.project?" ("+c.project+")":"")+(c.member?" · "+c.member:"")));
    if(c.questions.length){const u=el("ul","q");c.questions.forEach(x=>u.append(el("li","",x)));b.append(u)}
    row.append(el("span",c.color==="red"?"":"muted","Waiting "+ago(c.waited)+(c.color==="red"?", past "+c.limit+" min":"")));return row}));
  document.getElementById("lib").textContent=d.inbox+" item(s) in the inbox, "+d.notes+" note(s) in the library.";
  const B=document.getElementById("library"),L=d.library,head=el("div","row"),hb=el("div","grow");head.append(el("span","dot "+L.color),hb);
  if(d.libs.length>1){const s=el("select");s.setAttribute("aria-label","Library");d.libs.forEach(x=>{const o=el("option","",x.name+(x.name==="personal"?"":" (team)")+", "+x.notes+" notes");o.value=x.name;if(x.name===L.name)o.selected=true;s.append(o)});
    s.onchange=()=>{libName=s.value;origin="";load()};hb.append(s);const cur=d.libs.find(x=>x.name===L.name);
    if(cur&&cur.sync!=="-"){const y=el("div","","Last sync: "+cur.sync);y.style.color=cur.sync_color==="green"?"var(--muted)":"var(--"+cur.sync_color+")";hb.append(y)}}
  if(L.state!=="online"){hb.append(el("div","name",L.state==="offline"?"Library offline":"Library error"),el("div","muted",L.message));B.replaceChildren(head)}
  else{hb.append(el("div","name",L.total+" notes"+(L.retired?", "+L.retired+" retired":"")),el("div","muted",L.path));
    const t=el("button","toggle",graphOpen?"Hide graph":"Graph");t.onclick=()=>{graphOpen=!graphOpen;render()};hb.append(t);
    if(graphOpen&&L.origins.length>1){const s=el("select");s.setAttribute("aria-label","Origin");[["","All origins"],...L.origins.map(o=>[o,o])].forEach(([v,x])=>{const o=el("option","",x);o.value=v;if(v===origin)o.selected=true;s.append(o)});
      s.onchange=()=>{origin=s.value;render()};hb.append(s)}
    const parts=[head];if(graphOpen&&L.nodes.length){parts.push(drawGraph(L));if(L.total>L.nodes.length)parts.push(el("div","empty","Showing the "+L.nodes.length+" most linked notes of "+L.total+"."))}
    const ls=el("div","lists"),title=id=>{const n=L.nodes.find(x=>x.id===id);return n?n.title+" ["+id+"]":id};
    ls.append(list("With problems",L.problems,title),list("Broken links",L.dangling,x=>title(x[0])+" → "+x[1]),
      list("Past review date",L.stale,title),list("Possible duplicates",L.pairs,x=>title(x[0])+" / "+title(x[1])));
    parts.push(ls);B.replaceChildren(...parts)}
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
