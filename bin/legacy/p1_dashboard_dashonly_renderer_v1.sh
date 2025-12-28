#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_dash_only_v1.js"
CSS="static/css/vsp_dash_only_v1.css"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_dashonly_${TS}"
echo "[BACKUP] ${TPL}.bak_dashonly_${TS}"

mkdir -p "$(dirname "$JS")" "$(dirname "$CSS")"

cat > "$CSS" <<'CSS'
/* VSP_DASH_ONLY_V1 (Dashboard-only, contract: rid_latest_gate_root + run_gate_summary) */
:root{
  --bg:#070e1a;
  --panel:rgba(255,255,255,.04);
  --panel2:rgba(255,255,255,.06);
  --border:rgba(255,255,255,.08);
  --text:#d6e2ff;
  --muted:rgba(214,226,255,.62);
  --accent:#7c5cff;
  --good:#35d07f;
  --warn:#ffcc66;
  --bad:#ff5c7c;
  --chip:#0c1628;
  --shadow:0 10px 30px rgba(0,0,0,.35);
}

html,body{background:var(--bg); color:var(--text); margin:0; font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;}
a{color:inherit; text-decoration:none}
.vsp-wrap{max-width:1280px; margin:0 auto; padding:18px 18px 40px;}
.vsp-top{
  display:flex; align-items:center; justify-content:space-between;
  gap:12px; padding:14px 16px; border:1px solid var(--border); border-radius:14px;
  background:linear-gradient(180deg, rgba(124,92,255,.10), rgba(255,255,255,.02));
  box-shadow:var(--shadow);
}
.vsp-title{display:flex; flex-direction:column; gap:4px}
.vsp-title .h{font-size:16px; font-weight:700; letter-spacing:.2px}
.vsp-title .s{font-size:12px; color:var(--muted)}
.vsp-actions{display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end}
.btn{
  border:1px solid var(--border); background:var(--panel); color:var(--text);
  padding:8px 10px; border-radius:10px; font-size:12px; cursor:pointer;
}
.btn:hover{background:var(--panel2)}
.badge{display:inline-flex; align-items:center; gap:8px; font-size:12px; padding:6px 10px; border-radius:999px; background:var(--chip); border:1px solid var(--border)}
.dot{width:8px; height:8px; border-radius:99px; background:var(--muted)}
.dot.good{background:var(--good)} .dot.warn{background:var(--warn)} .dot.bad{background:var(--bad)}

.grid{display:grid; grid-template-columns: 1.2fr .8fr; gap:12px; margin-top:12px;}
@media (max-width: 1040px){ .grid{grid-template-columns:1fr;} }

.card{
  border:1px solid var(--border); border-radius:14px; background:var(--panel);
  box-shadow:var(--shadow); padding:14px 14px;
}
.card .t{display:flex; align-items:center; justify-content:space-between; margin-bottom:10px}
.card .t .h{font-size:13px; font-weight:700}
.card .t .s{font-size:12px; color:var(--muted)}

.kpis{display:grid; grid-template-columns:repeat(4,1fr); gap:10px;}
@media (max-width: 1040px){ .kpis{grid-template-columns:repeat(2,1fr);} }
.kpi{border:1px solid var(--border); background:rgba(0,0,0,.12); border-radius:14px; padding:12px}
.kpi .n{font-size:22px; font-weight:800; letter-spacing:.2px}
.kpi .l{font-size:12px; color:var(--muted); margin-top:4px}
.kpi .tag{margin-top:10px; display:flex; gap:6px; flex-wrap:wrap}
.chip{font-size:11px; padding:4px 8px; border-radius:999px; border:1px solid var(--border); background:var(--chip); color:var(--muted)}

