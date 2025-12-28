#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

JS="static/js/vsp_dash_only_v1.js"
CSS="static/css/vsp_dash_only_v1.css"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_dashonly_isolate_${TS}"
echo "[BACKUP] ${WSGI}.bak_dashonly_isolate_${TS}"

mkdir -p static/js static/css

cat > "$CSS" <<'CSS'
/* VSP_DASH_ONLY_V1 */
:root{
  --bg:#0b1220;
  --card: rgba(255,255,255,.04);
  --bd: rgba(255,255,255,.10);
  --txt: rgba(226,232,240,.92);
  --muted: rgba(148,163,184,.88);
  --good: rgba(34,197,94,.9);
  --warn: rgba(245,158,11,.95);
  --bad:  rgba(239,68,68,.92);
  --accent: rgba(56,189,248,.9);
  --r: 16px;
}
html,body{margin:0;background:var(--bg);color:var(--txt);font-family: ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial}
a{color:var(--txt);text-decoration:none}
.topnav{display:flex;gap:10px;padding:10px 14px;border-bottom:1px solid var(--bd);background:rgba(0,0,0,.22);position:sticky;top:0;z-index:9999}
.topnav a{font-size:12px;padding:8px 10px;border:1px solid rgba(255,255,255,.14);border-radius:999px}
.topnav a:hover{background:rgba(255,255,255,.06)}
.wrap{max-width:1200px;margin:16px auto;padding:0 14px}
.row{display:flex;gap:12px;flex-wrap:wrap}
.card{background:var(--card);border:1px solid var(--bd);border-radius:var(--r);padding:12px;box-shadow:0 10px 30px rgba(0,0,0,.25)}
.kpi{min-width:180px;flex:1}
.kpi .v{font-size:22px;font-weight:700}
.kpi .l{font-size:12px;color:var(--muted)}
.pill{display:inline-flex;align-items:center;gap:8px;padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);font-size:12px}
.btn{cursor:pointer;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.14);color:var(--txt);border-radius:999px;padding:8px 10px;font-size:12px}
.btn:hover{background:rgba(255,255,255,.10)}
.small{font-size:12px;color:var(--muted)}
.grid{display:grid;grid-template-columns: repeat(4,minmax(0,1fr));gap:10px}
@media(max-width:900px){ .grid{grid-template-columns: repeat(2,minmax(0,1fr));} }
.tool{padding:10px;border-radius:14px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.18)}
.tool .t{font-size:12px;color:var(--muted)}
.tool .s{font-size:12px;font-weight:700}
.s-ok{color:var(--good)} .s-miss{color:var(--warn)} .s-bad{color:var(--bad)}
pre{white-space:pre-wrap;word-break:break-word;background:rgba(0,0,0,.25);border:1px solid rgba(255,255,255,.10);border-radius:14px;padding:10px;color:rgba(226,232,240,.92)}
table{width:100%;border-collapse:collapse}
td,th{border-bottom:1px solid rgba(255,255,255,.08);padding:8px 6px;font-size:12px;text-align:left}
th{color:var(--muted);font-weight:600}
CSS
echo "[OK] wrote $CSS"

