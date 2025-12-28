#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"

TPLS=(
  "templates/vsp_dashboard_2025.html"
  "templates/vsp_5tabs_enterprise_v2.html"
)

JS="static/js/vsp_bundle_commercial_v2.js"

for t in "${TPLS[@]}"; do
  if [ -f "$t" ]; then
    cp -f "$t" "${t}.bak_dash_kpi_${TS}"
    echo "[BACKUP] ${t}.bak_dash_kpi_${TS}"
  fi
done

cp -f "$JS" "${JS}.bak_dash_kpi_${TS}"
echo "[BACKUP] ${JS}.bak_dash_kpi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK_TPL = "VSP_P1_DASHBOARD_COMMERCIAL_LAYOUT_V1"
MARK_JS  = "VSP_P1_DASHBOARD_KPI_RENDER_V1"

tpl_candidates = [
  Path("templates/vsp_dashboard_2025.html"),
  Path("templates/vsp_5tabs_enterprise_v2.html"),
]
js = Path("static/js/vsp_bundle_commercial_v2.js")

def patch_template(p: Path) -> bool:
  if not p.exists(): return False
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK_TPL in s:
    print(f"[SKIP] tpl already patched: {p}")
    return True

  # Only patch if this template looks like it serves Dashboard (/vsp5) content
  # We patch safely: insert a dashboard KPI shell near top of <body>.
  if "<body" not in s.lower():
    print(f"[WARN] tpl no <body>: {p}")
    return False

  dash_shell = r"""
<!-- VSP_P1_DASHBOARD_COMMERCIAL_LAYOUT_V1 -->
<div id="vsp_dash_p1_wrap" style="padding:14px 14px 10px 14px;">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;">
    <div style="min-width:260px;">
      <div style="font-size:18px;font-weight:700;letter-spacing:.2px;">VSP • Dashboard</div>
      <div style="opacity:.78;font-size:12px;margin-top:4px;">
        Tool truth (gate_root): <span id="vsp_dash_gate_root" style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;">—</span>
        • Updated: <span id="vsp_dash_updated_at">—</span>
      </div>
    </div>

    <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;justify-content:flex-end;">
      <a class="vsp_btn" href="/runs" style="text-decoration:none;">Runs &amp; Reports</a>
      <a class="vsp_btn" href="/data_source" style="text-decoration:none;">Data Source</a>
      <a class="vsp_btn" href="/settings" style="text-decoration:none;">Settings</a>
      <a class="vsp_btn" href="/rule_overrides" style="text-decoration:none;">Rule Overrides</a>
      <span style="width:1px;height:22px;background:rgba(255,255,255,.10);display:inline-block;"></span>
      <a class="vsp_btn" id="vsp_dash_export_zip" href="#" style="text-decoration:none;">Export ZIP</a>
      <a class="vsp_btn" id="vsp_dash_export_pdf" href="#" style="text-decoration:none;">Export PDF</a>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:repeat(12, 1fr);gap:10px;margin-top:12px;">
    <div style="grid-column:span 3;min-width:220px;" class="vsp_card">
      <div style="opacity:.75;font-size:12px;">Overall</div>
      <div id="vsp_dash_overall" style="margin-top:6px;font-size:20px;font-weight:800;">—</div>
      <div style="margin-top:6px;opacity:.75;font-size:12px;">
        Degraded: <span id="vsp_dash_degraded">—</span>
      </div>
    </div>

    <div style="grid-column:span 3;min-width:220px;" class="vsp_card">
      <div style="opacity:.75;font-size:12px;">Findings (counts)</div>
      <div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:8px;">
        <span class="vsp_pill" id="vsp_dash_c_critical">CRIT: —</span>
        <span class="vsp_pill" id="vsp_dash_c_high">HIGH: —</span>
        <span class="vsp_pill" id="vsp_dash_c_medium">MED: —</span>
        <span class="vsp_pill" id="vsp_dash_c_low">LOW: —</span>
      </div>
      <div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:8px;">
        <span class="vsp_pill" id="vsp_dash_c_info">INFO: —</span>
        <span class="vsp_pill" id="vsp_dash_c_trace">TRACE: —</span>
      </div>
    </div>

    <div style="grid-column:span 6;min-width:320px;" class="vsp_card">
      <div style="opacity:.75;font-size:12px;display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;">
        <span>Severity bar</span>
        <span style="opacity:.75">RID: <span id="vsp_dash_rid_short" style="font-family:ui-monospace, monospace;">—</span></span>
      </div>
      <div id="vsp_dash_sev_bar" style="margin-top:10px;display:flex;gap:8px;align-items:flex-end;min-height:44px;"></div>
      <div style="opacity:.7;font-size:12px;margin-top:8px;">
        Tip: Dashboard auto-reloads when gate_root changes (tool truth).
      </div>
    </div>
  </div>
</div>

<style>
/* small helpers, safe even if css already exists */
.vsp_card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);}
.vsp_btn{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:8px 10px;border-radius:12px;font-size:12px;opacity:.9}
.vsp_btn:hover{opacity:1;filter:brightness(1.08)}
.vsp_pill{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:6px 8px;border-radius:999px;font-size:12px}
</style>
<!-- /VSP_P1_DASHBOARD_COMMERCIAL_LAYOUT_V1 -->
"""

  # insert after <body...> open tag
  s2, n = re.subn(r'(<body[^>]*>)', r'\1\n' + dash_shell, s, count=1, flags=re.I)
  if n == 0:
    print(f"[WARN] tpl insert failed (no body tag): {p}")
    return False

  p.write_text(s2, encoding="utf-8")
  print(f"[OK] tpl patched: {p}")
  return True

