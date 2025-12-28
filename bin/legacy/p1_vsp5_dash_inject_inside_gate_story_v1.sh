#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_dash_inject_${TS}"
echo "[BACKUP] ${JS}.bak_dash_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASH_INJECT_INSIDE_GATE_STORY_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P0_DASH_INJECT_INSIDE_GATE_STORY_V1
   - Runs in /vsp5 even when HTML is minimal
   - Forces tool-truth: mutate /api/vsp/runs json so pickers land on rid_latest_gate_root
   - Injects KPI + Audit panels under Gate Story bar
*/
(()=> {
  try{
    if (window.__vsp_p0_dash_inject_gate_story_v1) return;
    window.__vsp_p0_dash_inject_gate_story_v1 = true;

    const isDash = ()=> (location && location.pathname && location.pathname.indexOf("/vsp5") === 0);
    if (!isDash()) return;

    // --- Global fetch hook (works even if bundle not loaded) ---
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch && !window.__vsp_p0_runs_fetch_hooked_in_gate_v1){
      window.__vsp_p0_runs_fetch_hooked_in_gate_v1 = true;
      window.fetch = async (input, init) => {
        const res = await _fetch(input, init);
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && url.indexOf("/api/vsp/runs") !== -1 && res && res.ok && typeof res.json === "function"){
            const _json = res.json.bind(res);
            res.json = async () => {
              const j = await _json();
              try{
                if (j && j.rid_latest_gate_root){
                  j.__vsp_gate_root = j.rid_latest_gate_root;
                  j.rid_last_good = j.rid_latest_gate_root;
                  j.rid_latest    = j.rid_latest_gate_root;
                  console.log("[VSP][runs_hook@gate] prefer gate_root:", j.rid_latest_gate_root);
                }
              }catch(e){}
              return j;
            };
          }
        }catch(e){}
        return res;
      };
      console.log("[VSP][runs_hook@gate] installed");
    }

    // --- UI inject shell ---
    const $ = (id)=> document.getElementById(id);
    const setText = (id, v)=> { const el=$(id); if(el) el.textContent = (v==null? "—": String(v)); };

    async function fetchJSON(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) throw new Error("http "+r.status+" "+url);
      return await r.json();
    }
    async function probeText(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) return { ok:false, status:r.status, size:0 };
      const t = await r.text();
      return { ok: !!t && t.length>1, status:200, size:(t||"").length };
    }

    function ensureShell(){
      if ($("vsp_dash_p1_wrap")) return true;
      if (!document.body) return false;

      const wrap = document.createElement("div");
      wrap.id = "vsp_dash_p1_wrap";
      wrap.style.padding = "14px 14px 10px 14px";
      wrap.innerHTML = `
        <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;">
          <div style="min-width:260px;">
            <div style="font-size:18px;font-weight:700;letter-spacing:.2px;">VSP • Dashboard</div>
            <div style="opacity:.78;font-size:12px;margin-top:4px;">
              Tool truth (gate_root): <span id="vsp_dash_gate_root" style="font-family:ui-monospace,monospace;">—</span>
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
            <div style="margin-top:6px;opacity:.75;font-size:12px;">Degraded: <span id="vsp_dash_degraded">—</span></div>
          </div>

          <div style="grid-column:span 3;min-width:220px;" class="vsp_card">
            <div style="opacity:.75;font-size:12px;">Findings (counts)</div>
            <div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:8px;">
              <span class="vsp_pill" id="vsp_dash_c_critical">CRIT: —</span>
              <span class="vsp_pill" id="vsp_dash_c_high">HIGH: —</span>
              <span class="vsp_pill" id="vsp_dash_c_medium">MED: —</span>
              <span class="vsp_pill" id="vsp_dash_c_low">LOW: —</span>
              <span class="vsp_pill" id="vsp_dash_c_info">INFO: —</span>
              <span class="vsp_pill" id="vsp_dash_c_trace">TRACE: —</span>
            </div>
          </div>

          <div style="grid-column:span 6;min-width:320px;" class="vsp_card">
            <div style="opacity:.75;font-size:12px;">Evidence &amp; Audit Readiness</div>
            <div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;" id="vsp_dash_audit_pills"></div>
            <div style="margin-top:8px;opacity:.75;font-size:12px;">Status: <span id="vsp_dash_audit_status" class="vsp_pill">—</span></div>
          </div>
        </div>

        <style>
          .vsp_card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);}
          .vsp_btn{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:8px 10px;border-radius:12px;font-size:12px;opacity:.9}
          .vsp_btn:hover{opacity:1;filter:brightness(1.08)}
          .vsp_pill{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:6px 8px;border-radius:999px;font-size:12px}
        </style>
      `;

      // chèn sau gate story header (an toàn): insert as first child of body
      document.body.insertBefore(wrap, document.body.children[1] || null);
      return true;
    }

    async function render(){
      if (!ensureShell()) return;

      const meta = await fetchJSON("/api/vsp/runs?_ts=" + Date.now());
      const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!rid) return;

      setText("vsp_dash_gate_root", rid);
      setText("vsp_dash_updated_at", new Date().toLocaleString());

      const aZip = $("vsp_dash_export_zip"), aPdf = $("vsp_dash_export_pdf");
      if (aZip) aZip.href = `/api/vsp/run_export_zip?rid=${encodeURIComponent(rid)}`;
      if (aPdf) aPdf.href = `/api/vsp/run_export_pdf?rid=${encodeURIComponent(rid)}`;

      // gate summary
      let sum = null;
      try{
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json&_ts=${Date.now()}`);
      }catch(e){
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json&_ts=${Date.now()}`);
      }

      const overall = (sum?.overall_status || sum?.overall || sum?.status || "—").toString().toUpperCase();
      setText("vsp_dash_overall", overall);
      setText("vsp_dash_degraded", (sum?.degraded!=null)? sum.degraded : "—");

      const c = sum?.counts_by_severity || sum?.by_severity || sum?.severity_counts || sum?.summary?.counts_by_severity || {};
      setText("vsp_dash_c_critical", `CRIT: ${Number(c.CRITICAL||0)||0}`);
      setText("vsp_dash_c_high",     `HIGH: ${Number(c.HIGH||0)||0}`);
      setText("vsp_dash_c_medium",   `MED: ${Number(c.MEDIUM||0)||0}`);
      setText("vsp_dash_c_low",      `LOW: ${Number(c.LOW||0)||0}`);
      setText("vsp_dash_c_info",     `INFO: ${Number(c.INFO||0)||0}`);
      setText("vsp_dash_c_trace",    `TRACE: ${Number(c.TRACE||0)||0}`);

      // audit pills
      const pills = $("vsp_dash_audit_pills");
      if (pills) pills.innerHTML = "";
      const req = [
        "run_manifest.json","run_evidence_index.json","run_gate.json","run_gate_summary.json",
        "findings_unified.json","reports/findings_unified.csv","reports/findings_unified.sarif",
      ];
      let okAll = true;
      for (const f of req){
        const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(f)}&_ts=${Date.now()}`;
        const r = await probeText(u);
        if (!r.ok) okAll = false;
        if (pills){
          const sp = document.createElement("span");
          sp.className="vsp_pill";
          sp.style.borderColor = r.ok ? "rgba(80,220,140,.28)" : "rgba(255,72,72,.28)";
          sp.style.background  = r.ok ? "rgba(80,220,140,.10)" : "rgba(255,72,72,.10)";
          sp.textContent = `${f}${r.ok?"":" ✗"}`;
          pills.appendChild(sp);
        }
      }
      const st = $("vsp_dash_audit_status");
      if (st) st.textContent = okAll ? "AUDIT READY" : "MISSING EVIDENCE";

      console.log("[VSP][Dash@gate] rendered rid=", rid, "overall=", overall);
    }

    const kick = ()=> render().catch(e=>console.warn("[VSP][Dash@gate] render err", e));
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ()=> setTimeout(kick, 200));
    else setTimeout(kick, 200);

    // refresh nhẹ
    setInterval(()=> {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      setText("vsp_dash_updated_at", new Date().toLocaleString());
    }, 15000);

  }catch(e){
    console.warn("[VSP][Dash@gate] init failed", e);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended dash inject block into gate_story js")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Open /vsp5 and HARD reload (Ctrl+Shift+R). Expect console: [VSP][runs_hook@gate] installed"
