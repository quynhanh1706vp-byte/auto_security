#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) write JS v2 (high z-index + re-mount if removed)
JS="static/js/vsp_dashboard_kpi_toolstrip_v2.js"
mkdir -p "$(dirname "$JS")"
cat > "$JS" <<'JS'
/* VSP_DASHBOARD_KPI_TOOLSTRIP_V2 */
(() => {
  if (window.__vsp_dashboard_kpi_toolstrip_v2) return;
  window.__vsp_dashboard_kpi_toolstrip_v2 = true;

  const TOOL_ORDER = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const SEV_ORDER  = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  const $ = (sel, root=document) => root.querySelector(sel);

  async function getJson(url, timeoutMs=12000){
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal:c.signal, credentials:"same-origin"});
      if (!r.ok) throw new Error("HTTP "+r.status);
      return await r.json();
    } finally { clearTimeout(t); }
  }

  function pillClass(v){
    const x = String(v||"").toUpperCase();
    if (x.includes("GREEN") || x==="OK" || x==="PASS") return "ok";
    if (x.includes("AMBER") || x==="WARN") return "warn";
    if (x.includes("RED") || x==="FAIL" || x==="BLOCK") return "bad";
    return "muted";
  }

  function ensureStyles(){
    if ($("#vspDashKpiStyleV2")) return;
    const st = document.createElement("style");
    st.id = "vspDashKpiStyleV2";
    st.textContent = `
      /* keep dark-enterprise visible even if page background is weird */
      #vspDashKpiRootV2{ position:relative; z-index: 5000; padding: 14px; color: rgba(255,255,255,0.92); }
      #vspDashKpiRootV2 .vsp-grid{ display:grid; gap:12px; }
      #vspDashKpiRootV2 .vsp-grid.kpi{ grid-template-columns: repeat(6, minmax(120px, 1fr)); }
      #vspDashKpiRootV2 .vsp-card{
        border:1px solid rgba(255,255,255,0.10);
        background: rgba(12,16,22,0.66);
        border-radius: 14px;
        padding: 12px 12px;
        box-shadow: 0 6px 18px rgba(0,0,0,0.22);
      }
      #vspDashKpiRootV2 .vsp-kpi-title{ font-size:12px; opacity:0.85; letter-spacing:0.2px; }
      #vspDashKpiRootV2 .vsp-kpi-val{ font-size:22px; font-weight:700; margin-top:6px; }
      #vspDashKpiRootV2 .vsp-row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      #vspDashKpiRootV2 .vsp-tool{ display:flex; align-items:center; gap:8px; padding:8px 10px; border-radius: 12px;
        border:1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.03); font-size:12px;
      }
      #vspDashKpiRootV2 .vsp-pill{ padding:2px 10px; border-radius:999px; border:1px solid rgba(255,255,255,0.14);
        background: rgba(255,255,255,0.05); font-size:12px;
      }
      #vspDashKpiRootV2 .vsp-pill.ok{ border-color: rgba(40,200,120,0.55); }
      #vspDashKpiRootV2 .vsp-pill.warn{ border-color: rgba(240,180,40,0.65); }
      #vspDashKpiRootV2 .vsp-pill.bad{ border-color: rgba(240,80,80,0.65); }
      #vspDashKpiRootV2 .vsp-pill.muted{ opacity:0.75; }
      #vspDashKpiRootV2 .vsp-title{ font-size:14px; font-weight:700; letter-spacing:0.2px; }
      #vspDashKpiRootV2 .vsp-sub{ font-size:12px; opacity:0.8; margin-top:4px; }
      #vspDashKpiRootV2 .vsp-two{ display:grid; gap:12px; grid-template-columns: 1.3fr 1fr; }
      #vspDashKpiRootV2 .vsp-mono{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; }
      @media (max-width: 1100px){
        #vspDashKpiRootV2 .vsp-grid.kpi{ grid-template-columns: repeat(3, minmax(120px, 1fr)); }
        #vspDashKpiRootV2 .vsp-two{ grid-template-columns: 1fr; }
      }
    `;
    document.head.appendChild(st);
  }

  function mount(){
    if (!String(location.pathname).includes("/vsp5")) return null;
    ensureStyles();

    let host = document.getElementById("vspDashKpiRootV2");
    if (host) return host;

    host = document.createElement("div");
    host.id = "vspDashKpiRootV2";

    // Prefer place right under topbar; else at body top
    const topbar = $(".vsp-topbar");
    if (topbar && topbar.parentNode){
      topbar.parentNode.insertBefore(host, topbar.nextSibling);
    } else {
      document.body.insertBefore(host, document.body.firstChild);
    }
    return host;
  }

  function renderSkeleton(host){
    host.innerHTML = `
      <div class="vsp-two">
        <div class="vsp-card">
          <div class="vsp-title">Gate summary</div>
          <div class="vsp-sub">Commercial KPI panel (V2)</div>
          <div style="height:8px"></div>
          <div class="vsp-row">
            <span class="vsp-pill muted" id="vspDashVerdictV2">…</span>
            <span class="vsp-pill muted vsp-mono" id="vspDashRidV2">RID: …</span>
            <span class="vsp-pill muted vsp-mono" id="vspDashTsV2">TS: …</span>
          </div>
        </div>

        <div class="vsp-card">
          <div class="vsp-title">Tools</div>
          <div class="vsp-sub">8-tool strip (missing shows N/A)</div>
          <div style="height:8px"></div>
          <div class="vsp-row" id="vspToolStripV2"></div>
        </div>
      </div>

      <div style="height:12px"></div>

      <div class="vsp-card">
        <div class="vsp-title">Findings KPI</div>
        <div class="vsp-sub">From reports/run_gate_summary.json → counts_total</div>
        <div style="height:10px"></div>
        <div class="vsp-grid kpi" id="vspKpiGridV2"></div>
      </div>
    `;

    const strip = $("#vspToolStripV2", host);
    strip.innerHTML = TOOL_ORDER.map(t => `
      <div class="vsp-tool">
        <span class="vsp-pill muted">${t}</span>
        <span class="vsp-pill muted">N/A</span>
      </div>
    `).join("");

    const grid = $("#vspKpiGridV2", host);
    grid.innerHTML = SEV_ORDER.map(s => `
      <div class="vsp-card" style="padding:12px">
        <div class="vsp-kpi-title">${s}</div>
        <div class="vsp-kpi-val">…</div>
      </div>
    `).join("");
  }

  function setText(host, id, v){
    const el = document.getElementById(id);
    if (el && host.contains(el)) el.textContent = v;
  }
  function setPill(host, id, text, klass){
    const el = document.getElementById(id);
    if (!el || !host.contains(el)) return;
    el.textContent = text;
    el.classList.remove("ok","warn","bad","muted");
    el.classList.add(klass || "muted");
  }

  function render(host, rid, summary){
    const overall = String(summary?.overall || "UNKNOWN").toUpperCase();
    setPill(host, "vspDashVerdictV2", overall, pillClass(overall));
    setText(host, "vspDashRidV2", `RID: ${rid || "N/A"}`);
    setText(host, "vspDashTsV2", `TS: ${(summary && summary.ts) ? summary.ts : "N/A"}`);

    const counts = summary?.counts_total || {};
    const grid = $("#vspKpiGridV2", host);
    grid.innerHTML = SEV_ORDER.map(sev => {
      const val = (counts && (sev in counts)) ? counts[sev] : 0;
      return `
        <div class="vsp-card" style="padding:12px">
          <div class="vsp-kpi-title">${sev}</div>
          <div class="vsp-kpi-val">${Number(val||0)}</div>
        </div>
      `;
    }).join("");

    const byTool = summary?.by_tool || {};
    const strip = $("#vspToolStripV2", host);
    strip.innerHTML = TOOL_ORDER.map(t => {
      const o = byTool?.[t] || null;
      const verdict = o?.verdict ? String(o.verdict).toUpperCase() : "N/A";
      const klass = verdict === "N/A" ? "muted" : pillClass(verdict);
      const tot = (o && typeof o.total !== "undefined") ? `total:${o.total}` : "";
      return `
        <div class="vsp-tool">
          <span class="vsp-pill muted">${t}</span>
          <span class="vsp-pill ${klass}">${verdict}</span>
          <span style="opacity:0.75" class="vsp-mono">${tot}</span>
        </div>
      `;
    }).join("");
  }

  async function loadOnce(){
    const host = mount();
    if (!host) return;
    renderSkeleton(host);

    let rid = null;
    try{
      const runs = await getJson("/api/vsp/runs?limit=1", 12000);
      rid = runs?.items?.[0]?.run_id || null;
    }catch(_){}

    if (!rid){
      setPill(host, "vspDashVerdictV2", "UNKNOWN", "muted");
      setText(host, "vspDashRidV2", "RID: N/A");
      return;
    }

    try{
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`, 15000);
      render(host, rid, summary);
    }catch(_){
      setPill(host, "vspDashVerdictV2", "UNKNOWN", "muted");
      setText(host, "vspDashRidV2", `RID: ${rid}`);
    }
  }

  function armRemount(){
    // if other scripts wipe DOM, re-add our panel
    const mo = new MutationObserver(() => {
      if (!String(location.pathname).includes("/vsp5")) return;
      const host = document.getElementById("vspDashKpiRootV2");
      if (!host) {
        // delay a bit so we re-mount after other renderer
        setTimeout(loadOnce, 120);
      }
    });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  }

  function start(){
    // let other dashboard scripts render first, then we overlay
    setTimeout(loadOnce, 250);
    armRemount();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
JS
echo "[OK] wrote $JS"

# 2) patch templates to use v2 include (remove v1 include to avoid double)
python3 - <<'PY'
from pathlib import Path
import re, time
ts=time.strftime("%Y%m%d_%H%M%S")

targets=[Path("templates/vsp_5tabs_enterprise_v2.html"), Path("templates/vsp_dashboard_2025.html")]
new_tag='<script src="/static/js/vsp_dashboard_kpi_toolstrip_v2.js?v={{ asset_v }}"></script>'

for p in targets:
  if not p.exists():
    print("[WARN] missing:", p); continue
  s=p.read_text(encoding="utf-8", errors="replace")
  bak=p.with_name(p.name+f".bak_dash_kpi_v2_{ts}")
  bak.write_text(s, encoding="utf-8")

  # drop old include if present
  s2=re.sub(r'\s*<script[^>]+vsp_dashboard_kpi_toolstrip_v1\.js[^>]*></script>\s*', "\n", s, flags=re.I)
  if "vsp_dashboard_kpi_toolstrip_v2.js" not in s2:
    if "</body>" in s2:
      s2=s2.replace("</body>", f"  {new_tag}\n</body>", 1)
    else:
      s2 += "\n" + new_tag + "\n"

  p.write_text(s2, encoding="utf-8")
  print("[OK] patched:", p, "backup:", bak)
PY

echo "[DONE] dashboard KPI/tool strip v2 applied."