def patch_js(p: Path) -> bool:
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK_JS in s:
    print("[SKIP] js already patched")
    return True

  block = r"""
/* VSP_P1_DASHBOARD_KPI_RENDER_V1 */
(()=> {
  try{
    if (window.__vsp_p1_dashboard_kpi_v1) return;
    window.__vsp_p1_dashboard_kpi_v1 = true;

    const $ = (id)=> document.getElementById(id);
    function setText(id, v){ const el=$(id); if(el) el.textContent = (v==null? "—": String(v)); }
    function safeInt(x){ const n = Number(x); return Number.isFinite(n) ? n : 0; }

    async function fetchJSON(url){
      const res = await fetch(url, { cache:"no-store" });
      if(!res.ok) throw new Error("http " + res.status + " for " + url);
      return await res.json();
    }

    function pickGateRoot(meta){
      return (meta && (meta.rid_latest_gate_root || meta.rid_latest || meta.rid_last_good || meta.rid_latest_findings)) || "";
    }

    function normalizeCounts(j){
      // best-effort across variants
      const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      const candidates = [
        j?.counts_by_severity,
        j?.by_severity,
        j?.severity_counts,
        j?.severity,
        j?.summary?.counts_by_severity,
        j?.summary?.by_severity,
      ];
      for (const c of candidates){
        if (!c || typeof c !== "object") continue;
        for (const k of Object.keys(out)){
          if (c[k] != null) out[k] = safeInt(c[k]);
        }
      }
      // sometimes nested like {critical:..} lowercase
      const lc = j?.counts || j?.by_sev || j?.sev || null;
      if (lc && typeof lc === "object"){
        const map = {critical:"CRITICAL", high:"HIGH", medium:"MEDIUM", low:"LOW", info:"INFO", trace:"TRACE"};
        for (const kk of Object.keys(map)){
          if (lc[kk] != null) out[map[kk]] = safeInt(lc[kk]);
        }
      }
      return out;
    }

    function normalizeOverall(j){
      // prefer explicit overall_status / overall
      const x = (j?.overall_status || j?.overall || j?.status || "").toString().toUpperCase();
      if (["RED","AMBER","GREEN"].includes(x)) return x;
      // sometimes PASS/FAIL
      if (x.includes("FAIL")) return "RED";
      if (x.includes("WARN") || x.includes("AMBER")) return "AMBER";
      if (x.includes("PASS") || x.includes("GREEN")) return "GREEN";
      return x || "—";
    }

    function normalizeDegraded(j){
      // accept different shapes
      const d = j?.degraded;
      if (typeof d === "number") return d;
      if (typeof d === "string" && d.match(/^\d+\/\d+$/)) return d;
      const by = j?.by_tool || j?.tools || j?.by_type || null;
      if (by && typeof by === "object"){
        let total=0, deg=0;
        for (const k of Object.keys(by)){
          total++;
          const v = by[k];
          if (v && (v.degraded === true || v.status === "DEGRADED")) deg++;
        }
        if (total>0) return `${deg}/${total}`;
      }
      return "—";
    }

    function renderBar(counts){
      const el = $("vsp_dash_sev_bar");
      if (!el) return;
      el.innerHTML = "";
      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const max = Math.max(1, ...order.map(k=>counts[k]||0));
      for (const k of order){
        const v = counts[k]||0;
        const h = Math.round((v/max)*38) + 6; // 6..44
        const col = document.createElement("div");
        col.style.flex = "1";
        col.style.minWidth = "34px";
        col.style.display = "flex";
        col.style.flexDirection = "column";
        col.style.alignItems = "center";
        const bar = document.createElement("div");
        bar.style.width = "100%";
        bar.style.height = h + "px";
        bar.style.borderRadius = "10px";
        bar.style.border = "1px solid rgba(255,255,255,.10)";
        bar.style.background = "rgba(255,255,255,.06)";
        const lab = document.createElement("div");
        lab.style.marginTop = "6px";
        lab.style.fontSize = "11px";
        lab.style.opacity = ".78";
        lab.textContent = `${k.replace("MEDIUM","MED")}:${v}`;
        col.appendChild(bar);
        col.appendChild(lab);
        el.appendChild(col);
      }
    }

    function paintOverall(overall){
      const el = $("vsp_dash_overall");
      if (!el) return;
      el.textContent = overall || "—";
      el.style.padding = "4px 10px";
      el.style.borderRadius = "999px";
      el.style.display = "inline-block";
      el.style.border = "1px solid rgba(255,255,255,.12)";
      let bg = "rgba(255,255,255,.05)";
      if (overall === "RED") bg = "rgba(255, 72, 72, .18)";
      if (overall === "AMBER") bg = "rgba(255, 190, 64, .18)";
      if (overall === "GREEN") bg = "rgba(80, 220, 140, .16)";
      el.style.background = bg;
    }

    function wireExports(rid){
      const aZip = $("vsp_dash_export_zip");
      const aPdf = $("vsp_dash_export_pdf");
      if (aZip) aZip.href = `/api/vsp/run_export_zip?rid=${encodeURIComponent(rid)}`;
      if (aPdf) aPdf.href = `/api/vsp/run_export_pdf?rid=${encodeURIComponent(rid)}`;
    }

    async function main(){
      // Only if dashboard shell exists
      if (!$("vsp_dash_p1_wrap")) return;

      const meta = await fetchJSON("/api/vsp/runs?_ts=" + Date.now());
      const gateRoot = pickGateRoot(meta);
      if (!gateRoot){
        console.warn("[VSP][DashKPI] no gate_root from /api/vsp/runs");
        return;
      }

      setText("vsp_dash_gate_root", gateRoot);
      setText("vsp_dash_rid_short", gateRoot.slice(0, 24));
      setText("vsp_dash_updated_at", new Date().toLocaleString());
      wireExports(gateRoot);

      // Prefer run_gate_summary.json (fast & normalized); fallback to run_gate.json
      let sum = null;
      try{
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(gateRoot)}&path=run_gate_summary.json&_ts=${Date.now()}`);
      }catch(e1){
        console.warn("[VSP][DashKPI] run_gate_summary fetch failed; fallback run_gate.json", e1);
        try{
          sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(gateRoot)}&path=run_gate.json&_ts=${Date.now()}`);
        }catch(e2){
          console.warn("[VSP][DashKPI] run_gate.json fetch failed", e2);
          return;
        }
      }

      const overall = normalizeOverall(sum);
      const degraded = normalizeDegraded(sum);
      const counts = normalizeCounts(sum);

      paintOverall(overall);
      setText("vsp_dash_degraded", degraded);

      setText("vsp_dash_c_critical", `CRIT: ${counts.CRITICAL}`);
      setText("vsp_dash_c_high",     `HIGH: ${counts.HIGH}`);
      setText("vsp_dash_c_medium",   `MED: ${counts.MEDIUM}`);
      setText("vsp_dash_c_low",      `LOW: ${counts.LOW}`);
      setText("vsp_dash_c_info",     `INFO: ${counts.INFO}`);
      setText("vsp_dash_c_trace",    `TRACE: ${counts.TRACE}`);

      renderBar(counts);

      console.log("[VSP][DashKPI] rendered from gate_root:", gateRoot, "overall:", overall, "degraded:", degraded);
    }

    // Run once + refresh lightweight (không reload) để cập nhật timestamp / trạng thái nếu backend update
    main();
    setInterval(()=> {
      if ($("vsp_dash_p1_wrap")) setText("vsp_dash_updated_at", new Date().toLocaleString());
    }, 15000);

  }catch(e){
    console.warn("[VSP][DashKPI] init failed", e);
  }
})();
"""

  p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
  print("[OK] js appended KPI renderer")
  return True

ok_tpl = 0
for t in tpl_candidates:
  if patch_template(t): ok_tpl += 1

if ok_tpl == 0:
  print("[WARN] no templates patched (dashboard template not found?). Still patched JS only.")

patch_js(js)
PY

echo "== node --check bundle =="
node --check static/js/vsp_bundle_commercial_v2.js
echo "[OK] syntax OK"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== HEAD /vsp5 =="
curl -sS -I "$BASE/vsp5" | sed -n '1,12p'
echo "[OK] Open $BASE/vsp5 -> should see KPI cards + console [VSP][DashKPI]"
