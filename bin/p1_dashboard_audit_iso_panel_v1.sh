#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_audit_iso_${TS}"
echo "[BACKUP] ${JS}.bak_audit_iso_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASH_AUDIT_ISO_PANEL_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_DASH_AUDIT_ISO_PANEL_V1 */
(()=> {
  try{
    if (window.__vsp_p1_dash_audit_iso_v1) return;
    window.__vsp_p1_dash_audit_iso_v1 = true;

    const $ = (id)=> document.getElementById(id);

    function pill(text, ok){
      const el = document.createElement("span");
      el.className = "vsp_pill";
      el.style.borderColor = ok ? "rgba(80,220,140,.28)" : "rgba(255,72,72,.28)";
      el.style.background = ok ? "rgba(80,220,140,.10)" : "rgba(255,72,72,.10)";
      el.textContent = text;
      return el;
    }

    function badge(text){
      const el = document.createElement("span");
      el.className = "vsp_pill";
      el.style.background = "rgba(255,255,255,.04)";
      el.style.borderColor = "rgba(255,255,255,.10)";
      el.textContent = text;
      return el;
    }

    async function fetchJSON(url){
      const res = await fetch(url, { cache:"no-store" });
      if (!res.ok) throw new Error("http " + res.status + " " + url);
      return await res.json();
    }

    async function probeFile(rid, path){
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}&_ts=${Date.now()}`;
      try{
        const res = await fetch(url, { cache:"no-store" });
        if (!res.ok) return { ok:false, status:res.status };
        // best-effort: read small text to ensure non-empty
        const txt = await res.text();
        if (!txt || txt.length < 2) return { ok:false, status:200, empty:true };
        return { ok:true, status:200, size:txt.length, text:txt };
      }catch(e){
        return { ok:false, status:0, err:String(e) };
      }
    }

    function ensurePanel(){
      const wrap = $("vsp_dash_p1_wrap");
      if (!wrap) return null;

      // find the KPI grid we already inserted
      const grid = wrap.querySelector("div[style*='grid-template-columns']");
      if (!grid) return null;

      if ($("vsp_dash_audit_card")) return grid;

      const card = document.createElement("div");
      card.id = "vsp_dash_audit_card";
      card.className = "vsp_card";
      card.style.gridColumn = "span 12";
      card.style.minWidth = "320px";

      card.innerHTML = `
        <div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:center;">
          <div style="opacity:.82;font-size:12px;">Evidence &amp; Audit Readiness</div>
          <div style="opacity:.75;font-size:12px;">
            Status: <span id="vsp_dash_audit_status" class="vsp_pill">—</span>
          </div>
        </div>
        <div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;" id="vsp_dash_audit_pills"></div>

        <div style="margin-top:10px;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:flex-start;">
          <div style="min-width:280px;flex:1;">
            <div style="opacity:.75;font-size:12px;">ISO / DepSecOps hint</div>
            <div style="margin-top:6px;opacity:.9;font-size:12px;line-height:1.4" id="vsp_dash_iso_hint">—</div>
          </div>
          <div style="min-width:280px;flex:1;">
            <div style="opacity:.75;font-size:12px;">Tool lane (8 tools)</div>
            <div style="margin-top:6px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;" id="vsp_dash_tool_lane"></div>
          </div>
        </div>
      `;
      grid.appendChild(card);
      return grid;
    }

    function setAuditStatus(okAll, msg){
      const el = $("vsp_dash_audit_status");
      if (!el) return;
      el.textContent = msg || (okAll ? "AUDIT READY" : "MISSING EVIDENCE");
      el.style.borderColor = okAll ? "rgba(80,220,140,.28)" : "rgba(255,72,72,.28)";
      el.style.background = okAll ? "rgba(80,220,140,.10)" : "rgba(255,72,72,.10)";
    }

    function renderIsoHint(summary){
      const el = $("vsp_dash_iso_hint");
      if (!el) return;

      // best-effort: accept many shapes
      const iso = summary?.iso27001 || summary?.iso_map || summary?.iso || summary?.compliance || null;

      if (iso && typeof iso === "object"){
        const keys = Object.keys(iso);
        const sample = keys.slice(0,6).join(", ");
        el.textContent = `ISO mapping present (${keys.length} keys). Sample: ${sample}`;
      }else{
        // still “commercial”: explain what auditor expects
        el.textContent =
          "ISO mapping not found in run_gate_summary. Recommended: map each rule/tool finding to ISO 27001 controls and keep run_manifest + evidence_index for audit traceability.";
      }
    }

    function renderToolLane(summary){
      const lane = $("vsp_dash_tool_lane");
      if (!lane) return;
      lane.innerHTML = "";

      // try locate tool list
      const byTool = summary?.by_tool || summary?.tools || summary?.tool_status || summary?.summary?.by_tool || null;

      const prefer = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
      if (byTool && typeof byTool === "object"){
        for (const t of prefer){
          const v = byTool[t] || byTool[t.toLowerCase()] || null;
          const st = (v?.status || v?.state || v || "").toString().toUpperCase();
          const d  = (v?.degraded === true) || (st === "DEGRADED");
          const ok = st ? st : (d ? "DEGRADED" : "OK");
          const b = badge(`${t}:${ok}${d ? "*" : ""}`);
          if (d){
            b.style.borderColor = "rgba(255,190,64,.25)";
            b.style.background = "rgba(255,190,64,.10)";
          }
          lane.appendChild(b);
        }
        return;
      }

      // fallback: show fixed lane (commercial expectation)
      for (const t of prefer){
        lane.appendChild(badge(`${t}:—`));
      }
    }

    async function run(){
      if (!ensurePanel()) return;
      const gateEl = $("vsp_dash_gate_root");
      const rid = gateEl ? (gateEl.textContent || "").trim() : "";
      if (!rid || rid === "—") return;

      // probe evidence files (P0 audit set)
      const req = [
        "run_manifest.json",
        "run_evidence_index.json",
        "run_gate.json",
        "run_gate_summary.json",
        "findings_unified.json",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
      ];

      const pillsEl = $("vsp_dash_audit_pills");
      if (!pillsEl) return;
      pillsEl.innerHTML = "";

      let okAll = true;
      const results = {};
      for (const f of req){
        const r = await probeFile(rid, f);
        results[f] = r;
        if (!r.ok) okAll = false;
        pillsEl.appendChild(pill(`${f}${r.ok ? "" : " ✗"}`, r.ok));
      }
      setAuditStatus(okAll, okAll ? "AUDIT READY" : "MISSING EVIDENCE");

      // also render ISO/tool info using run_gate_summary (best-effort)
      let summary = null;
      try{
        summary = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json&_ts=${Date.now()}`);
      }catch(_e){
        try{
          summary = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json&_ts=${Date.now()}`);
        }catch(__e){
          summary = null;
        }
      }
      renderIsoHint(summary);
      renderToolLane(summary);

      console.log("[VSP][DashAuditISO] rid=", rid, "audit_ready=", okAll);
    }

    // kick once + periodic refresh
    setTimeout(run, 1400);
    setInterval(()=> {
      // only run when dashboard visible
      if (document.visibilityState && document.visibilityState !== "visible") return;
      run();
    }, 30000);

  }catch(e){
    console.warn("[VSP][DashAuditISO] init failed", e);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended audit/iso panel block")
PY

echo "== node --check bundle =="
node --check static/js/vsp_bundle_commercial_v2.js
echo "[OK] syntax OK"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke HEAD /vsp5 =="
curl -sS -I "$BASE/vsp5" | sed -n '1,12p'
echo "[OK] Open $BASE/vsp5 -> should see Evidence & Audit panel"
