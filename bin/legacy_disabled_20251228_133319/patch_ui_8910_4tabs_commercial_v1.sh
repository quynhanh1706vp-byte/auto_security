#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ui4tabs_${TS}"
echo "[BACKUP] $F.bak_ui4tabs_${TS}"

mkdir -p templates static/css static/js

# -----------------------------
# 1) CSS
# -----------------------------
cat > static/css/vsp_ui_4tabs_commercial_v1.css <<'CSS'
/* === VSP_UI_4TABS_COMMERCIAL_V1 === */
:root{
  --bg0:#020617; --bg1:#0b1220; --card:rgba(2,6,23,.55);
  --line:rgba(148,163,184,.18);
  --txt:rgba(226,232,240,.92); --mut:rgba(148,163,184,.75);
}
html,body{height:100%}
body{margin:0;background:radial-gradient(1200px 800px at 20% 10%, rgba(56,189,248,.08), transparent 60%),
     radial-gradient(900px 700px at 85% 25%, rgba(168,85,247,.08), transparent 55%),
     linear-gradient(180deg,var(--bg0),var(--bg1));
     color:var(--txt); font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial;}
a{color:inherit}
.vsp-shell{display:flex;min-height:100vh}
.vsp-side{width:270px;flex:0 0 auto;padding:18px 14px;border-right:1px solid var(--line);
  background:rgba(2,6,23,.65);backdrop-filter:blur(8px)}
.vsp-brand{display:flex;gap:10px;align-items:center;padding:10px 10px 14px 10px}
.vsp-logo{width:34px;height:34px;border-radius:12px;background:linear-gradient(135deg, rgba(56,189,248,.45), rgba(168,85,247,.35));
  border:1px solid var(--line)}
.vsp-title{font-weight:800;letter-spacing:.02em}
.vsp-sub{font-size:12px;color:var(--mut);margin-top:2px}
.vsp-nav{display:flex;flex-direction:column;gap:8px;margin-top:6px}
.vsp-nav button{all:unset;cursor:pointer;display:flex;align-items:center;gap:10px;
  padding:10px 12px;border-radius:14px;border:1px solid transparent;color:var(--txt)}
.vsp-nav button:hover{border-color:var(--line);background:rgba(148,163,184,.06)}
.vsp-nav button.active{border-color:var(--line);background:rgba(56,189,248,.08)}
.vsp-pill{margin-left:auto;font-size:11px;color:var(--mut)}
.vsp-main{flex:1;padding:18px 18px 26px 18px}
.vsp-top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:4px 0 12px 0}
.vsp-h1{font-size:18px;font-weight:800}
.vsp-actions{display:flex;gap:10px;align-items:center}
.vsp-btn{all:unset;cursor:pointer;padding:9px 12px;border-radius:12px;border:1px solid var(--line);
  background:rgba(148,163,184,.06);font-size:12px;font-weight:700}
.vsp-btn:hover{background:rgba(148,163,184,.10)}
.vsp-card{border:1px solid var(--line);background:var(--card);border-radius:16px;padding:14px;
  box-shadow:0 10px 24px rgba(0,0,0,.25)}
.vsp-grid{display:grid;gap:14px}
.vsp-grid-2{grid-template-columns: 1.3fr .7fr}
@media (max-width: 1100px){.vsp-grid-2{grid-template-columns:1fr}}
.vsp-kpi-grid{display:grid;gap:14px;grid-template-columns:repeat(4,minmax(180px,1fr));margin:14px 0}
@media (max-width: 1100px){.vsp-kpi-grid{grid-template-columns:repeat(2,minmax(180px,1fr));}}
@media (max-width: 640px){.vsp-kpi-grid{grid-template-columns:1fr;}}
.vsp-kpi{border:1px solid var(--line);background:rgba(2,6,23,.55);backdrop-filter:blur(6px);
  border-radius:16px;padding:14px;box-shadow:0 10px 24px rgba(0,0,0,.25)}
