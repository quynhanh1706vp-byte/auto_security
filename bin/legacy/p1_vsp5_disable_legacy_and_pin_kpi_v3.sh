#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Disable legacy dash/poller on /vsp5 (prevents <URL> fetch + DOM/canvas wipe)
LEG="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
if [ -f "$LEG" ]; then
  cp -f "$LEG" "${LEG}.bak_disable_legacy_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re, time
p=Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
# we wrapped earlier with VSP_FILLREAL_IIFE_WRAP_V1; inject guard right after "(() => {"
if "VSP_DISABLE_LEGACY_ON_VSP5_V1" in s:
    print("[OK] legacy guard already injected"); raise SystemExit(0)

m = re.search(r'\(\(\)\s*=>\s*\{\s*\n', s)
if not m:
    # fallback: just prepend guard safely
    guard = "/* VSP_DISABLE_LEGACY_ON_VSP5_V1 */\nif (String(location.pathname||'').includes('/vsp5')) { return; }\n"
    s2 = guard + s
else:
    guard = "/* VSP_DISABLE_LEGACY_ON_VSP5_V1 */\n  if (String(location.pathname||'').includes('/vsp5')) { return; }\n"
    s2 = s[:m.end()] + guard + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] injected legacy disable guard into:", p)
PY
else
  echo "[WARN] missing $LEG (skip legacy disable)"
fi

