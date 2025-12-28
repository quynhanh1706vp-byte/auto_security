#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
VER="$(date +%s)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PYF="vsp_demo_app.py"

[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

echo "[INFO] TS=$TS VER=$VER"

# (1) Write dash-only assets (overwrite OK)
CSS="static/css/vsp_dash_only_v1.css"
JS="static/js/vsp_dash_only_v1.js"
mkdir -p "$(dirname "$CSS")" "$(dirname "$JS")"

cat > "$CSS" <<'CSS'
/* VSP_DASH_ONLY_V1 (Dashboard-only cosmetics) */
:root{
  --bg:#070e1a;
  --panel:rgba(255,255,255,.04);
  --panel2:rgba(255,255,255,.06);
  --border:rgba(255,255,255,.10);
  --text:rgba(226,232,240,.96);
  --muted:rgba(226,232,240,.65);
  --good:#35d07f; --warn:#ffcc66; --bad:#ff5c7c;
  --shadow:0 12px 36px rgba(0,0,0,.38);
}
html,body{background:var(--bg); margin:0; color:var(--text);
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;}
a{color:inherit; text-decoration:none}
.vsp-wrap{max-width:1280px; margin:0 auto; padding:16px 18px 44px;}
.top{
  display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap;
  padding:14px; border:1px solid var(--border); border-radius:16px;
  background:linear-gradient(180deg, rgba(124,92,255,.10), rgba(255,255,255,.02));
  box-shadow:var(--shadow);
}
.title{display:flex; flex-direction:column; gap:4px}
.title .h{font-weight:900; letter-spacing:.2px; font-size:15px}
.title .s{font-size:12px; color:var(--muted)}
.actions{display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end}
.btn{border:1px solid var(--border); background:var(--panel); color:var(--text);
  padding:8px 10px; border-radius:12px; font-size:12px; cursor:pointer;}
.btn:hover{background:var(--panel2)}
.badge{display:inline-flex; align-items:center; gap:8px;
  font-size:12px; padding:7px 10px; border-radius:999px;
  background:rgba(0,0,0,.20); border:1px solid var(--border);}
.dot{width:8px;height:8px;border-radius:99px;background:rgba(226,232,240,.35)}
.dot.good{background:var(--good)} .dot.warn{background:var(--warn)} .dot.bad{background:var(--bad)}
.grid{display:grid; grid-template-columns:1.15fr .85fr; gap:12px; margin-top:12px;}
@media (max-width:1040px){.grid{grid-template-columns:1fr;}}
.card{border:1px solid var(--border); border-radius:16px; background:var(--panel);
  box-shadow:var(--shadow); padding:14px;}
.card .t{display:flex; align-items:center; justify-content:space-between; margin-bottom:10px}
.card .t .h{font-size:13px; font-weight:900}
.card .t .s{font-size:12px; color:var(--muted)}
.kpis{display:grid; grid-template-columns:repeat(4,1fr); gap:10px;}
@media (max-width:1040px){.kpis{grid-template-columns:repeat(2,1fr);}}
.kpi{border:1px solid var(--border); background:rgba(0,0,0,.12); border-radius:16px; padding:12px}
.kpi .n{font-size:22px; font-weight:900}
.kpi .l{font-size:12px; color:var(--muted); margin-top:4px}
.chip{font-size:11px; padding:4px 8px; border-radius:999px; border:1px solid var(--border);
  background:rgba(0,0,0,.18); color:var(--muted)}
.sep{height:1px; background:var(--border); opacity:.8; margin:10px 0}
.tools{display:grid; grid-template-columns:repeat(4,1fr); gap:10px;}
@media (max-width:1040px){.tools{grid-template-columns:repeat(2,1fr);}}
.tool{border:1px solid var(--border); background:rgba(0,0,0,.10); border-radius:16px; padding:10px}
.tool .name{font-size:12px; font-weight:900}
.tool .meta{margin-top:6px; display:flex; align-items:center; justify-content:space-between; font-size:11px; color:var(--muted)}
pre{white-space:pre-wrap; word-break:break-word; margin:0; font-size:12px; color:var(--muted)}
CSS

cat > "$JS" <<'JS'
/* VSP_DASH_ONLY_V1 (Dashboard-only renderer)
   Only calls:
   - /api/vsp/rid_latest_gate_root
   - /api/vsp/run_file_allow?rid=...&path=run_gate_summary.json
*/
(()=> {
  if (window.__vsp_dash_only_v1) return;
  window.__vsp_dash_only_v1 = true;

  const esc = (s)=> String(s ?? "").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  const $ = (id)=> document.getElementById(id);

  function dotClass(overall){
    const o = String(overall||"").toUpperCase();
    if (o.includes("PASS") || o.includes("GREEN")) return "good";
    if (o.includes("AMBER") || o.includes("WARN")) return "warn";
    if (o.includes("FAIL") || o.includes("RED")) return "bad";
    return "";
  }

  function pickCounts(sum){
    const ct = sum && (sum.counts_total || sum.counts || (sum.meta && sum.meta.counts_by_severity));
    const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,TOTAL:0};
    if (ct && typeof ct === "object"){
      for (const k of ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]){
        out[k] = Number(ct[k] ?? ct[k.toLowerCase()] ?? 0) || 0;
      }
      const t = Number(ct.TOTAL ?? ct.total);
      out.TOTAL = (t && t>0) ? t : (out.CRITICAL+out.HIGH+out.MEDIUM+out.LOW+out.INFO+out.TRACE);
    }
    return out;
  }

  function normalizeTools(sum){
    const bt = sum && sum.by_tool;
    const tools = [];
    if (bt && typeof bt === "object"){
      for (const [name, obj] of Object.entries(bt)){
        const st = String((obj && (obj.status || obj.state || obj.result)) || "UNKNOWN");
        const degraded = !!(obj && (obj.degraded || obj.is_degraded));
        const missing = !!(obj && (obj.missing || obj.is_missing));
        tools.push({name, st, degraded, missing});
      }
    }
    const order = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
    tools.sort((a,b)=> (order.indexOf(a.name)-order.indexOf(b.name)) || a.name.localeCompare(b.name));
    return tools;
  }

  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }

  function ensureLayout(){
    const root = $("vsp5_root");
    if (!root) throw new Error("missing #vsp5_root");
    if (root.__dash_only_inited) return;
    root.__dash_only_inited = true;

    root.innerHTML = `
      <div class="vsp-wrap">
        <div class="top">
          <div class="title">
            <div class="h">VSP • Dashboard</div>
            <div class="s">Dash-only: rid_latest_gate_root + run_gate_summary.json • Updated: <span id="d_upd">—</span></div>
          </div>
          <div class="actions">
            <span id="d_status" class="badge"><span class="dot"></span>—</span>
            <span class="badge"><span class="dot"></span>RID: <span id="d_rid">—</span></span>
            <button class="btn" id="d_refresh">Refresh</button>
            <button class="btn" id="d_sum">Summary JSON</button>
          </div>
        </div>

        <div class="grid">
          <div class="card">
            <div class="t"><div class="h">KPIs</div><div class="s">Counts-only</div></div>
            <div class="kpis">
              <div class="kpi"><div class="n" id="k_total">—</div><div class="l">TOTAL</div></div>
              <div class="kpi"><div class="n" id="k_crit">—</div><div class="l">CRITICAL</div></div>
              <div class="kpi"><div class="n" id="k_high">—</div><div class="l">HIGH</div></div>
              <div class="kpi"><div class="n" id="k_med">—</div><div class="l">MEDIUM</div></div>
              <div class="kpi"><div class="n" id="k_low">—</div><div class="l">LOW</div></div>
              <div class="kpi"><div class="n" id="k_info">—</div><div class="l">INFO</div></div>
              <div class="kpi"><div class="n" id="k_trace">—</div><div class="l">TRACE</div></div>
            </div>

            <div class="sep"></div>
            <div class="t"><div class="h">Evidence quick-links</div><div class="s">allowlisted</div></div>
            <div id="d_ev" style="display:flex;flex-wrap:wrap;gap:8px"></div>
          </div>

          <div class="card">
            <div class="t"><div class="h">Tool lanes</div><div class="s">by_tool</div></div>
            <div class="tools" id="d_tools"></div>
            <div class="sep"></div>
            <div class="t"><div class="h">Snapshot</div><div class="s">safe</div></div>
            <pre id="d_raw" style="margin-top:8px"></pre>
          </div>
        </div>
      </div>
    `;
  }

  async function load(){
    ensureLayout();
    $("d_status").innerHTML = `<span class="dot"></span>Loading…`;
    $("d_raw").textContent = "";

    const latest = await jget("/api/vsp/rid_latest_gate_root");
    const rid = latest.rid || latest.run_id || "";
    $("d_rid").textContent = rid || "(none)";

    const sum = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
    const overall = String(sum.overall_status || sum.overall || (sum.gate && sum.gate.overall) || "UNKNOWN");

    $("d_status").innerHTML = `<span class="dot ${dotClass(overall)}"></span><b>${esc(overall)}</b>`;
    $("d_upd").textContent = new Date().toLocaleString();

    const c = pickCounts(sum);
    $("k_total").textContent = c.TOTAL;
    $("k_crit").textContent  = c.CRITICAL;
    $("k_high").textContent  = c.HIGH;
    $("k_med").textContent   = c.MEDIUM;
    $("k_low").textContent   = c.LOW;
    $("k_info").textContent  = c.INFO;
    $("k_trace").textContent = c.TRACE;

    const ev = ["run_gate_summary.json","run_gate.json","findings_unified.json","reports/findings_unified.csv"];
    $("d_ev").innerHTML = ev.map(p=>{
      const href = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(p)}`;
      return `<a class="chip" href="${href}" target="_blank" rel="noreferrer">${esc(p)}</a>`;
    }).join("");

    const tools = normalizeTools(sum);
    $("d_tools").innerHTML = tools.map(t=>{
      const up = t.st.toUpperCase();
      let dc = "";
      if (t.missing || t.degraded) dc="warn";
      else if (up.includes("OK")||up.includes("PASS")) dc="good";
      else if (up.includes("FAIL")||up.includes("ERR")) dc="bad";
      return `
        <div class="tool">
          <div class="name">${esc(t.name)}</div>
          <div class="meta">
            <span><span class="dot ${dc}"></span>${esc(t.st)}</span>
            <span>${t.degraded ? "degraded" : (t.missing ? "missing" : "ok")}</span>
          </div>
        </div>`;
    }).join("");

    $("d_raw").textContent = JSON.stringify({ rid, overall, counts:c }, null, 2);

    $("d_refresh").onclick = ()=> load().catch(()=>{});
    $("d_sum").onclick = ()=> window.open(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`, "_blank");
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    console.info("[VSP][DASH_ONLY_V1] boot");
    load().catch(e=> console.warn("[VSP][DASH_ONLY_V1] err", e));
    setInterval(()=> load().catch(()=>{}), 30000);
  });
})();
JS