.vsp-kpi .k{font-size:12px;letter-spacing:.06em;text-transform:uppercase;opacity:.78;margin-bottom:6px}
.vsp-kpi .v{font-size:22px;font-weight:800;line-height:1.2}
.vsp-kpi .s{font-size:12px;opacity:.78;margin-top:6px;color:var(--mut)}

.vsp-badge{display:inline-flex;align-items:center;gap:8px;padding:6px 10px;border-radius:999px;
  font-size:12px;font-weight:800;letter-spacing:.04em;border:1px solid var(--line)}
.vsp-dot{width:8px;height:8px;border-radius:999px;display:inline-block}
.vsp-badge-green{background:rgba(34,197,94,.12)}
.vsp-badge-amber{background:rgba(245,158,11,.12)}
.vsp-badge-red{background:rgba(239,68,68,.12)}
.vsp-badge-muted{background:rgba(148,163,184,.10)}
.vsp-dot-green{background:rgb(34,197,94)}
.vsp-dot-amber{background:rgb(245,158,11)}
.vsp-dot-red{background:rgb(239,68,68)}
.vsp-dot-muted{background:rgb(148,163,184)}

table{width:100%;border-collapse:separate;border-spacing:0 8px}
thead th{font-size:12px;color:var(--mut);text-align:left;padding:0 10px}
tbody tr{background:rgba(148,163,184,.06);border:1px solid var(--line)}
tbody td{padding:10px 10px;font-size:13px}
tbody tr td:first-child{border-top-left-radius:14px;border-bottom-left-radius:14px}
tbody tr td:last-child{border-top-right-radius:14px;border-bottom-right-radius:14px}
.vsp-mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
.vsp-muted{color:var(--mut)}
.vsp-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.vsp-select{all:unset;border:1px solid var(--line);background:rgba(148,163,184,.06);
  padding:8px 10px;border-radius:12px;font-size:12px}
CSS