cat > "$JS" <<'JS'
/* VSP_DASH_ONLY_V1 */
(()=> {
  if (window.__vsp_dash_only_v1) return;
  window.__vsp_dash_only_v1 = true;

  const $ = (q,el=document)=>el.querySelector(q);
  const esc = (s)=> String(s??"").replace(/[&<>"']/g, m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m]));
  const sevRank = (s)=> ({CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5}[String(s||"").toUpperCase()] ?? 99);

  const state = {
    rid: null,
    gate: null,
    counts: null,
    tools: null,
    findings: null,
  };

  function log(...a){ console.log("[DASH_ONLY]", ...a); }

  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    if(!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }

  function getRidFromQS(){
    const u = new URL(location.href);
    return u.searchParams.get("rid");
  }

  async function resolveRid(){
    const qs = getRidFromQS();
    if (qs) return qs;

    const pin = localStorage.getItem("vsp.rid.pin");
    if (pin) return pin;

    try{
      const j = await jget("/api/vsp/rid_latest_gate_root");
      if (j && j.ok && j.rid) return j.rid;
    }catch(e){
      log("rid_latest_gate_root failed", e?.message || e);
    }
    return null;
  }

  function setStatusBadge(overall){
    const el = $("#overall_badge");
    if(!el) return;
    const o = String(overall||"UNKNOWN").toUpperCase();
    el.textContent = o;
    el.style.borderColor = "rgba(255,255,255,.14)";
    if (o === "PASS" || o === "GREEN") el.style.color = "rgba(34,197,94,.95)";
    else if (o === "STALE" || o === "AMBER" || o === "WARN") el.style.color = "rgba(245,158,11,.98)";
    else if (o === "FAIL" || o === "RED") el.style.color = "rgba(239,68,68,.95)";
    else el.style.color = "rgba(226,232,240,.92)";
  }

  function render(){
    $("#rid_txt").textContent = state.rid || "(no rid)";
    setStatusBadge(state.gate?.overall_status || state.gate?.overall || state.gate?.overall_v2);

    const c = state.counts || {};
    const setK = (id,val)=> { const el=$(id); if(el) el.textContent = (val==null? "—": String(val)); };

    setK("#k_total", c.TOTAL ?? c.total ?? state.gate?.counts_total?.TOTAL);
    setK("#k_crit",  c.CRITICAL ?? c.critical);
    setK("#k_high",  c.HIGH ?? c.high);
    setK("#k_med",   c.MEDIUM ?? c.medium);
    setK("#k_low",   c.LOW ?? c.low);
    setK("#k_info",  c.INFO ?? c.info);
    setK("#k_trace", c.TRACE ?? c.trace);

    const toolsBox = $("#tools_box");
    if (toolsBox){
      const tools = state.tools || {};
      const order = ["Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","Bandit","CodeQL"];
      toolsBox.innerHTML = order.map(t=>{
        const st = String(tools[t]?.status || tools[t] || "UNKNOWN").toUpperCase();
        const cls = (st==="OK") ? "s-ok" : (st==="MISSING" || st==="DEGRADED") ? "s-miss" : (st==="FAIL" || st==="ERROR") ? "s-bad" : "";
        return `<div class="tool"><div class="t">${esc(t)}</div><div class="s ${cls}">${esc(st)}</div></div>`;
      }).join("");
    }

    const note = $("#note_box");
    if(note){
      const arr = [];
      arr.push(`Source: run_gate_summary.json (tool truth)`);
      arr.push(`No legacy /api/vsp/runs auto-refresh (dash-only).`);
      note.textContent = arr.join("\n");
    }
  }

  async function loadGate(){
    const rid = state.rid;
    if(!rid) throw new Error("No RID resolved");
    const gate = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
    // allow both shapes: {ok:true,...} or raw json
    state.gate = gate?.ok === false ? null : (gate?.ok === true && gate.data ? gate.data : gate);
    // heuristics for counts/tools
    const meta = state.gate?.meta || state.gate || {};
    state.counts = meta.counts_by_severity || meta.counts_total || meta.counts || meta.meta?.counts_by_severity || meta.meta?.counts_total || null;
    state.tools = meta.by_tool || meta.tools || meta.byTool || null;
    render();
  }

  async function loadTopFindings(){
    const rid = state.rid;
    if(!rid) return;
    const out = $("#findings_tbl");
    const btn = $("#btn_load_findings");
    if(btn) btn.disabled = true;

    try{
      const fu = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`);
      const payload = fu?.ok === true && fu.findings ? fu : (fu?.ok === true && fu.data ? fu.data : fu);
      const findings = payload.findings || payload?.data?.findings || [];
      const rows = findings
        .map(f=>({
          sev: String(f.severity||"").toUpperCase(),
          tool: f.tool || f.source || "",
          title: f.title || f.rule_id || f.message || "",
          loc: f.location || f.path || (f.file? `${f.file}:${f.line||""}`:""),
        }))
        .sort((a,b)=> sevRank(a.sev)-sevRank(b.sev))
        .slice(0, 25);

      out.innerHTML = rows.map(r=>(
        `<tr><td>${esc(r.sev)}</td><td>${esc(r.tool)}</td><td>${esc(r.title)}</td><td>${esc(r.loc)}</td></tr>`
      )).join("");
      log("loaded top findings", rows.length);
    }catch(e){
      log("load findings failed", e?.message||e);
      out.innerHTML = `<tr><td colspan="4">Failed to load findings_unified.json</td></tr>`;
    }finally{
      if(btn) btn.disabled = false;
    }
  }

  async function boot(){
    log("boot");
    state.rid = await resolveRid();
    if(!state.rid){
      $("#rid_txt").textContent = "(no rid)";
      $("#note_box").textContent = "Cannot resolve RID. (Hint: set VSP_RUNS_ROOT in service env, or open /vsp5?rid=RUN_...)";
      return;
    }
    await loadGate();
  }

  window.__vspDashOnly = {
    pinRid(){
      if(state.rid) localStorage.setItem("vsp.rid.pin", state.rid);
      alert("Pinned RID: " + (state.rid||""));
    },
    clearPin(){
      localStorage.removeItem("vsp.rid.pin");
      alert("Cleared pinned RID");
    },
    refresh(){ return boot(); },
    loadTopFindings(){ return loadTopFindings(); },
  };

  document.addEventListener("click", (e)=>{
    const t = e.target;
    if(!(t instanceof HTMLElement)) return;
    const id = t.id;
    if(id==="btn_refresh") boot();
    if(id==="btn_pin") window.__vspDashOnly.pinRid();
    if(id==="btn_unpin") window.__vspDashOnly.clearPin();
    if(id==="btn_load_findings") loadTopFindings();
  });

  boot();
})();
JS
echo "[OK] wrote $JS"

python3 - <<'PY'
from pathlib import Path
import textwrap

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_VSP5_ISOLATE_DASH_ONLY_V1"
if marker in s:
    print("[OK] marker already present, skip patch")
    raise SystemExit(0)

patch = textwrap.dedent(r'''
# ===================== VSP_P0_VSP5_ISOLATE_DASH_ONLY_V1 =====================
def _vsp_p0_dashonly_isolate_v1(_app):
    if getattr(_app, "_vsp_p0_dashonly_isolate_v1", False):
        return _app
    from urllib.parse import parse_qs
    from pathlib import Path
    import os, json, time

    def _resp(start_response, status, ctype, body_bytes, extra_headers=None):
        hs = [
            ("Content-Type", ctype),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(body_bytes))),
        ]
        if extra_headers:
            hs.extend(list(extra_headers))
        start_response(status, hs)
        return [body_bytes]

    def _json(start_response, obj, status="200 OK"):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        return _resp(start_response, status, "application/json; charset=utf-8", body)

    def _guess_roots():
        env = os.environ.get("VSP_RUNS_ROOT","").strip()
        roots = [r for r in env.split(":") if r] if env else []
        # safe fallbacks commonly used in your repo
        roots += [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]
        # unique + exists
        out = []
        for r in roots:
            p = Path(r)
            if p.exists() and str(p) not in out:
                out.append(str(p))
        return out

    def _list_runs(limit=30, offset=0):
        roots = _guess_roots()
        cands = []
        for r in roots:
            rp = Path(r)
            try:
                for d in rp.iterdir():
                    if not d.is_dir():
                        continue
                    name = d.name
                    if not (name.startswith("RUN_") or name.startswith("VSP_") or "RUN" in name):
                        continue
                    f1 = d/"run_gate_summary.json"
                    f2 = d/"run_gate.json"
                    if f1.is_file():
                        mt = f1.stat().st_mtime
                    elif f2.is_file():
                        mt = f2.stat().st_mtime
                    else:
                        continue
                    cands.append((mt, name))
            except Exception:
                continue
        cands.sort(key=lambda x: x[0], reverse=True)
        total = len(cands)
        sl = cands[offset:offset+limit]
        runs = [{"rid": rid, "mtime": int(mt)} for (mt, rid) in sl]
        return total, runs, roots

    def _latest_rid():
        total, runs, roots = _list_runs(limit=1, offset=0)
        if runs:
            rid = runs[0]["rid"]
            return rid, f"gate_root_{rid}", roots
        return None, None, roots

    def _html_vsp5():
        v = str(int(time.time()))
        html = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
<meta http-equiv="Pragma" content="no-cache"/><meta http-equiv="Expires" content="0"/>
<title>VSP5</title>
<link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css?v={v}"/>
</head><body>
<div class="topnav">
  <a href="/vsp5">Dashboard</a>
  <a href="/runs">Runs &amp; Reports</a>
  <a href="/data_source">Data Source</a>
  <a href="/settings">Settings</a>
  <a href="/rule_overrides">Rule Overrides</a>
</div>

<div class="wrap">
  <div class="row">
    <div class="card pill">RID: <b id="rid_txt">—</b></div>
    <div class="card pill">Overall: <b id="overall_badge">—</b></div>
    <button class="btn" id="btn_refresh">Refresh</button>
    <button class="btn" id="btn_pin">Pin RID</button>
    <button class="btn" id="btn_unpin">Unpin</button>
  </div>

  <div style="height:10px"></div>
  <div class="row">
    <div class="card kpi"><div class="v" id="k_total">—</div><div class="l">TOTAL</div></div>
    <div class="card kpi"><div class="v" id="k_crit">—</div><div class="l">CRITICAL</div></div>
    <div class="card kpi"><div class="v" id="k_high">—</div><div class="l">HIGH</div></div>
    <div class="card kpi"><div class="v" id="k_med">—</div><div class="l">MEDIUM</div></div>
    <div class="card kpi"><div class="v" id="k_low">—</div><div class="l">LOW</div></div>
    <div class="card kpi"><div class="v" id="k_info">—</div><div class="l">INFO</div></div>
    <div class="card kpi"><div class="v" id="k_trace">—</div><div class="l">TRACE</div></div>
  </div>

  <div style="height:10px"></div>
  <div class="card">
    <div style="display:flex;justify-content:space-between;gap:10px;align-items:center">
      <div>
        <div style="font-weight:700">Tool lane (8 tools)</div>
        <div class="small">Derived from run_gate_summary.json</div>
      </div>
      <button class="btn" id="btn_load_findings">Load top findings (25)</button>
    </div>
    <div style="height:10px"></div>
    <div class="grid" id="tools_box"></div>
  </div>

  <div style="height:10px"></div>
  <div class="card">
    <div style="font-weight:700">Notes</div>
    <div style="height:8px"></div>
    <pre id="note_box">Loading...</pre>
  </div>

  <div style="height:10px"></div>
  <div class="card">
    <div style="font-weight:700">Top findings (sample)</div>
    <div class="small">Only loads when you click the button (avoid heavy fetch by default)</div>
    <div style="height:8px"></div>
    <table>
      <thead><tr><th>Severity</th><th>Tool</th><th>Title</th><th>Location</th></tr></thead>
      <tbody id="findings_tbl"><tr><td colspan="4">Not loaded</td></tr></tbody>
    </table>
  </div>
</div>

<script src="/static/js/vsp_p0_fetch_shim_v1.js?v={v}"></script>
<script src="/static/js/vsp_dash_only_v1.js?v={v}"></script>
</body></html>"""
        return html.encode("utf-8")

    def app(environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path == "/vsp5":
            body = _html_vsp5()
            return _resp(start_response, "200 OK", "text/html; charset=utf-8", body, extra_headers=[
                ("Cache-Control","no-cache, no-store, must-revalidate"),
                ("Pragma","no-cache"),
                ("Expires","0"),
            ])

        if path == "/api/vsp/rid_latest_gate_root":
            rid, gate_root, roots = _latest_rid()
            if rid:
                return _json(start_response, {"ok": True, "rid": rid, "gate_root": gate_root, "roots": roots, "ts": int(time.time())})
            return _json(start_response, {"ok": False, "err": "no runs found", "roots": roots, "ts": int(time.time())}, status="404 Not Found")

        if path == "/api/vsp/runs":
            qs = parse_qs(environ.get("QUERY_STRING","") or "")
            try: limit = int((qs.get("limit") or ["30"])[0])
            except Exception: limit = 30
            try: offset = int((qs.get("offset") or ["0"])[0])
            except Exception: offset = 0
            limit = max(1, min(limit, 200))
            offset = max(0, offset)
            total, runs, roots = _list_runs(limit=limit, offset=offset)
            return _json(start_response, {"ok": True, "total": total, "limit": limit, "offset": offset, "runs": runs, "roots": roots, "ts": int(time.time())})

        return _app(environ, start_response)

    app._vsp_p0_dashonly_isolate_v1 = True
    return app

try:
    application = _vsp_p0_dashonly_isolate_v1(application)
except Exception:
    pass
# ===================== /VSP_P0_VSP5_ISOLATE_DASH_ONLY_V1 =====================
''')

w.write_text(s + "\n" + patch, encoding="utf-8")
print("[OK] appended patch block:", marker)
PY

echo "== compile check wsgi =="
python3 -m py_compile "$WSGI"

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== wait /vsp5 ready =="
for i in $(seq 1 40); do
  curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== verify /vsp5 uses dash_only js (NOT bundle) =="
curl -fsS "$BASE/vsp5" | grep -nE "vsp_dash_only_v1|vsp_bundle_commercial_v2" || true

echo "== verify latest rid endpoint =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo

echo "[DONE] Open /vsp5 and Hard refresh (Ctrl+Shift+R)."
