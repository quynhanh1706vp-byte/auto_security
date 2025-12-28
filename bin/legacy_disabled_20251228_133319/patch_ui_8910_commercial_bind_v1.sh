#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# 1) write CSS
mkdir -p static/css static/js

cat > static/css/vsp_commercial_bind_v1.css <<'CSS'
/* === VSP_COMMERCIAL_BIND_V1 === */
.vsp-kpi-grid{display:grid;gap:14px;grid-template-columns:repeat(4,minmax(180px,1fr));margin:16px 0}
@media (max-width: 1100px){.vsp-kpi-grid{grid-template-columns:repeat(2,minmax(180px,1fr));}}
@media (max-width: 640px){.vsp-kpi-grid{grid-template-columns:1fr;}}
.vsp-kpi{border:1px solid rgba(148,163,184,.18);background:rgba(2,6,23,.55);backdrop-filter:blur(6px);
  border-radius:16px;padding:14px 14px 12px 14px;box-shadow:0 10px 24px rgba(0,0,0,.25)}
.vsp-kpi .k{font-size:12px;letter-spacing:.06em;text-transform:uppercase;opacity:.75;margin-bottom:6px}
.vsp-kpi .v{font-size:22px;font-weight:700;line-height:1.2}
.vsp-kpi .s{font-size:12px;opacity:.78;margin-top:6px}

.vsp-badge{display:inline-flex;align-items:center;gap:8px;padding:6px 10px;border-radius:999px;
  font-size:12px;font-weight:700;letter-spacing:.04em;border:1px solid rgba(148,163,184,.18)}
.vsp-dot{width:8px;height:8px;border-radius:999px;display:inline-block}

.vsp-badge-green{background:rgba(34,197,94,.12)}
.vsp-badge-amber{background:rgba(245,158,11,.12)}
.vsp-badge-red{background:rgba(239,68,68,.12)}
.vsp-badge-muted{background:rgba(148,163,184,.10)}

.vsp-dot-green{background:rgb(34,197,94)}
.vsp-dot-amber{background:rgb(245,158,11)}
.vsp-dot-red{background:rgb(239,68,68)}
.vsp-dot-muted{background:rgb(148,163,184)}
CSS

