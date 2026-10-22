#!/usr/bin/env python3
"""Local panel for a chief-of-staff workspace: health per project, track progress, cards waiting on
the owner, the last turns' adherence, and an import box that drops files or links into
knowledge/inbox/. Standard library only. Listens on 127.0.0.1; every request needs the token in the URL.

Usage: python3 panel.py <workspace> [port]     (port 0 or omitted = a free port)
"""
import http.server, json, os, re, secrets, subprocess, sys, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_UPLOAD = 50 * 1024 * 1024
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


def sh(script, *args):
    try:
        r = subprocess.run(["sh", os.path.join(HERE, script), *args], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return ""
    return r.stdout


def snapshot(root):
    projects = []
    for line in sh("health.sh", root).splitlines():
        f = (line.split(US) + [""] * 11)[:11]
        slug, color, reason, stage, stages, closed, total, delivery, delivered, baseline, baseline_delivery = f
        pdir = os.path.join(root, "projects", slug)
        stage_names, items = [], []
        for row in sh("track.sh", "items", pdir).splitlines():
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
            "stage_names": stage_names, "items": items,
            "brief": sh("track.sh", "brief", pdir).strip().split(" Waiting on prerequisites:")[0],
            "next": front_matter(os.path.join(pdir, "STATE.md")).get("next", ""),
        })
    rank = {"red": 2, "yellow": 1, "green": 0}
    overall = max((p["color"] for p in projects), key=lambda c: rank.get(c, 0), default="green")

    cards = []
    board = os.path.join(root, "board")
    for name in sorted(os.listdir(board)) if os.path.isdir(board) else []:
        if name.endswith(".md"):
            fm = front_matter(os.path.join(board, name))
            if fm.get("status") == "waiting-owner":
                cards.append({"title": name[:-3], "project": fm.get("project", ""), "since": fm.get("updated", "")})

    turns = []
    try:
        with open(os.path.join(root, ".protocol.log"), encoding="utf-8", errors="replace") as f:
            lines = f.readlines()[-200:]
    except OSError:
        lines = []
    last = {}
    for line in lines:  # keep the last line of each turn (after any push)
        kv = dict(p.split("=", 1) for p in line.split() if "=" in p)
        if "turn" in kv:
            kv["when"] = line[:19]
            last[kv["turn"]] = kv
    turns = sorted(last.values(), key=lambda k: k.get("t", ""), reverse=True)[:10]

    inbox = os.path.join(root, "knowledge", "inbox")
    n_inbox = len([n for n in os.listdir(inbox) if not n.startswith(".")]) if os.path.isdir(inbox) else 0
    notes = os.path.join(root, "knowledge", "notes")
    n_notes = len([n for n in os.listdir(notes) if n.endswith(".md")]) if os.path.isdir(notes) else 0
    return {"workspace": root, "overall": overall, "projects": projects, "cards": cards,
            "turns": [{k: t.get(k, "") for k in ("when", "project", "substantive", "specialists",
                                                  "reviewers", "track", "violation")} for t in turns],
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
<h2>Last turns</h2><div id="turns" class="box"></div>
</main><script>
const T=new URLSearchParams(location.search).get("t");
const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e};
function empty(box,text){box.replaceChildren(el("div","empty",text))}
const openMaps=new Set();let last=null;
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
  const r=await fetch("api?t="+encodeURIComponent(T));if(!r.ok){document.getElementById("msg").textContent="Panel stopped. Start it again.";return}
  last=await r.json();render()}
function render(){
  const d=last;if(!d)return;
  document.getElementById("overall").className="dot "+d.overall;
  document.getElementById("time").textContent="Updated "+d.time;
  document.getElementById("ws").textContent=d.workspace;
  const P=document.getElementById("projects");
  if(!d.projects.length)empty(P,"No projects");else P.replaceChildren(...d.projects.map(p=>{
    const row=el("div","row"),body=el("div","grow");row.append(el("span","dot "+p.color),body);
    body.append(el("div","name",p.slug),el("div","",p.reason));
    if(p.total){const b=el("div","bar"),i=el("i");i.style.width=(100*p.closed/p.total)+"%";b.append(i);
      const diff=p.baseline!==""?p.total-p.baseline:0,moved=p.baseline_delivery!==""&&p.baseline_delivery!==p.delivery;
      body.append(b,el("div","muted",p.closed+" of "+p.total+" deliverables closed"+(diff>0?", "+diff+" added since opening":"")+(diff<0?", "+(-diff)+" removed since opening":"")+(moved?", delivery line moved from stage "+p.baseline_delivery+" to "+p.delivery:"")+
        (p.delivered?". Original request delivered.":". "+p.brief)));
      const t=el("button","toggle",openMaps.has(p.slug)?"Hide map":"Map");
      t.onclick=()=>{openMaps.has(p.slug)?openMaps.delete(p.slug):openMaps.add(p.slug);render()};body.append(t);
      if(openMaps.has(p.slug))body.append(drawMap(p))}
    else if(p.next)body.append(el("div","muted","Next: "+p.next));
    return row}));
  const C=document.getElementById("cards");
  if(!d.cards.length)empty(C,"Nothing waiting");else C.replaceChildren(...d.cards.map(c=>{
    const row=el("div","row");row.append(el("span","dot yellow"),el("div","grow",c.title+(c.project?" ("+c.project+")":"")),el("span","muted",c.since));return row}));
  document.getElementById("lib").textContent=d.inbox+" item(s) in the inbox, "+d.notes+" note(s) in the library.";
  const U=document.getElementById("turns");
  if(!d.turns.length)empty(U,"No turns yet");else{
    const t=el("table"),h=el("tr");["When","Project","Specialists","Reviewers","Track gaps",""].forEach(x=>h.append(el("th","",x)));t.append(h);
    d.turns.forEach(x=>{const r=el("tr");const bad=x.violation==="1";
      [x.when,x.project,x.specialists,x.reviewers,x.track].forEach(v=>r.append(el("td","",v)));
      const s=el("td");s.append(el("span","dot "+(bad?"red":(x.substantive==="1"?"green":"yellow"))));r.append(s);t.append(r)});
    U.replaceChildren(t)}
}
async function send(body,name,kind){
  const m=document.getElementById("msg");m.textContent="Saving…";
  const r=await fetch("import?t="+encodeURIComponent(T),{method:"POST",body,headers:{"X-Name":encodeURIComponent(name),"X-Kind":kind}});
  m.textContent=r.ok?"Saved to the inbox. Ask central to process it.":await r.text();load()}
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

    def reply(self, ctype, body):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")  # the token is in the URL: never send it on
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.allowed():
            return
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            self.reply("text/html; charset=utf-8", PAGE.encode())
        elif path == "/api":
            self.reply("application/json", json.dumps(snapshot(self.root)).encode())
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
        inbox = os.path.join(self.root, "knowledge", "inbox")
        os.makedirs(inbox, exist_ok=True)
        try:
            with open(os.path.join(inbox, name), "xb") as f:
                f.write(data)
        except FileExistsError:
            return self.deny(409, "A file with that name arrived the same second. Send it again.")
        self.reply("text/plain; charset=utf-8", b"saved")


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