# 2) Write KPI/toolstrip v3 (fixed + highest z-index)
JS="static/js/vsp_dashboard_kpi_toolstrip_v3.js"
cat > "$JS" <<'JS'
/* VSP_DASHBOARD_KPI_TOOLSTRIP_V3_PINNED */
(() => {
  if (window.__vsp_dashboard_kpi_toolstrip_v3) return;
  window.__vsp_dashboard_kpi_toolstrip_v3 = true;

  const TOOL_ORDER = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
  const SEV_ORDER  = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
  const $ = (sel, root=document) => root.querySelector(sel);

  function pillClass(v){
    const x = String(v||"").toUpperCase();
    if (x.includes("GREEN") || x==="OK" || x==="PASS") return "ok";
    if (x.includes("AMBER") || x==="WARN") return "warn";
    if (x.includes("RED") || x==="FAIL" || x==="BLOCK") return "bad";
    return "muted";
  }

  async function getJson(url, timeoutMs=15000){
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal:c.signal, credentials:"same-origin"});
      if (!r.ok) throw new Error("HTTP "+r.status);
      return await r.json();
    } finally { clearTimeout(t); }
  }

  function ensureStyles(){
    if (document.getElementById("vspDashPinnedStyleV3")) return;
    const st = document.createElement("style");
    st.id = "vspDashPinnedStyleV3";
    st.textContent = `
      /* pin topbar on top of ANY overlay */
      .vsp-topbar{
        position: fixed !important;
        top:0; left:0; right:0;
        z-index: 2147483647 !important;
      }
      body{ padding-top: 56px !important; }

      /* pinned KPI panel */
      #vspDashKpiPinnedV3{
        position: fixed;
        top: 56px;
        left: 0;
        right: 0;
        z-index: 2147483646;
        padding: 12px 14px;
        pointer-events: none; /* panel doesn’t block page interactions */
      }
      #vspDashKpiPinnedV3 .inner{
        max-width: 1400px;
        margin: 0 auto;
        pointer-events: auto;
        color: rgba(255,255,255,0.92);
      }
      #vspDashKpiPinnedV3 .grid{ display:grid; gap:12px; }
      #vspDashKpiPinnedV3 .two{ display:grid; gap:12px; grid-template-columns: 1.25fr 1fr; }
      #vspDashKpiPinnedV3 .kpi{ grid-template-columns: repeat(6, minmax(110px, 1fr)); }
      #vspDashKpiPinnedV3 .card{
        border:1px solid rgba(255,255,255,0.10);
        background: rgba(12,16,22,0.70);
        border-radius: 14px;
        padding: 12px;
        box-shadow: 0 8px 20px rgba(0,0,0,0.25);
      }
      #vspDashKpiPinnedV3 .title{ font-size:14px; font-weight:700; }
      #vspDashKpiPinnedV3 .sub{ font-size:12px; opacity:0.8; margin-top:4px; }
      #vspDashKpiPinnedV3 .row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      #vspDashKpiPinnedV3 .mono{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; }

      #vspDashKpiPinnedV3 .pill{
        padding:2px 10px; border-radius:999px;
        border:1px solid rgba(255,255,255,0.14);
        background: rgba(255,255,255,0.05);
        font-size:12px;
      }
      #vspDashKpiPinnedV3 .pill.ok{ border-color: rgba(40,200,120,0.55); }
      #vspDashKpiPinnedV3 .pill.warn{ border-color: rgba(240,180,40,0.65); }
      #vspDashKpiPinnedV3 .pill.bad{ border-color: rgba(240,80,80,0.65); }
      #vspDashKpiPinnedV3 .pill.muted{ opacity:0.75; }

      #vspDashKpiPinnedV3 .tool{ display:flex; align-items:center; gap:8px; padding:8px 10px; border-radius: 12px;
        border:1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.03); font-size:12px;
      }
      #vspDashKpiPinnedV3 .kpiTitle{ font-size:12px; opacity:0.85; }
      #vspDashKpiPinnedV3 .kpiVal{ font-size:22px; font-weight:700; margin-top:6px; }

      @media (max-width: 1100px){
        #vspDashKpiPinnedV3 .two{ grid-template-columns: 1fr; }
        #vspDashKpiPinnedV3 .kpi{ grid-template-columns: repeat(3, minmax(110px, 1fr)); }
      }
    `;
    document.head.appendChild(st);
  }

  function mount(){
    if (!String(location.pathname||"").includes("/vsp5")) return null;
    ensureStyles();
    let host = document.getElementById("vspDashKpiPinnedV3");
    if (host) return host;

    host = document.createElement("div");
    host.id = "vspDashKpiPinnedV3";
    host.innerHTML = `
      <div class="inner">
        <div class="grid two">
          <div class="card">
            <div class="title">Gate summary</div>
            <div class="sub">Pinned commercial KPI (V3)</div>
            <div style="height:8px"></div>
            <div class="row">
              <span id="v3Verdict" class="pill muted">…</span>
              <span id="v3Rid" class="pill muted mono">RID: …</span>
              <span id="v3Ts" class="pill muted mono">TS: …</span>
            </div>
          </div>
          <div class="card">
            <div class="title">Tools</div>
            <div class="sub">8 tools, missing → N/A</div>
            <div style="height:8px"></div>
            <div class="row" id="v3Tools"></div>
          </div>
        </div>

        <div style="height:12px"></div>

        <div class="card">
          <div class="title">Findings KPI</div>
          <div class="sub">counts_total from run_gate_summary.json</div>
          <div style="height:10px"></div>
          <div class="grid kpi" id="v3Kpi"></div>
        </div>
      </div>
    `;
    document.body.appendChild(host);
    return host;
  }

  function setPill(id, text, klass){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.classList.remove("ok","warn","bad","muted");
    el.classList.add(klass || "muted");
  }
  function setText(id, v){
    const el = document.getElementById(id);
    if (el) el.textContent = v;
  }

  function render(rid, summary){
    const overall = String(summary?.overall || "UNKNOWN").toUpperCase();
    setPill("v3Verdict", overall, pillClass(overall));
    setText("v3Rid", `RID: ${rid || "N/A"}`);
    setText("v3Ts", `TS: ${summary?.ts || "N/A"}`);

    const counts = summary?.counts_total || {};
    const kpi = document.getElementById("v3Kpi");
    if (kpi){
      kpi.innerHTML = SEV_ORDER.map(sev => {
        const val = (sev in counts) ? counts[sev] : 0;
        return `<div class="card" style="padding:12px">
          <div class="kpiTitle">${sev}</div>
          <div class="kpiVal">${Number(val||0)}</div>
        </div>`;
      }).join("");
    }

    const byTool = summary?.by_tool || {};
    const tools = document.getElementById("v3Tools");
    if (tools){
      tools.innerHTML = TOOL_ORDER.map(t => {
        const o = byTool?.[t] || null;
        const verdict = o?.verdict ? String(o.verdict).toUpperCase() : "N/A";
        const klass = verdict === "N/A" ? "muted" : pillClass(verdict);
        const tot = (o && typeof o.total !== "undefined") ? `total:${o.total}` : "";
        return `<div class="tool">
          <span class="pill muted">${t}</span>
          <span class="pill ${klass}">${verdict}</span>
          <span class="mono" style="opacity:0.75">${tot}</span>
        </div>`;
      }).join("");
    }
  }

  async function main(){
    const host = mount();
    if (!host) return;

    // skeleton
    setPill("v3Verdict","…","muted");
    setText("v3Rid","RID: …");
    setText("v3Ts","TS: …");

    let rid = null;
    try{
      const runs = await getJson("/api/vsp/runs?limit=1", 12000);
      rid = runs?.items?.[0]?.run_id || null;
    }catch(_){}

    if (!rid){
      setPill("v3Verdict","UNKNOWN","muted");
      setText("v3Rid","RID: N/A");
      return;
    }

    try{
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`, 15000);
      render(rid, summary);
    }catch(_){
      setPill("v3Verdict","UNKNOWN","muted");
      setText("v3Rid",`RID: ${rid}`);
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => setTimeout(main, 250));
  else setTimeout(main, 250);
})();
JS
echo "[OK] wrote $JS"

# 3) Switch template include to v3 (drop v1/v2 include)
python3 - <<'PY'
from pathlib import Path
import re, time
ts=time.strftime("%Y%m%d_%H%M%S")
targets=[Path("templates/vsp_5tabs_enterprise_v2.html"), Path("templates/vsp_dashboard_2025.html")]
new_tag='<script src="/static/js/vsp_dashboard_kpi_toolstrip_v3.js?v={{ asset_v }}"></script>'

for p in targets:
  if not p.exists():
    print("[WARN] missing:", p); continue
  s=p.read_text(encoding="utf-8", errors="replace")
  bak=p.with_name(p.name+f".bak_dash_kpi_v3_{ts}")
  bak.write_text(s, encoding="utf-8")

  s2=re.sub(r'\s*<script[^>]+vsp_dashboard_kpi_toolstrip_v[12]\.js[^>]*></script>\s*', "\n", s, flags=re.I)
  if "vsp_dashboard_kpi_toolstrip_v3.js" not in s2:
    if "</body>" in s2:
      s2=s2.replace("</body>", f"  {new_tag}\n</body>", 1)
    else:
      s2 += "\n" + new_tag + "\n"

  p.write_text(s2, encoding="utf-8")
  print("[OK] patched:", p, "backup:", bak)
PY

echo "[DONE] v3 pinned KPI + legacy disable applied."