# 2) write JS
cat > static/js/vsp_commercial_bind_v1.js <<'JS'
/* === VSP_COMMERCIAL_BIND_V1 === */
(function () {
  const API = {
    runsIndex: "/api/vsp/runs_index_v3_fs_resolved?limit=20&hide_empty=0&filter=1",
    statusV2: (rid) => `/api/vsp/run_status_v2/${encodeURIComponent(rid)}`
  };

  function $(sel, root=document){ return root.querySelector(sel); }
  function $all(sel, root=document){ return Array.from(root.querySelectorAll(sel)); }

  async function fetchJSON(url) {
    const r = await fetch(url, { headers: { "Accept": "application/json" } });
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }

  function normRid(rid) {
    if (!rid) return "";
    rid = String(rid).trim();
    if (rid.startsWith("RUN_")) return rid;
    if (rid.startsWith("VSP_CI_")) return "RUN_" + rid;
    if (rid.startsWith("VSP_UIREQ_")) return rid; // status_v2 may not support uireq; ignore
    return rid.startsWith("RUN_") ? rid : rid;
  }

  function verdictBadge(verdict, label) {
    const v = (verdict || "").toUpperCase();
    let cls = "vsp-badge-muted", dot = "vsp-dot-muted", text = v || "N/A";
    if (v === "GREEN") { cls = "vsp-badge-green"; dot = "vsp-dot-green"; }
    else if (v === "AMBER" || v === "YELLOW") { cls = "vsp-badge-amber"; dot = "vsp-dot-amber"; text = "AMBER"; }
    else if (v === "RED") { cls = "vsp-badge-red"; dot = "vsp-dot-red"; }
    else if (v === "DISABLED" || v === "NOT_RUN" || v === "DEGRADED") { cls = "vsp-badge-muted"; dot = "vsp-dot-muted"; text = v; }

    return `
      <span class="vsp-badge ${cls}" title="${label || ""}">
        <span class="vsp-dot ${dot}"></span>
        ${text}
      </span>
    `;
  }

  function ensureKpiPanel() {
    if ($("#vsp-kpis-commercial")) return;

    const host =
      $("#main") ||
      $("main") ||
      $(".vsp-main") ||
      $(".content") ||
      $(".container") ||
      document.body;

    const wrap = document.createElement("div");
    wrap.id = "vsp-kpis-commercial";
    wrap.innerHTML = `
      <div class="vsp-kpi-grid">
        <div class="vsp-kpi">
          <div class="k">Overall Verdict</div>
          <div class="v" id="kpi-overall">…</div>
          <div class="s" id="kpi-overall-sub"></div>
        </div>
        <div class="vsp-kpi">
          <div class="k">Gate Overall</div>
          <div class="v" id="kpi-gate">…</div>
          <div class="s" id="kpi-gate-sub"></div>
        </div>
        <div class="vsp-kpi">
          <div class="k">Gitleaks</div>
          <div class="v" id="kpi-gitleaks">…</div>
          <div class="s" id="kpi-gitleaks-sub"></div>
        </div>
        <div class="vsp-kpi">
          <div class="k">CodeQL</div>
          <div class="v" id="kpi-codeql">…</div>
          <div class="s" id="kpi-codeql-sub"></div>
        </div>
      </div>
    `;
    host.insertBefore(wrap, host.firstChild);
  }

  function setText(id, txt){ const el = document.getElementById(id); if (el) el.textContent = txt; }
  function setHTML(id, html){ const el = document.getElementById(id); if (el) el.innerHTML = html; }

  async function loadLatestStatusV2() {
    const idx = await fetchJSON(API.runsIndex);
    const items = (idx && (idx.items || idx.runs || idx.data)) || [];
    const first = items[0] || null;
    const runId = first && (first.run_id || first.id || first.rid || first.rid_norm || first.name);
    const rid = normRid(runId);
    if (!rid || !rid.startsWith("RUN_")) return null;
    return await fetchJSON(API.statusV2(rid));
  }

  function updateKpis(s) {
    if (!s) return;

    const overall = s.overall_verdict || s.overall || (s.run_gate_summary && s.run_gate_summary.overall) || "N/A";
    const gateOverall = (s.run_gate_summary && (s.run_gate_summary.overall_verdict || s.run_gate_summary.overall)) || overall || "N/A";

    const glVerdict = s.gitleaks_verdict || "NOT_RUN";
    const glTotal = (typeof s.gitleaks_total === "number") ? s.gitleaks_total : (s.gitleaks_total ? Number(s.gitleaks_total) : 0);

    // CodeQL: if disabled/not present, show placeholder labels
    let cqVerdict = s.codeql_verdict || (s.has_codeql ? "AMBER" : "DISABLED");
    let cqTotal = (typeof s.codeql_total === "number") ? s.codeql_total : (s.codeql_total ? Number(s.codeql_total) : 0);
    if (!s.has_codeql && (cqVerdict === "AMBER" || cqVerdict === "GREEN" || cqVerdict === "RED")) cqVerdict = "DISABLED";

    setHTML("kpi-overall", verdictBadge(overall, "Overall verdict (status_v2)"));
    setText("kpi-overall-sub", s.ci_run_dir ? `CI: ${s.rid_norm || ""}` : "");

    setHTML("kpi-gate", verdictBadge(gateOverall, "Gate overall (run_gate_summary)"));
    setText("kpi-gate-sub", s.run_gate_summary && s.run_gate_summary.ts ? `ts: ${s.run_gate_summary.ts}` : "");

    setHTML("kpi-gitleaks", verdictBadge(glVerdict, "Gitleaks verdict"));
    setText("kpi-gitleaks-sub", `total: ${glTotal}`);

    setHTML("kpi-codeql", verdictBadge(cqVerdict, "CodeQL verdict"));
    setText("kpi-codeql-sub", `total: ${cqTotal}`);
  }

  async function enhanceRunsTable() {
    // best-effort: try to find a runs table
    const table = document.querySelector("table#runs_table, table.vsp-runs, table");
    if (!table) return;

    const rows = $all("tbody tr", table).slice(0, 20);
    if (!rows.length) return;

    // add header cols if possible
    const theadTr = table.querySelector("thead tr");
    if (theadTr && !theadTr.querySelector("[data-vsp-col='overall']")) {
      const th1 = document.createElement("th"); th1.textContent = "Overall"; th1.setAttribute("data-vsp-col","overall");
      const th2 = document.createElement("th"); th2.textContent = "Degraded"; th2.setAttribute("data-vsp-col","degraded");
      theadTr.appendChild(th1); theadTr.appendChild(th2);
    }

    for (const tr of rows) {
      const txt = tr.textContent || "";
      const m = txt.match(/VSP_CI_\d{8}_\d{6}/);
      if (!m) continue;
      const rid = normRid(m[0]);
      if (tr.querySelector("[data-vsp-cell='overall']")) continue;

      // placeholder cells
      const tdOverall = document.createElement("td"); tdOverall.setAttribute("data-vsp-cell","overall");
      tdOverall.innerHTML = verdictBadge("N/A","loading...");
      const tdDeg = document.createElement("td"); tdDeg.setAttribute("data-vsp-cell","degraded");
      tdDeg.textContent = "…";
      tr.appendChild(tdOverall);
      tr.appendChild(tdDeg);

      try {
        const s = await fetchJSON(API.statusV2(rid));
        const overall = s.overall_verdict || (s.run_gate_summary && s.run_gate_summary.overall) || "N/A";
        tdOverall.innerHTML = verdictBadge(overall, rid);
        tdDeg.textContent = String(s.degraded_n ?? (Array.isArray(s.degraded_tools) ? s.degraded_tools.length : 0));
      } catch (e) {
        tdOverall.innerHTML = verdictBadge("N/A", String(e));
        tdDeg.textContent = "-";
      }
    }
  }

  async function boot() {
    try {
      ensureKpiPanel();
      const s = await loadLatestStatusV2();
      updateKpis(s);
      enhanceRunsTable(); // best-effort
    } catch (e) {
      // keep UI stable even if API fails
      console.warn("[VSP_COMMERCIAL_BIND_V1]", e);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
JS

# 3) patch a base template to include CSS+JS
pick_tpl() {
  local cands=(
    "templates/vsp_5tabs_full.html"
    "templates/vsp_dashboard_2025.html"
    "templates/vsp_layout_sidebar.html"
    "templates/index.html"
    "templates/base.html"
  )
  for f in "${cands[@]}"; do
    if [ -f "$f" ]; then echo "$f"; return 0; fi
  done
  # fallback: first html in templates
  find templates -maxdepth 2 -type f -name '*.html' | sort | head -n1 || true
}

TPL="$(pick_tpl)"
[ -n "$TPL" ] || { echo "[ERR] cannot find templates/*.html"; exit 1; }
echo "[OK] template=$TPL"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_ui_bind_${TS}"
echo "[BACKUP] $TPL.bak_ui_bind_${TS}"

FPATH="$TPL" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["FPATH"])
t = p.read_text(encoding="utf-8", errors="ignore")

CSS_TAG = 'href="/static/css/vsp_commercial_bind_v1.css"'
JS_TAG  = 'src="/static/js/vsp_commercial_bind_v1.js"'

changed = False

# inject CSS before </head>
if CSS_TAG not in t:
    if "</head>" in t:
        t = t.replace("</head>", '  <link rel="stylesheet" '+CSS_TAG+'>\n</head>', 1)
        changed = True

# inject JS before </body>
if JS_TAG not in t:
    if "</body>" in t:
        t = t.replace("</body>", '  <script defer '+JS_TAG+'></script>\n</body>', 1)
        changed = True

if not changed:
    print("[SKIP] template already includes CSS/JS or missing head/body tags")
else:
    p.write_text(t, encoding="utf-8")
    print("[OK] injected CSS/JS into", p)
PY

python3 -m py_compile vsp_demo_app.py >/dev/null
rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== SMOKE =="
curl -sS http://127.0.0.1:8910/ | head -n 5 || true
echo "[OK] open UI: http://127.0.0.1:8910/"