.tools{display:grid; grid-template-columns:repeat(4,1fr); gap:10px;}
@media (max-width: 1040px){ .tools{grid-template-columns:repeat(2,1fr);} }
.tool{border:1px solid var(--border); background:rgba(0,0,0,.10); border-radius:14px; padding:10px}
.tool .name{font-size:12px; font-weight:700}
.tool .meta{margin-top:6px; display:flex; align-items:center; justify-content:space-between; font-size:11px; color:var(--muted)}
.tool .state{display:inline-flex; align-items:center; gap:6px}
.sep{height:1px; background:var(--border); margin:10px 0}
.small{font-size:12px; color:var(--muted)}
pre{white-space:pre-wrap; word-break:break-word; margin:0; font-size:12px; color:var(--muted)}
CSS

cat > "$JS" <<'JS'
/* VSP_DASH_ONLY_V1
   Contract: /api/vsp/rid_latest_gate_root + run_gate_summary.json only.
*/
(()=> {
  if (window.__vsp_dash_only_v1) return;
  window.__vsp_dash_only_v1 = true;

  const $ = (sel, root=document) => root.querySelector(sel);
  const esc = (s)=> String(s ?? "").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const api = (p)=> p;

  function sevDot(overall){
    const o = String(overall||"").toUpperCase();
    if (o.includes("PASS") || o.includes("GREEN")) return "good";
    if (o.includes("AMBER") || o.includes("WARN")) return "warn";
    if (o.includes("FAIL") || o.includes("RED")) return "bad";
    return "";
  }

  function pickCounts(summary){
    // prefer summary.counts_total (commercial contract)
    const ct = summary && (summary.counts_total || summary.counts || (summary.meta && summary.meta.counts_by_severity));
    const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,TOTAL:0};
    if (ct && typeof ct === "object"){
      for (const k of Object.keys(out)){
        if (k==="TOTAL") continue;
        const v = ct[k] ?? ct[k.toLowerCase()] ?? 0;
        out[k] = Number(v)||0;
      }
      // total
      const t = ct.TOTAL ?? ct.total;
      out.TOTAL = Number(t)|| (out.CRITICAL+out.HIGH+out.MEDIUM+out.LOW+out.INFO+out.TRACE);
    }
    return out;
  }

  function normalizeTools(summary){
    const bt = summary && summary.by_tool;
    const tools = [];
    if (bt && typeof bt === "object"){
      for (const [name, obj] of Object.entries(bt)){
        const st = (obj && (obj.status || obj.state || obj.result)) || "UNKNOWN";
        const degraded = !!(obj && (obj.degraded || obj.is_degraded));
        const missing = !!(obj && (obj.missing || obj.is_missing));
        tools.push({name, st: String(st), degraded, missing});
      }
    }
    // stable ordering
    const order = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
    tools.sort((a,b)=> (order.indexOf(a.name)-order.indexOf(b.name)) || a.name.localeCompare(b.name));
    return tools;
  }

  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }

  async function loadOnce(){
    const top = $("#vspTopStatus");
    const ridEl = $("#vspRid");
    const updEl = $("#vspUpdated");
    const rawEl = $("#vspRaw");

    top.innerHTML = `<span class="badge"><span class="dot"></span>Loading…</span>`;
    rawEl.textContent = "";

    const latest = await jget(api("/api/vsp/rid_latest_gate_root"));
    const rid = latest.rid || latest.run_id || "";
    ridEl.textContent = rid || "(none)";

    const sum = await jget(api(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`));

    const overall = String(sum.overall_status || sum.overall || (sum.gate && sum.gate.overall) || "UNKNOWN");
    const dot = sevDot(overall);
    top.innerHTML = `<span class="badge"><span class="dot ${dot}"></span><b>${esc(overall)}</b>&nbsp;<span style="opacity:.65">•</span>&nbsp;<span class="small">RID</span>&nbsp;<span>${esc(rid)}</span></span>`;

    const counts = pickCounts(sum);
    const tools = normalizeTools(sum);

    $("#kTotal").textContent = counts.TOTAL;
    $("#kCritical").textContent = counts.CRITICAL;
    $("#kHigh").textContent = counts.HIGH;
    $("#kMedium").textContent = counts.MEDIUM;
    $("#kLow").textContent = counts.LOW;
    $("#kInfo").textContent = counts.INFO;
    $("#kTrace").textContent = counts.TRACE;

    // evidence quick (from your contract checks)
    const ev = [];
    const want = ["run_gate_summary.json","run_gate.json","findings_unified.json","reports/findings_unified.csv"];
    for (const p of want){
      ev.push({p, ok:true}); // just show links; backend already allowlisted
    }
    $("#evLinks").innerHTML = ev.map(x=>{
      const href = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(x.p)}`;
      return `<a class="chip" href="${href}" target="_blank" rel="noreferrer">${esc(x.p)}</a>`;
    }).join("");

    // tool lanes
    const lanes = $("#toolLanes");
    lanes.innerHTML = tools.map(t=>{
      const name = esc(t.name);
      const st = esc(t.st);
      let dotc = "";
      const up = t.st.toUpperCase();
      if (t.missing) dotc="warn";
      else if (t.degraded) dotc="warn";
      else if (up.includes("OK")||up.includes("PASS")) dotc="good";
      else if (up.includes("FAIL")||up.includes("ERR")) dotc="bad";
      return `
        <div class="tool">
          <div class="name">${name}</div>
          <div class="meta">
            <span class="state"><span class="dot ${dotc}"></span>${st}</span>
            <span>${t.degraded ? "degraded" : (t.missing ? "missing" : "ok")}</span>
          </div>
        </div>`;
    }).join("");

    // updated
    const now = new Date();
    updEl.textContent = now.toLocaleString();

    // raw (debug toggle)
    rawEl.textContent = JSON.stringify({rid, overall, counts, tools: tools.map(t=>({name:t.name, st:t.st, degraded:t.degraded, missing:t.missing}))}, null, 2);

    // buttons
    $("#btnGateJson").onclick = ()=> window.open(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`, "_blank");
    $("#btnSummaryJson").onclick = ()=> window.open(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`, "_blank");
  }

  async function boot(){
    try{
      await loadOnce();
    }catch(e){
      $("#vspTopStatus").innerHTML = `<span class="badge"><span class="dot bad"></span><b>ERROR</b>&nbsp;<span class="small">${esc(e.message||e)}</span></span>`;
      $("#vspRaw").textContent = String(e && (e.stack||e.message)||e);
    }
  }

  window.__vsp_dash_only_reload = boot;
  document.addEventListener("DOMContentLoaded", ()=>{
    console.info("[VSP][DASH_ONLY_V1] boot");
    boot();
    // polling gentle
    setInterval(()=>boot().catch(()=>{}), 30000);
  });
})();
JS