# -----------------------------
# 2) HTML template
# -----------------------------
cat > templates/vsp_4tabs_commercial_v1.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>VSP 2025 – Commercial UI (4 Tabs)</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="/static/css/vsp_ui_4tabs_commercial_v1.css">
</head>
<body>
  <div class="vsp-shell">
    <aside class="vsp-side">
      <div class="vsp-brand">
        <div class="vsp-logo"></div>
        <div>
          <div class="vsp-title">VersaSecure Platform</div>
          <div class="vsp-sub">VSP 2025 • UI gateway 8910</div>
        </div>
      </div>

      <nav class="vsp-nav" id="nav">
        <button data-tab="dashboard" class="active">
          Dashboard <span class="vsp-pill" id="pill-overall">…</span>
        </button>
        <button data-tab="runs">
          Runs &amp; Reports <span class="vsp-pill" id="pill-runs">…</span>
        </button>
        <button data-tab="settings">
          Settings <span class="vsp-pill">env</span>
        </button>
        <button data-tab="data">
          Data Source <span class="vsp-pill" id="pill-art">…</span>
        </button>
      </nav>

      <div style="margin-top:16px" class="vsp-muted">
        <div style="font-size:12px;line-height:1.5">
          Route: <span class="vsp-mono">/vsp4</span><br/>
          API: <span class="vsp-mono">/api/vsp/run_status_v2</span>
        </div>
      </div>
    </aside>

    <main class="vsp-main">
      <div class="vsp-top">
        <div class="vsp-h1" id="page-title">Dashboard</div>
        <div class="vsp-actions">
          <select id="run-picker" class="vsp-select"></select>
          <button class="vsp-btn" id="btn-refresh">Refresh</button>
          <a class="vsp-btn" href="/" title="Back to legacy UI">Legacy UI</a>
        </div>
      </div>

      <!-- DASHBOARD -->
      <section id="tab-dashboard">
        <div id="vsp-kpis-commercial">
          <!-- reuse KPI contract from your previous bind script (same id) -->
          <div class="vsp-kpi-grid">
            <div class="vsp-kpi"><div class="k">Overall Verdict</div><div class="v" id="kpi-overall">…</div><div class="s" id="kpi-overall-sub"></div></div>
            <div class="vsp-kpi"><div class="k">Gate Overall</div><div class="v" id="kpi-gate">…</div><div class="s" id="kpi-gate-sub"></div></div>
            <div class="vsp-kpi"><div class="k">Gitleaks</div><div class="v" id="kpi-gitleaks">…</div><div class="s" id="kpi-gitleaks-sub"></div></div>
            <div class="vsp-kpi"><div class="k">CodeQL</div><div class="v" id="kpi-codeql">…</div><div class="s" id="kpi-codeql-sub"></div></div>
          </div>
        </div>

        <div class="vsp-grid vsp-grid-2">
          <div class="vsp-card">
            <div class="vsp-row" style="justify-content:space-between">
              <div style="font-weight:800">Gate Summary</div>
              <div class="vsp-muted" id="gate-ts">…</div>
            </div>
            <div id="gate-bytool" style="margin-top:10px"></div>
          </div>

          <div class="vsp-card">
            <div style="font-weight:800;margin-bottom:8px">Run Meta</div>
            <div class="vsp-muted" style="font-size:12px;line-height:1.6" id="run-meta">…</div>
          </div>
        </div>
      </section>

      <!-- RUNS -->
      <section id="tab-runs" style="display:none">
        <div class="vsp-card">
          <div class="vsp-row" style="justify-content:space-between;margin-bottom:8px">
            <div style="font-weight:800">Runs (latest 20)</div>
            <div class="vsp-muted" style="font-size:12px">badges: overall + degraded_n</div>
          </div>
          <div style="overflow:auto">
            <table>
              <thead>
                <tr>
                  <th>Run ID</th>
                  <th>Overall</th>
                  <th>Gate</th>
                  <th>Gitleaks</th>
                  <th>CodeQL</th>
                  <th>Degraded</th>
                </tr>
              </thead>
              <tbody id="runs-tbody"></tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- SETTINGS -->
      <section id="tab-settings" style="display:none">
        <div class="vsp-card">
          <div style="font-weight:800;margin-bottom:8px">Settings (UI-side)</div>
          <div class="vsp-muted" style="font-size:12px;line-height:1.6">
            Đây là placeholder “commercial”: UI hiển thị các toggle/timeout. Hiện tại chưa nối backend settings write,
            nên các toggle sẽ lưu LocalStorage. Khi bạn làm backend settings route, chỉ cần bind vào đây.
          </div>

          <div class="vsp-grid" style="margin-top:12px">
            <div class="vsp-row">
              <span class="vsp-badge vsp-badge-muted"><span class="vsp-dot vsp-dot-muted"></span>ENABLE_CODEQL</span>
              <select id="set-enable-codeql" class="vsp-select">
                <option value="1">ON</option>
                <option value="0">OFF</option>
              </select>

              <span class="vsp-badge vsp-badge-muted"><span class="vsp-dot vsp-dot-muted"></span>TIMEOUT_CODEQL</span>
              <input id="set-timeout-codeql" class="vsp-select vsp-mono" value="3600s"/>

              <span class="vsp-badge vsp-badge-muted"><span class="vsp-dot vsp-dot-muted"></span>TIMEOUT_KICS</span>
              <input id="set-timeout-kics" class="vsp-select vsp-mono" value="1800s"/>
            </div>

            <div class="vsp-card" style="padding:12px">
              <div style="font-weight:800;margin-bottom:6px">Hardening proof</div>
              <div class="vsp-muted" style="font-size:12px;line-height:1.6" id="hardening-proof">
                • KICS: docker <span class="vsp-mono">--pull=never</span> enforced<br/>
                • KICS image digest: (optional) set env <span class="vsp-mono">VSP_KICS_IMAGE=checkmarx/kics@sha256:...</span><br/>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- DATA SOURCE -->
      <section id="tab-data" style="display:none">
        <div class="vsp-card">
          <div class="vsp-row" style="justify-content:space-between;margin-bottom:8px">
            <div style="font-weight:800">Artifacts index (selected run)</div>
            <div class="vsp-muted" style="font-size:12px" id="art-count">…</div>
          </div>
          <div id="art-list" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>
        </div>
      </section>
    </main>
  </div>

  <script defer src="/static/js/vsp_ui_4tabs_commercial_v1.js"></script>
