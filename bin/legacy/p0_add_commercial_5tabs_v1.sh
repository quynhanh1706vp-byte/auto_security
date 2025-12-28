#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_DEFAULT="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need mkdir; need grep; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_commercial_5tabs_v1_${TS}"
echo "[BACKUP] ${APP}.bak_commercial_5tabs_v1_${TS}"

mkdir -p templates static/js

# ----------------------------
# 1) Base template
# ----------------------------
cat > templates/vsp_c_base_v1.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{{ title }}</title>
  <style>
    :root{
      --bg:#0b1020; --panel:#0f162b; --panel2:#101a33; --line:rgba(255,255,255,.10);
      --text:#e9eefc; --muted:rgba(233,238,252,.65); --accent:#4fd1c5;
      --good:#22c55e; --warn:#f59e0b; --bad:#ef4444;
      --chip:rgba(255,255,255,.06);
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
    }
    *{box-sizing:border-box}
    body{
      margin:0;
      background:radial-gradient(1200px 900px at 20% -10%, #1a2a55 0%, transparent 55%), var(--bg);
      color:var(--text);
      font-family:var(--sans);
    }
    .topbar{
      position:sticky; top:0; z-index:50;
      display:flex; align-items:center; justify-content:space-between;
      padding:12px 16px;
      background:rgba(9,12,20,.76);
      backdrop-filter: blur(10px);
      border-bottom:1px solid var(--line);
      gap:12px;
    }
    .brand{display:flex; gap:10px; align-items:center; min-width:240px}
    .dot{width:10px;height:10px;border-radius:999px;background:var(--good);box-shadow:0 0 18px rgba(34,197,94,.6)}
    .title{font-weight:800; letter-spacing:.2px}
    .sub{font-size:12px; color:var(--muted)}
    .nav{
      display:flex; gap:8px; flex-wrap:wrap; align-items:center; justify-content:center; flex:1;
    }
    .tab{
      font-family:var(--mono);
      font-size:12px;
      padding:8px 10px;
      border-radius:999px;
      border:1px solid rgba(255,255,255,.12);
      background:rgba(255,255,255,.05);
      cursor:pointer;
      color:var(--text);
      text-decoration:none;
    }
    .tab.active{border-color:rgba(79,209,197,.35); box-shadow:0 0 0 1px rgba(79,209,197,.18) inset}
    .right{display:flex; align-items:center; gap:10px; flex-wrap:wrap; justify-content:flex-end; min-width:360px}
    .pill{
      font-family:var(--mono);
      font-size:12px;
      padding:7px 10px;
      border-radius:999px;
      background:var(--chip);
      border:1px solid var(--line);
      white-space:nowrap;
    }
    .btn{
      font-family:var(--mono);
      font-size:12px;
      padding:8px 10px;
      border-radius:10px;
      border:1px solid rgba(255,255,255,.14);
      background:rgba(255,255,255,.06);
      color:var(--text);
      cursor:pointer;
    }
    .btn:hover{background:rgba(255,255,255,.10)}
    .btn.primary{border-color:rgba(79,209,197,.35); box-shadow:0 0 0 1px rgba(79,209,197,.20) inset}
    .wrap{max-width:1260px; margin:0 auto; padding:18px 16px 40px}
    .grid{display:grid; gap:12px}
    .panel{
      background:linear-gradient(180deg, rgba(255,255,255,.04), rgba(255,255,255,.02));
      border:1px solid var(--line);
      border-radius:16px;
      padding:14px 14px;
      box-shadow:0 18px 40px rgba(0,0,0,.25);
    }
    .h{display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:8px}
    .h .hh{font-weight:900}
    .h .hh2{font-size:12px;color:var(--muted); font-family:var(--mono)}
    .muted{color:var(--muted)}
    .mono{font-family:var(--mono)}
    .table{
      width:100%;
      border-collapse:separate;
      border-spacing:0;
      font-family:var(--mono);
      font-size:12px;
      overflow:hidden;
      border-radius:14px;
      border:1px solid var(--line);
      background:rgba(0,0,0,.12);
    }
    .table th, .table td{
      padding:10px 10px;
      border-bottom:1px solid rgba(255,255,255,.06);
      vertical-align:top;
    }
    .table th{color:rgba(233,238,252,.75); text-align:left; background:rgba(255,255,255,.03)}
    .sev{
      display:inline-flex; align-items:center; gap:7px;
      padding:3px 8px; border-radius:999px;
      border:1px solid rgba(255,255,255,.12);
      background:rgba(255,255,255,.05);
    }
    .s-dot{width:8px;height:8px;border-radius:999px}
    .s-critical{background:var(--bad)}
    .s-high{background:#fb7185}
    .s-medium{background:var(--warn)}
    .s-low{background:#60a5fa}
    .s-info{background:#a78bfa}
    .input{
      width:100%;
      padding:10px 10px;
      border-radius:12px;
      border:1px solid rgba(255,255,255,.12);
      background:rgba(0,0,0,.16);
      color:var(--text);
      font-family:var(--mono);
      font-size:12px;
      outline:none;
    }
    .row{display:flex; gap:10px; flex-wrap:wrap; align-items:center}
    .spacer{height:10px}
  </style>
</head>
<body data-active="{{ active_tab }}" data-rid="{{ rid|e }}">
  <div class="topbar">
    <div class="brand">
      <span class="dot"></span>
      <div>
        <div class="title">VSP • Commercial</div>
        <div class="sub">5 tabs • API-driven • freeze-safe</div>
      </div>
    </div>

    <div class="nav">
      <a class="tab" data-tab="dashboard" href="/c/dashboard?rid={{ rid|e }}">Dashboard</a>
      <a class="tab" data-tab="runs" href="/c/runs?rid={{ rid|e }}">Runs & Reports</a>
      <a class="tab" data-tab="data_source" href="/c/data_source?rid={{ rid|e }}">Data Source</a>
      <a class="tab" data-tab="settings" href="/c/settings?rid={{ rid|e }}">Settings</a>
      <a class="tab" data-tab="rule_overrides" href="/c/rule_overrides?rid={{ rid|e }}">Rule Overrides</a>
    </div>

    <div class="right">
      <span class="pill" id="p-rid">RID: …</span>
      <span class="pill" id="p-ds">DATA SOURCE: …</span>
      <span class="pill" id="p-pin">PIN: …</span>
      <button class="btn" id="b-auto">AUTO</button>
      <button class="btn" id="b-global">PIN GLOBAL</button>
      <button class="btn" id="b-rid">USE RID</button>
      <button class="btn primary" id="b-refresh">REFRESH</button>
    </div>
  </div>

  <div class="wrap">
    {% block body %}{% endblock %}
  </div>

  <script src="/static/js/vsp_c_common_v1.js?v={{ asset_v }}"></script>
  {% block scripts %}{% endblock %}
</body>
</html>
HTML

# ----------------------------
# 2) Dashboard template + JS
# ----------------------------
cat > templates/vsp_c_dashboard_v1.html <<'HTML'
{% extends "vsp_c_base_v1.html" %}
{% block body %}
  <div class="grid" style="grid-template-columns:repeat(4,minmax(0,1fr)); margin-bottom:12px">
    <div class="panel">
      <div class="h"><div class="hh">Total Findings</div><div class="hh2 mono" id="k-time">…</div></div>
      <div style="font-size:26px;font-weight:900" id="k-total">…</div>
      <div class="muted mono" id="k-from">from_path: …</div>
    </div>
    <div class="panel">
      <div class="h"><div class="hh">Top Findings</div><div class="hh2">limit 200</div></div>
      <div style="font-size:26px;font-weight:900" id="k-toplen">…</div>
      <div class="muted mono" id="k-topmeta">source: top_findings_v3c</div>
    </div>
    <div class="panel">
      <div class="h"><div class="hh">Trend</div><div class="hh2">points</div></div>
      <div style="font-size:26px;font-weight:900" id="k-trend">…</div>
      <div class="muted mono" id="k-trendmeta">source: trend_v1</div>
    </div>
    <div class="panel">
      <div class="h"><div class="hh">Status</div><div class="hh2 mono" id="k-status">LIVE</div></div>
      <div class="muted mono">Commercial suite: /c/*</div>
      <div class="muted mono">No heavy DOM • freeze-safe</div>
    </div>
  </div>

  <div class="grid" style="grid-template-columns: 1.55fr .45fr;">
    <div class="panel">
      <div class="h"><div class="hh">Top Findings</div><div class="hh2 mono" id="t-meta">…</div></div>
      <table class="table">
        <thead>
          <tr>
            <th style="width:140px">SEVERITY</th>
            <th>TITLE</th>
            <th style="width:110px">TOOL</th>
            <th style="width:220px">FILE</th>
          </tr>
        </thead>
        <tbody id="tb">
          <tr><td colspan="4" class="muted">Loading…</td></tr>
        </tbody>
      </table>
    </div>

    <div class="panel">
      <div class="h"><div class="hh">Trend (mini)</div><div class="hh2">preview</div></div>
      <div class="panel" style="padding:10px; border-radius:14px; background:rgba(0,0,0,.10)" id="trend-mini">Loading…</div>
      <div class="spacer"></div>
      <div class="muted mono">Tip: dùng PIN GLOBAL khi demo, AUTO khi chạy thường.</div>
    </div>
  </div>
{% endblock %}
{% block scripts %}
  <script src="/static/js/vsp_c_dashboard_v1.js?v={{ asset_v }}"></script>
{% endblock %}
HTML

cat > static/js/vsp_c_dashboard_v1.js <<'JS'
(function(){
  const U = window.__VSPC;
  const rid = U.rid();
  const tb = document.getElementById("tb");

  function row(it){
    const sev=(it.severity||"INFO").toUpperCase();
    return `<tr>
      <td><span class="sev"><span class="s-dot ${U.sevDot(sev)}"></span>${U.esc(sev)}</span></td>
      <td>${U.esc(it.title||"(no title)")}</td>
      <td>${U.esc(it.tool||it.scanner||"")}</td>
      <td class="muted">${U.esc(U.shortFile(it.file||""))}</td>
    </tr>`;
  }

  async function load(){
    document.getElementById("k-time").textContent = new Date().toLocaleString();

    const f = await U.jget(`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=1&offset=0&pin=${encodeURIComponent(U.mode())}`);
    if (f && f.ok){
      document.getElementById("k-total").textContent = (f.total_findings != null ? String(f.total_findings) : "—");
      document.getElementById("k-from").textContent = "from_path: " + (f.from_path||"—");
      U.paintPills(f);
    } else {
      document.getElementById("k-total").textContent = "ERR";
      document.getElementById("k-from").textContent = "from_path: (api err)";
    }

    const t = await U.jget(`/api/vsp/top_findings_v3c?rid=${encodeURIComponent(rid)}&limit=200&pin=${encodeURIComponent(U.mode())}`);
    const items = (t && t.items) ? t.items : [];
    document.getElementById("k-toplen").textContent = String(items.length);
    document.getElementById("t-meta").textContent = `items=${items.length}  limit=${t.limit_applied||200}`;
    tb.innerHTML = items.length ? items.slice(0,200).map(row).join("") : `<tr><td colspan="4" class="muted">No items</td></tr>`;

    const tr = await U.jget(`/api/vsp/trend_v1`);
    const pts = (tr && (tr.points||tr.data)) || [];
    document.getElementById("k-trend").textContent = String(Array.isArray(pts)?pts.length:0);
    document.getElementById("trend-mini").textContent =
      Array.isArray(pts) && pts.length ? `latest: ${(pts[0].label||pts[0].ts||"").toString()}` : "no points";
  }

  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
JS

# ----------------------------
# 3) Runs template + JS
# ----------------------------
cat > templates/vsp_c_runs_v1.html <<'HTML'
{% extends "vsp_c_base_v1.html" %}
{% block body %}
  <div class="panel">
    <div class="h">
      <div>
        <div class="hh">Runs & Reports</div>
        <div class="hh2">Pick a RID → open Dashboard / Data Source</div>
      </div>
      <div class="hh2 mono" id="runs-meta">…</div>
    </div>

    <div class="row" style="margin-bottom:10px">
      <input class="input" id="runs-q" placeholder="Filter by RID / label / date (client-side)" />
    </div>

    <table class="table">
      <thead>
        <tr>
          <th style="width:340px">RID</th>
          <th style="width:220px">LABEL/TS</th>
          <th class="muted">ACTIONS</th>
        </tr>
      </thead>
      <tbody id="runs-tb">
        <tr><td colspan="3" class="muted">Loading…</td></tr>
      </tbody>
    </table>
  </div>
{% endblock %}
{% block scripts %}
  <script src="/static/js/vsp_c_runs_v1.js?v={{ asset_v }}"></script>
{% endblock %}
HTML

cat > static/js/vsp_c_runs_v1.js <<'JS'
(function(){
  const U = window.__VSPC;
  const tb = document.getElementById("runs-tb");
  const q = document.getElementById("runs-q");

  let rows = [];

  function render(){
    const s = (q.value||"").toLowerCase().trim();
    const show = s ? rows.filter(r => (r._search||"").includes(s)) : rows;
    tb.innerHTML = show.length ? show.map(r=>r._html).join("") : `<tr><td colspan="3" class="muted">No rows</td></tr>`;
    document.getElementById("runs-meta").textContent = `rows=${show.length}/${rows.length}`;
  }

  async function load(){
    const j = await U.jget(`/api/vsp/runs?limit=80&offset=0`);
    const runs = (j && j.runs) ? j.runs : [];
    rows = runs.map(r=>{
      const rid = r.rid || r.run_id || r.id || "";
      const label = r.label || r.ts || r.time || "";
      const dash = `/c/dashboard?rid=${encodeURIComponent(rid)}`;
      const ds   = `/c/data_source?rid=${encodeURIComponent(rid)}`;
      const h = `<tr>
        <td class="mono">${U.esc(rid)}</td>
        <td class="mono muted">${U.esc(label)}</td>
        <td class="mono">
          <a class="tab" href="${dash}">Open Dashboard</a>
          <a class="tab" href="${ds}">Data Source</a>
        </td>
      </tr>`;
      return {_search:(rid+" "+label).toLowerCase(), _html:h};
    });
    render();
  }

  q.addEventListener("input", ()=>render(), {passive:true});
  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
JS

# ----------------------------
# 4) Data Source template + JS
# ----------------------------
cat > templates/vsp_c_data_source_v1.html <<'HTML'
{% extends "vsp_c_base_v1.html" %}
{% block body %}
  <div class="panel">
    <div class="h">
      <div>
        <div class="hh">Data Source</div>
        <div class="hh2">Preview unified findings (first 200 rows) • client filter</div>
      </div>
      <div class="hh2 mono" id="ds-meta">…</div>
    </div>

    <div class="row" style="margin-bottom:10px">
      <input class="input" id="ds-q" placeholder="Filter by severity/tool/title/file (client-side)" />
      <button class="btn" id="ds-more">Next +200</button>
      <span class="pill" id="ds-off">offset=0</span>
    </div>

    <table class="table">
      <thead>
        <tr>
          <th style="width:140px">SEVERITY</th>
          <th>TITLE</th>
          <th style="width:110px">TOOL</th>
          <th style="width:260px">FILE</th>
        </tr>
      </thead>
      <tbody id="ds-tb">
        <tr><td colspan="4" class="muted">Loading…</td></tr>
      </tbody>
    </table>
    <div class="spacer"></div>
    <div class="muted mono" id="ds-from">from_path: …</div>
  </div>
{% endblock %}
{% block scripts %}
  <script src="/static/js/vsp_c_data_source_v1.js?v={{ asset_v }}"></script>
{% endblock %}
HTML

cat > static/js/vsp_c_data_source_v1.js <<'JS'
(function(){
  const U = window.__VSPC;
  const rid = U.rid();
  const tb = document.getElementById("ds-tb");
  const q  = document.getElementById("ds-q");
  const more = document.getElementById("ds-more");
  const offP = document.getElementById("ds-off");

  let offset = 0;
  let items = [];

  function row(it){
    const sev=(it.severity||"INFO").toUpperCase();
    return `<tr>
      <td><span class="sev"><span class="s-dot ${U.sevDot(sev)}"></span>${U.esc(sev)}</span></td>
      <td>${U.esc(it.title||"(no title)")}</td>
      <td>${U.esc(it.tool||it.scanner||"")}</td>
      <td class="muted">${U.esc(U.shortFile(it.file||""))}</td>
    </tr>`;
  }

  function render(){
    const s = (q.value||"").toLowerCase().trim();
    const show = s ? items.filter(it => U.searchable(it).includes(s)) : items;
    tb.innerHTML = show.length ? show.slice(0,2000).map(row).join("") : `<tr><td colspan="4" class="muted">No rows</td></tr>`;
    document.getElementById("ds-meta").textContent = `loaded=${items.length}  showing=${show.length}`;
  }

  async function loadPage(){
    offP.textContent = "offset=" + offset;
    const j = await U.jget(`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=200&offset=${offset}&pin=${encodeURIComponent(U.mode())}`);
    if (j && j.ok){
      U.paintPills(j);
      document.getElementById("ds-from").textContent = "from_path: " + (j.from_path||"—");
      const got = j.items || [];
      items = items.concat(got);
      offset += got.length;
      render();
    } else {
      tb.innerHTML = `<tr><td colspan="4" class="muted">API error</td></tr>`;
    }
  }

  q.addEventListener("input", ()=>render(), {passive:true});
  more.addEventListener("click", ()=>loadPage(), {passive:true});
  document.addEventListener("DOMContentLoaded", ()=>loadPage(), {once:true});
  U.onRefresh(()=>{ offset=0; items=[]; loadPage(); });
})();
JS

# ----------------------------
# 5) Settings template + JS
# ----------------------------
cat > templates/vsp_c_settings_v1.html <<'HTML'
{% extends "vsp_c_base_v1.html" %}
{% block body %}
  <div class="grid" style="grid-template-columns: 1fr 1fr;">
    <div class="panel">
      <div class="h"><div class="hh">Settings</div><div class="hh2">Commercial behaviors</div></div>
      <div class="muted mono">PIN default (stored local): <b id="s-pin">…</b></div>
      <div class="spacer"></div>
      <button class="btn" id="s-set-auto">Set AUTO</button>
      <button class="btn" id="s-set-global">Set PIN GLOBAL</button>
      <button class="btn" id="s-set-rid">Set USE RID</button>
      <div class="spacer"></div>
      <div class="muted mono">
        Notes:
        <ul>
          <li>DATA SOURCE là “effective” dựa trên from_path (GLOBAL_BEST vs RID)</li>
          <li>UI suite /c/* không đè UI cũ, để rollback dễ.</li>
        </ul>
      </div>
    </div>

    <div class="panel">
      <div class="h"><div class="hh">Endpoint Probes</div><div class="hh2 mono" id="s-meta">…</div></div>
      <table class="table">
        <thead><tr><th>API</th><th>Status</th></tr></thead>
        <tbody id="s-tb">
          <tr><td colspan="2" class="muted">Loading…</td></tr>
        </tbody>
      </table>
    </div>
  </div>
{% endblock %}
{% block scripts %}
  <script src="/static/js/vsp_c_settings_v1.js?v={{ asset_v }}"></script>
{% endblock %}
HTML

cat > static/js/vsp_c_settings_v1.js <<'JS'
(function(){
  const U = window.__VSPC;
  const tb = document.getElementById("s-tb");
  const sp = document.getElementById("s-pin");

  function set(m){ localStorage.setItem("vsp_pin_mode_v2", m); sp.textContent = m.toUpperCase(); }
  document.getElementById("s-set-auto").addEventListener("click", ()=>set("auto"), {passive:true});
  document.getElementById("s-set-global").addEventListener("click", ()=>set("global"), {passive:true});
  document.getElementById("s-set-rid").addEventListener("click", ()=>set("rid"), {passive:true});

  async function probe(name, url){
    try{
      const r = await fetch(url, {cache:"no-store", credentials:"same-origin"});
      return {name, ok:r.ok, code:r.status};
    }catch(e){
      return {name, ok:false, code:"ERR"};
    }
  }

  async function load(){
    sp.textContent = U.mode().toUpperCase();
    const rid = U.rid();
    const pin = U.mode();
    const list = await Promise.all([
      probe("findings_page_v3", `/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=1&offset=0&pin=${encodeURIComponent(pin)}`),
      probe("top_findings_v3c", `/api/vsp/top_findings_v3c?rid=${encodeURIComponent(rid)}&limit=10&pin=${encodeURIComponent(pin)}`),
      probe("trend_v1", `/api/vsp/trend_v1`),
      probe("runs", `/api/vsp/runs?limit=1&offset=0`)
    ]);
    tb.innerHTML = list.map(x => `<tr><td class="mono">${U.esc(x.name)}</td><td class="mono ${x.ok?'':'muted'}">${U.esc(String(x.code))}</td></tr>`).join("");
    document.getElementById("s-meta").textContent = "pin=" + pin.toUpperCase();
  }

  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
JS

# ----------------------------
# 6) Rule Overrides template + JS (backend if exists, else localStorage)
# ----------------------------
cat > templates/vsp_c_rule_overrides_v1.html <<'HTML'
{% extends "vsp_c_base_v1.html" %}
{% block body %}
  <div class="panel">
    <div class="h">
      <div>
        <div class="hh">Rule Overrides</div>
        <div class="hh2">Prefer backend /api/vsp/rule_overrides_v1, fallback localStorage</div>
      </div>
      <div class="hh2 mono" id="ro-meta">…</div>
    </div>

    <div class="row" style="margin-bottom:10px">
      <button class="btn" id="ro-load">LOAD</button>
      <button class="btn primary" id="ro-save">SAVE</button>
      <button class="btn" id="ro-export">EXPORT</button>
      <span class="pill" id="ro-status">…</span>
    </div>

    <textarea class="input" id="ro-text" style="min-height:380px; resize:vertical;"
      placeholder='Paste overrides JSON here. Example: {"disable_rules":["RULE_ID"],"severity_overrides":{"RULE_ID":"LOW"}}'></textarea>
    <div class="spacer"></div>
    <div class="muted mono" id="ro-hint">
      Tip: Nếu backend chưa có endpoint, hệ thống sẽ lưu localStorage key: vsp_rule_overrides_v1.
    </div>
  </div>
{% endblock %}
{% block scripts %}
  <script src="/static/js/vsp_c_rule_overrides_v1.js?v={{ asset_v }}"></script>
{% endblock %}
HTML

cat > static/js/vsp_c_rule_overrides_v1.js <<'JS'
(function(){
  const U = window.__VSPC;
  const t = document.getElementById("ro-text");
  const st = document.getElementById("ro-status");
  const meta = document.getElementById("ro-meta");
  const LS="vsp_rule_overrides_v1";

  function setStatus(s){ st.textContent = s; }

  async function tryGet(){
    try{
      const r = await fetch("/api/vsp/rule_overrides_v1", {cache:"no-store", credentials:"same-origin"});
      if (!r.ok) throw new Error(String(r.status));
      return {ok:true, text: await r.text(), src:"backend"};
    }catch(e){
      return {ok:true, text: localStorage.getItem(LS) || "{}", src:"local"};
    }
  }

  async function trySave(txt){
    // validate JSON first
    try{ JSON.parse(txt); }catch(e){ setStatus("JSON invalid"); throw e; }

    try{
      const r = await fetch("/api/vsp/rule_overrides_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: txt,
        credentials:"same-origin"
      });
      if (r.ok){
        localStorage.setItem(LS, txt);
        return {ok:true, src:"backend"};
      }
      throw new Error(String(r.status));
    }catch(e){
      localStorage.setItem(LS, txt);
      return {ok:true, src:"local"};
    }
  }

  async function load(){
    const g = await tryGet();
    t.value = g.text || "{}";
    meta.textContent = "source=" + g.src;
    setStatus("loaded");
  }

  async function save(){
    setStatus("saving…");
    const r = await trySave(t.value || "{}");
    meta.textContent = "source=" + r.src;
    setStatus("saved");
  }

  function exportTxt(){
    const blob = new Blob([t.value||"{}"], {type:"application/json"});
    const a=document.createElement("a");
    a.href=URL.createObjectURL(blob);
    a.download="rule_overrides.json";
    a.click();
    setStatus("exported");
  }

  document.getElementById("ro-load").addEventListener("click", ()=>load(), {passive:true});
  document.getElementById("ro-save").addEventListener("click", ()=>save(), {passive:true});
  document.getElementById("ro-export").addEventListener("click", ()=>exportTxt(), {passive:true});

  document.addEventListener("DOMContentLoaded", load, {once:true});
  U.onRefresh(load);
})();
JS

# ----------------------------
# 7) Common JS (pin + pills + nav active + refresh hook)
# ----------------------------
cat > static/js/vsp_c_common_v1.js <<'JS'
(function(){
  if (window.__VSPC) return;
  const LS_KEY="vsp_pin_mode_v2"; // auto|global|rid
  const MODES=["auto","global","rid"];

  function rid(){
    const qs = new URLSearchParams(location.search);
    return (qs.get("rid") || document.body.getAttribute("data-rid") || "").trim();
  }
  function mode(){
    const m = (localStorage.getItem(LS_KEY) || "auto").toLowerCase();
    return MODES.includes(m) ? m : "auto";
  }
  function setMode(m){
    localStorage.setItem(LS_KEY, MODES.includes(m)?m:"auto");
  }
  function esc(s){ return String(s||"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }
  function sevDot(sev){
    const s=(sev||"").toUpperCase();
    if (s==="CRITICAL") return "s-critical";
    if (s==="HIGH") return "s-high";
    if (s==="MEDIUM") return "s-medium";
    if (s==="LOW") return "s-low";
    return "s-info";
  }
  function shortFile(f){
    const s=String(f||"");
    const parts=s.split("/");
    return parts.slice(Math.max(0, parts.length-4)).join("/");
  }
  function searchable(it){
    const a = [it.severity,it.tool,it.scanner,it.title,it.file].filter(Boolean).join(" ");
    return a.toLowerCase();
  }
  async function jget(url){
    const r=await fetch(url, {cache:"no-store", credentials:"same-origin"});
    const txt=await r.text();
    try{ return JSON.parse(txt); }
    catch(e){ return {ok:false, _err:"json_parse", _head:txt.slice(0,220)}; }
  }

  function paintPills(info){
    const pr=document.getElementById("p-rid");
    const pd=document.getElementById("p-ds");
    const pp=document.getElementById("p-pin");
    if (pr) pr.textContent = "RID: " + (rid() || "(none)");
    if (pp) pp.textContent = "PIN: " + mode().toUpperCase();
    if (pd) pd.textContent = "DATA SOURCE: " + (info && info.data_source ? info.data_source : "…");
  }

  function nav(pin){
    setMode(pin);
    const u=new URL(location.href);
    u.searchParams.set("rid", rid());
    u.searchParams.set("pin", pin);
    location.href=u.toString();
  }

  let _refreshHandler = null;
  function onRefresh(fn){ _refreshHandler = fn; }

  function setActiveTab(){
    const active = document.body.getAttribute("data-active") || "";
    document.querySelectorAll(".tab[data-tab]").forEach(a=>{
      if (a.getAttribute("data-tab")===active) a.classList.add("active");
    });
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    setActiveTab();
    const bA=document.getElementById("b-auto");
    const bG=document.getElementById("b-global");
    const bR=document.getElementById("b-rid");
    const bF=document.getElementById("b-refresh");
    if (bA) bA.addEventListener("click", ()=>nav("auto"), {passive:true});
    if (bG) bG.addEventListener("click", ()=>nav("global"), {passive:true});
    if (bR) bR.addEventListener("click", ()=>nav("rid"), {passive:true});
    if (bF) bF.addEventListener("click", ()=>{ if (_refreshHandler) _refreshHandler(); }, {passive:true});

    // Always refresh pills using findings_page_v3 (ground truth)
    (async ()=>{
      try{
        const f = await jget(`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid())}&limit=1&offset=0&pin=${encodeURIComponent(mode())}`);
        if (f && f.ok) paintPills(f);
        else paintPills({});
      }catch(e){ paintPills({}); }
    })();
  }, {once:true});

  window.__VSPC = { rid, mode, setMode, esc, sevDot, shortFile, searchable, jget, paintPills, onRefresh };
})();
JS

# ----------------------------
# 8) Patch routes into vsp_demo_app.py (append, idempotent via marker)
# ----------------------------
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_COMMERCIAL_5TABS_V1_ROUTES"

if MARK in s:
    print("[OK] routes already present:", MARK)
else:
    block=f'''
# ===================== {MARK} =====================
@app.get("/c")
def vsp_c_index():
    rid=(request.args.get("rid") or "").strip()
    if not rid:
        # fallback to whatever user passes later; keep empty safe
        rid=""
    return redirect(url_for("vsp_c_dashboard") + (f"?rid={{rid}}" if rid else ""))

@app.get("/c/dashboard")
def vsp_c_dashboard():
    rid=(request.args.get("rid") or "").strip()
    import os as _os
    from datetime import datetime as _dt
    asset_v=_os.environ.get("VSP_ASSET_V","") or _dt.now().strftime("%Y%m%d_%H%M%S")
    return render_template("vsp_c_dashboard_v1.html", title="VSP • Commercial • Dashboard", active_tab="dashboard", rid=rid, asset_v=asset_v)

@app.get("/c/runs")
def vsp_c_runs():
    rid=(request.args.get("rid") or "").strip()
    import os as _os
    from datetime import datetime as _dt
    asset_v=_os.environ.get("VSP_ASSET_V","") or _dt.now().strftime("%Y%m%d_%H%M%S")
    return render_template("vsp_c_runs_v1.html", title="VSP • Commercial • Runs", active_tab="runs", rid=rid, asset_v=asset_v)

@app.get("/c/data_source")
def vsp_c_data_source():
    rid=(request.args.get("rid") or "").strip()
    import os as _os
    from datetime import datetime as _dt
    asset_v=_os.environ.get("VSP_ASSET_V","") or _dt.now().strftime("%Y%m%d_%H%M%S")
    return render_template("vsp_c_data_source_v1.html", title="VSP • Commercial • Data Source", active_tab="data_source", rid=rid, asset_v=asset_v)

@app.get("/c/settings")
def vsp_c_settings():
    rid=(request.args.get("rid") or "").strip()
    import os as _os
    from datetime import datetime as _dt
    asset_v=_os.environ.get("VSP_ASSET_V","") or _dt.now().strftime("%Y%m%d_%H%M%S")
    return render_template("vsp_c_settings_v1.html", title="VSP • Commercial • Settings", active_tab="settings", rid=rid, asset_v=asset_v)

@app.get("/c/rule_overrides")
def vsp_c_rule_overrides():
    rid=(request.args.get("rid") or "").strip()
    import os as _os
    from datetime import datetime as _dt
    asset_v=_os.environ.get("VSP_ASSET_V","") or _dt.now().strftime("%Y%m%d_%H%M%S")
    return render_template("vsp_c_rule_overrides_v1.html", title="VSP • Commercial • Rule Overrides", active_tab="rule_overrides", rid=rid, asset_v=asset_v)
# =================== /{MARK} ======================
'''
    p.write_text(s + "\n" + block, encoding="utf-8")
    print("[OK] appended routes:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] commercial tabs"
for p in /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$p?rid=$RID_DEFAULT" || true)"
  echo "  $p => $code"
done

echo "[DONE] Open:"
echo "  $BASE/c/dashboard?rid=$RID_DEFAULT"
echo "  $BASE/c/runs?rid=$RID_DEFAULT"
echo "  $BASE/c/data_source?rid=$RID_DEFAULT"
echo "  $BASE/c/settings?rid=$RID_DEFAULT"
echo "  $BASE/c/rule_overrides?rid=$RID_DEFAULT"
