#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_extras_p1_v3_${TS}" && echo "[BACKUP] $F.bak_kpi_extras_p1_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASH_KPI_FROM_EXTRAS_P1_V3"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r'''
  // === VSP_DASH_KPI_FROM_EXTRAS_P1_V3 ===
  function _vsp_normRid(x){
    try{
      x = (x||"").toString().trim();
      x = re.sub(r'^\s*RUN[_\-]+', '', x, flags=re.I)
      x = re.sub(r'^\s*RID[:\s]+', '', x, flags=re.I)
      return x.strip()
    except Exception:
      return (x||"").toString().trim()
  }
  function _vsp_getRidBestEffort(){
    try{
      // 1) preferred: shared RID state (router)
      const st = (window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || null);
      if(st && (st.rid || st.run_id)) return _vsp_normRid(st.rid || st.run_id);

      // 2) header text "RID: xxx"
      const el = document.querySelector('[data-vsp-rid], #vsp-rid, #rid, #rid-current, .vsp-rid, .rid');
      if(el && el.textContent) return _vsp_normRid(el.textContent);

      // 3) any element containing "RID:"
      const cand = Array.from(document.querySelectorAll('body *'))
        .slice(0, 2000)
        .find(n => n && n.textContent && n.textContent.includes("RID:"));
      if(cand) return _vsp_normRid(cand.textContent);

    }catch(_){}
    return "";
  }
  function _vsp_setText(id, v){
    try{
      const el = document.getElementById(id);
      if(!el) return false;
      el.textContent = (v===0) ? "0" : (v ? String(v) : "–");
      return true;
    }catch(_){}
    return false;
  }
  async function _vsp_fetchExtras(rid){
    try{
      if(!rid) return null;
      const u = `/api/vsp/dashboard_v3_extras_v1?rid=${encodeURIComponent(rid)}`;
      const r = await fetch(u, {cache:"no-store"});
      if(!r.ok) return null;
      const j = await r.json();
      if(j && j.ok) return j;
    }catch(_){}
    return null;
  }
  function _vsp_fillKpiFromExtras(ex){
    if(!ex || !ex.kpi) return;
    const k = ex.kpi || {};
    const byTool = ex.by_tool || {};
    const bySev  = ex.by_sev || {};

    // --- 4tabs commercial KPIs (ids exist in template) ---
    _vsp_setText("kpi-overall", k.total ?? 0);
    _vsp_setText("kpi-overall-sub", `eff ${k.effective??0} / degr ${k.degraded??0}`);
    _vsp_setText("kpi-gate", k.score ?? "–");
    _vsp_setText("kpi-gate-sub", `unknown ${k.unknown_count??0}`);

    _vsp_setText("kpi-gitleaks", byTool.get("GITLEAKS", 0) if hasattr(byTool,"get") else (byTool.GITLEAKS ?? 0));
    _vsp_setText("kpi-gitleaks-sub", "GITLEAKS");
    _vsp_setText("kpi-codeql", byTool.get("CODEQL", 0) if hasattr(byTool,"get") else (byTool.CODEQL ?? 0));
    _vsp_setText("kpi-codeql-sub", "CODEQL");

    // --- dashboard_2025 ids (if present) ---
    _vsp_setText("kpi-total", k.total ?? 0);
    _vsp_setText("kpi-critical", bySev.get("CRITICAL",0) if hasattr(bySev,"get") else (bySev.CRITICAL ?? 0));
    _vsp_setText("kpi-high", bySev.get("HIGH",0) if hasattr(bySev,"get") else (bySev.HIGH ?? 0));
    _vsp_setText("kpi-medium", bySev.get("MEDIUM",0) if hasattr(bySev,"get") else (bySev.MEDIUM ?? 0));
    _vsp_setText("kpi-low", bySev.get("LOW",0) if hasattr(bySev,"get") else (bySev.LOW ?? 0));
    _vsp_setText("kpi-infotrace", bySev.get("INFO",0) if hasattr(bySev,"get") else (bySev.INFO ?? 0));
  }
  async function _vsp_tryHydrateDashKpi(){
    const rid = _vsp_getRidBestEffort();
    if(!rid) return;
    const ex = await _vsp_fetchExtras(rid);
    if(ex) _vsp_fillKpiFromExtras(ex);
  }
  function _vsp_scheduleDashKpi(){
    // run now + after navigation
    setTimeout(() => { _vsp_tryHydrateDashKpi(); }, 50);
    setTimeout(() => { _vsp_tryHydrateDashKpi(); }, 500);
    setTimeout(() => { _vsp_tryHydrateDashKpi(); }, 1500);
  }
  window.addEventListener("hashchange", _vsp_scheduleDashKpi);
  window.addEventListener("DOMContentLoaded", _vsp_scheduleDashKpi);
'''

# inject right after 'use strict';
if "'use strict';" in s and marker not in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
else:
    # fallback: prepend inside IIFE
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected dashboard KPI hydrate from dashboard_v3_extras_v1")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