</body>
</html>
HTML

# -----------------------------
# 3) JS (data binding)
# -----------------------------
cat > static/js/vsp_ui_4tabs_commercial_v1.js <<'JS'
/* === VSP_UI_4TABS_COMMERCIAL_V1 === */
(function(){
  const API = {
    runsIndex: "/api/vsp/runs_index_v3_fs_resolved?limit=20&hide_empty=0&filter=1",
    statusV2: (rid) => `/api/vsp/run_status_v2/${encodeURIComponent(rid)}`,
    artIndex: (rid) => `/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`
  };

  const $ = (s, r=document) => r.querySelector(s);
  const $all = (s, r=document) => Array.from(r.querySelectorAll(s));

  async function fetchJSON(url){
    const r = await fetch(url, {headers: {"Accept":"application/json"}});
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }

  function normRid(runId){
    if (!runId) return "";
    runId = String(runId).trim();
    if (runId.startsWith("RUN_")) return runId;
    if (runId.startsWith("VSP_CI_")) return "RUN_" + runId;
    return runId;
  }

  function badge(verdict, label){
    const v = (verdict||"").toUpperCase();
    let cls="vsp-badge-muted", dot="vsp-dot-muted", text=v||"N/A";
    if (v==="GREEN"){cls="vsp-badge-green";dot="vsp-dot-green";}
    else if (v==="AMBER"||v==="YELLOW"){cls="vsp-badge-amber";dot="vsp-dot-amber";text="AMBER";}
    else if (v==="RED"){cls="vsp-badge-red";dot="vsp-dot-red";}
    else if (v==="DISABLED"||v==="NOT_RUN"||v==="DEGRADED"){cls="vsp-badge-muted";dot="vsp-dot-muted";text=v;}
    return `<span class="vsp-badge ${cls}" title="${label||""}"><span class="vsp-dot ${dot}"></span>${text}</span>`;
  }

  function setHTML(id, html){ const el=document.getElementById(id); if (el) el.innerHTML=html; }
  function setText(id, txt){ const el=document.getElementById(id); if (el) el.textContent=txt; }

  function tabSwitch(name){
    const tabs = ["dashboard","runs","settings","data"];
    tabs.forEach(t=>{
      const sec = document.getElementById(`tab-${t}`);
      if (sec) sec.style.display = (t===name) ? "" : "none";
    });
    $all("#nav button").forEach(b=>b.classList.toggle("active", b.dataset.tab===name));
    const titleMap = {dashboard:"Dashboard", runs:"Runs & Reports", settings:"Settings", data:"Data Source"};
    setText("page-title", titleMap[name] || "VSP");
  }

  function renderGateByTool(s){
    const rg = s.run_gate_summary || {};
    const bt = rg.by_tool || {};
    const rows = Object.keys(bt).sort().map(k=>{
      const o = bt[k]||{};
      const v = o.verdict || "N/A";
      const total = o.total ?? 0;
      return `<div class="vsp-row" style="margin:8px 0">
        <div style="min-width:92px;font-weight:800">${k}</div>
        <div>${badge(v, k)}</div>
        <div class="vsp-muted">total: <span class="vsp-mono">${total}</span></div>
      </div>`;
    }).join("");
    $("#gate-bytool").innerHTML = rows || `<div class="vsp-muted">No gate summary</div>`;
    setText("gate-ts", rg.ts ? `ts: ${rg.ts}` : "ts: -");
  }

  function updateKpis(s){
    const overall = s.overall_verdict || s.overall || (s.run_gate_summary && s.run_gate_summary.overall) || "N/A";
    const gateOverall = (s.run_gate_summary && (s.run_gate_summary.overall_verdict || s.run_gate_summary.overall)) || overall || "N/A";

    const glV = s.gitleaks_verdict || "NOT_RUN";
    const glT = Number(s.gitleaks_total || 0);

    let cqV = s.codeql_verdict || (s.has_codeql ? "AMBER" : "DISABLED");
    let cqT = Number(s.codeql_total || 0);
    if (!s.has_codeql && (cqV==="GREEN"||cqV==="AMBER"||cqV==="RED")) cqV="DISABLED";

    setHTML("kpi-overall", badge(overall,"status_v2.overall_verdict"));
    setText("kpi-overall-sub", s.rid_norm ? `RID: ${s.rid_norm}` : "");
    setHTML("kpi-gate", badge(gateOverall,"run_gate_summary.overall"));
    setText("kpi-gate-sub", s.run_gate_summary && s.run_gate_summary.ts ? `ts: ${s.run_gate_summary.ts}` : "");
    setHTML("kpi-gitleaks", badge(glV,"gitleaks_verdict"));
    setText("kpi-gitleaks-sub", `total: ${glT}`);
    setHTML("kpi-codeql", badge(cqV,"codeql_verdict"));
    setText("kpi-codeql-sub", `total: ${cqT}`);

    setHTML("pill-overall", badge(overall));
  }

  function updateMeta(s){
    const lines = [
      `rid: ${s.rid || "-"}`,
      `rid_norm: ${s.rid_norm || "-"}`,
      `ci_run_dir: ${s.ci_run_dir || "-"}`,
      `status: ${s.status || "-"}`,
      `stage: ${s.stage_name || "-"}`,
      `degraded_n: ${s.degraded_n ?? (Array.isArray(s.degraded_tools) ? s.degraded_tools.length : 0)}`
    ];
    $("#run-meta").textContent = lines.join("\n");
  }

  async function renderArtifacts(rid){
    try{
      const j = await fetchJSON(API.artIndex(rid));
      const items = j.items || j.artifacts || j.files || [];
      setText("art-count", `count: ${items.length}`);
      $("#pill-art").textContent = String(items.length);
      $("#art-list").textContent = items.slice(0,300).map(x=>{
        if (typeof x === "string") return x;
        return x.path || x.name || JSON.stringify(x);
      }).join("\n");
    }catch(e){
      setText("art-count", "count: -");
      $("#art-list").textContent = String(e);
    }
  }

  async function loadRuns(){
    const idx = await fetchJSON(API.runsIndex);
    const items = idx.items || idx.runs || idx.data || [];
    $("#pill-runs").textContent = String(items.length || 0);

    // build picker
    const optHtml = items.map(it=>{
      const runId = it.run_id || it.id || it.rid || it.rid_norm || it.name || "";
      const rid = normRid(runId);
      return `<option value="${rid}">${rid}</option>`;
    }).join("");
    $("#run-picker").innerHTML = optHtml || `<option value="">(no runs)</option>`;

    // build runs table (with status_v2)
    const tbody = $("#runs-tbody");
    tbody.innerHTML = "";
    for (const it of items.slice(0,20)){
      const runId = it.run_id || it.id || it.rid || it.rid_norm || it.name || "";
      const rid = normRid(runId);
      if (!rid.startsWith("RUN_")) continue;

      let s = null;
      try { s = await fetchJSON(API.statusV2(rid)); } catch(e){ s = null; }

      const overall = s ? (s.overall_verdict || (s.run_gate_summary && s.run_gate_summary.overall) || "N/A") : "N/A";
      const gate = s && s.run_gate_summary ? (s.run_gate_summary.overall || "N/A") : "N/A";
      const glV = s ? (s.gitleaks_verdict || "NOT_RUN") : "N/A";
      const cqV = s ? (s.codeql_verdict || (s.has_codeql ? "AMBER" : "DISABLED")) : "N/A";
      const deg = s ? (s.degraded_n ?? (Array.isArray(s.degraded_tools)?s.degraded_tools.length:0)) : "-";

      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td class="vsp-mono">${rid}</td>
        <td>${badge(overall)}</td>
        <td>${badge(gate)}</td>
        <td>${badge(glV)} <span class="vsp-muted">(t=${Number((s&&s.gitleaks_total)||0)})</span></td>
        <td>${badge(cqV)} <span class="vsp-muted">(t=${Number((s&&s.codeql_total)||0)})</span></td>
        <td class="vsp-mono">${deg}</td>
      `;
      tr.style.cursor="pointer";
      tr.addEventListener("click", async ()=>{
        $("#run-picker").value = rid;
        await loadOne(rid);
        tabSwitch("dashboard");
      });
      tbody.appendChild(tr);
    }
  }

  async function loadOne(rid){
    if (!rid) return;
    let s = null;
    try { s = await fetchJSON(API.statusV2(rid)); } catch(e){ s = null; }
    if (!s){
      setText("run-meta", "cannot load status_v2");
      return;
    }
    updateKpis(s);
    renderGateByTool(s);
    updateMeta(s);
    await renderArtifacts(rid);
  }

  function loadSettingsUi(){
    const key = (k)=>`vsp_ui_set_${k}`;
    const enable = localStorage.getItem(key("ENABLE_CODEQL")) ?? "1";
    const tCodeql = localStorage.getItem(key("TIMEOUT_CODEQL")) ?? "3600s";
    const tKics = localStorage.getItem(key("TIMEOUT_KICS")) ?? "1800s";
    $("#set-enable-codeql").value = enable;
    $("#set-timeout-codeql").value = tCodeql;
    $("#set-timeout-kics").value = tKics;

    $("#set-enable-codeql").addEventListener("change", ()=>localStorage.setItem(key("ENABLE_CODEQL"), $("#set-enable-codeql").value));
    $("#set-timeout-codeql").addEventListener("change", ()=>localStorage.setItem(key("TIMEOUT_CODEQL"), $("#set-timeout-codeql").value));
    $("#set-timeout-kics").addEventListener("change", ()=>localStorage.setItem(key("TIMEOUT_KICS"), $("#set-timeout-kics").value));
  }

  function bootNav(){
    $all("#nav button").forEach(b=>{
      b.addEventListener("click", ()=>{
        tabSwitch(b.dataset.tab);
      });
    });
    $("#btn-refresh").addEventListener("click", async ()=>{
      await loadRuns();
      const rid = $("#run-picker").value;
      if (rid) await loadOne(rid);
    });
    $("#run-picker").addEventListener("change", async ()=>{
      const rid = $("#run-picker").value;
      if (rid) await loadOne(rid);
    });
  }

  async function boot(){
    bootNav();
    loadSettingsUi();
    await loadRuns();
    const rid = $("#run-picker").value;
    if (rid) await loadOne(rid);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
JS

# -----------------------------
# 4) Add route /vsp4 in vsp_demo_app.py (safe append)
# -----------------------------
FPATH="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["FPATH"])
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_UI_4TABS_ROUTE_V1 ==="
if TAG in t:
    print("[SKIP] route already added")
    raise SystemExit(0)

# ensure render_template imported
if "render_template" not in t:
    print("[WARN] cannot confirm render_template import; route may fail if missing")

route_block = r'''
# === VSP_UI_4TABS_ROUTE_V1 ===
try:
    from flask import render_template
except Exception:
    render_template = None

@app.route("/vsp4")
def vsp_ui_4tabs_commercial_v1():
    if render_template is None:
        return "render_template missing", 500
    return render_template("vsp_4tabs_commercial_v1.html")
'''
p.write_text(t + "\n\n" + route_block + "\n", encoding="utf-8")
print("[OK] appended /vsp4 route")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== SMOKE =="
curl -sS -o /dev/null -w "GET /vsp4 HTTP=%{http_code}\n" http://127.0.0.1:8910/vsp4
echo "[OK] open: http://127.0.0.1:8910/vsp4"