echo "[OK] wrote $CSS"
echo "[OK] wrote $JS"

# (2) Patch vsp_demo_app.py: remove bundle/legacy from /vsp5 stub and inject dash-only assets
cp -f "$PYF" "${PYF}.bak_dashonly_${TS}"
echo "[BACKUP] ${PYF}.bak_dashonly_${TS}"

python3 - <<PY
from pathlib import Path
import re

p = Path("${PYF}")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace the specific script-chain in the /vsp5 HTML (bundle/legacy) with dash-only tags
ver = "${VER}"
dash = (
  f'  <!-- VSP_P1_VSP5_DASH_ONLY_ROUTE_V1 -->\\n'
  f'  <link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css?v={ver}"/>\\n'
  f'  <script defer src="/static/js/vsp_dash_only_v1.js?v={ver}"></script>\\n'
)

# Kill any script tags that reference bundle/legacy in vsp5 stub
# We do it broadly but only inside the VSP5 HTML stub area by anchoring on "<title>VSP5</title>"
if "<title>VSP5</title>" not in s:
  raise SystemExit("[ERR] cannot find VSP5 stub (<title>VSP5</title>) in vsp_demo_app.py")

# Remove all /static/js scripts in the stub by replacing the whole tail before </body> with dash-only
pat = re.compile(r'(<title>VSP5</title>.*?)(</head>)(.*?)(</body>)', re.I | re.S)