python3 - <<PY
from pathlib import Path
import re

tpl = Path("${TPL}")
s = tpl.read_text(encoding="utf-8", errors="replace")

# HARD STOP: remove legacy heavy bundle/scripts on /vsp5
# Keep base css link(s) but remove any script src containing vsp_bundle_commercial_v2.js or legacy dash scripts.
patterns = [
  r'<script[^>]+src="[^"]*vsp_bundle_commercial_v2\.js[^"]*"[^>]*>\s*</script>',
  r'<script[^>]+src="[^"]*vsp_dashboard_.*\.js[^"]*"[^>]*>\s*</script>',
  r'<script[^>]+src="[^"]*vsp_rid_autofix_v1\.js[^"]*"[^>]*>\s*</script>',
  r'<script[^>]+src="[^"]*vsp_p0_fetch_shim_v1\.js[^"]*"[^>]*>\s*</script>',
]
for pat in patterns:
  s = re.sub(pat, "", s, flags=re.I)

# Inject dash-only css + js before </head> / </body>
ts = "${TS}"
dash_css = f'<link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css?v={ts}"/>'
dash_js  = f'<script defer src="/static/js/vsp_dash_only_v1.js?v={ts}"></script>'

if "vsp_dash_only_v1.css" not in s:
  s = re.sub(r"(</head>)", dash_css + "\n\\1", s, flags=re.I)