m = pat.search(s)
if not m:
  raise SystemExit("[ERR] cannot locate VSP5 HTML structure to patch")

head = m.group(1) + m.group(2)
body = m.group(3)
tail = m.group(4)

# remove any existing script tags in body (only affects stub block)
body2 = re.sub(r'(?is)<script[^>]+src="[^"]*/static/js/[^"]+"[^>]*>\\s*</script>', "", body)

# ensure vsp5_root exists
if 'id="vsp5_root"' not in body2:
  body2 = re.sub(r'(?is)<body[^>]*>', lambda mm: mm.group(0)+"\\n  <div id=\\"vsp5_root\\"></div>\\n", body2, count=1)

# inject dash-only assets before </body>
new_block = body2 + "\\n" + dash + "\\n" + tail

s2 = s[:m.start()] + head + new_block + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] patched vsp_demo_app.py: VSP_P1_VSP5_DASH_ONLY_ROUTE_V1")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true

echo "== verify /vsp5 html now contains dash-only and NOT bundle =="
curl -fsS "$BASE/vsp5" | grep -E "vsp_dash_only_v1|vsp_bundle_commercial_v2" -n || true
echo
echo "[DONE] Open /vsp5 then HARD refresh (Ctrl+Shift+R). Console must show: [VSP][DASH_ONLY_V1] boot"