else:
  s = re.sub(r"/static/css/vsp_dash_only_v1\.css(?:\?v=[^\"']+)?", f"/static/css/vsp_dash_only_v1.css?v={ts}", s)

if "vsp_dash_only_v1.js" not in s:
  s = re.sub(r"(</body>)", dash_js + "\n\\1", s, flags=re.I)
else:
  s = re.sub(r"/static/js/vsp_dash_only_v1\.js(?:\?v=[^\"']+)?", f"/static/js/vsp_dash_only_v1.js?v={ts}", s)

# Replace body content with a clean Dash-only root (avoid weird leftover markup)
root_html = r"""
<div class="vsp-wrap">
  <div class="vsp-top">
    <div class="vsp-title">
      <div class="h">VSP • Dashboard</div>
      <div class="s">Contract: rid_latest_gate_root + run_gate_summary.json • Updated: <span id="vspUpdated">—</span></div>
    </div>
    <div class="vsp-actions">
      <span id="vspTopStatus" class="badge"><span class="dot"></span>—</span>
      <span class="badge"><span class="dot"></span>RID: <span id="vspRid">—</span></span>
      <button class="btn" onclick="window.__vsp_dash_only_reload && window.__vsp_dash_only_reload()">Refresh</button>
      <button class="btn" id="btnSummaryJson">Summary JSON</button>
      <button class="btn" id="btnGateJson">Gate JSON</button>
    </div>
  </div>

  <div class="grid">
    <div class="card">
      <div class="t">
        <div class="h">KPIs</div>
        <div class="s">Counts from summary (no findings_unified auto-load)</div>
      </div>
      <div class="kpis">
        <div class="kpi"><div class="n" id="kTotal">—</div><div class="l">TOTAL</div><div class="tag"><span class="chip">All severities</span></div></div>
        <div class="kpi"><div class="n" id="kCritical">—</div><div class="l">CRITICAL</div><div class="tag"><span class="chip">Fix-first</span></div></div>
        <div class="kpi"><div class="n" id="kHigh">—</div><div class="l">HIGH</div><div class="tag"><span class="chip">Sprint priority</span></div></div>
        <div class="kpi"><div class="n" id="kMedium">—</div><div class="l">MEDIUM</div><div class="tag"><span class="chip">Backlog</span></div></div>
        <div class="kpi"><div class="n" id="kLow">—</div><div class="l">LOW</div><div class="tag"><span class="chip">Hygiene</span></div></div>
        <div class="kpi"><div class="n" id="kInfo">—</div><div class="l">INFO</div><div class="tag"><span class="chip">Signals</span></div></div>
        <div class="kpi"><div class="n" id="kTrace">—</div><div class="l">TRACE</div><div class="tag"><span class="chip">Noise</span></div></div>
      </div>
      <div class="sep"></div>
      <div class="small">Evidence quick-links</div>
      <div id="evLinks" style="margin-top:8px; display:flex; flex-wrap:wrap; gap:8px"></div>
    </div>

    <div class="card">
      <div class="t">
        <div class="h">Tool lanes</div>
        <div class="s">Status from summary.by_tool</div>
      </div>
      <div class="tools" id="toolLanes"></div>
      <div class="sep"></div>
      <div class="small">Debug snapshot</div>
      <pre id="vspRaw" style="margin-top:8px"></pre>
    </div>
  </div>
</div>
"""
# Replace <body ...> ... </body> with our root + keep closing tags
s = re.sub(r"(?is)<body[^>]*>.*?</body>", "<body>\n"+root_html+"\n</body>", s)

tpl.write_text(s, encoding="utf-8")
print("[OK] /vsp5 is now Dash-Only renderer (bundle removed)")
PY

echo "[OK] wrote $CSS"
echo "[OK] wrote $JS"
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect NO more jumping."
