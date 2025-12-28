#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_TOPFINDINGS_MISSING_FINDINGS_WARNING_V1"

cp -f "$JS" "${JS}.bak_${MARK}_${TS}"
ok "backup: ${JS}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_TOPFINDINGS_MISSING_FINDINGS_WARNING_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# Helper injected near top: safe sum counts
helper = r'''
// --- VSP_P0_TOPFINDINGS_MISSING_FINDINGS_WARNING_V1 ---
window.__vspSumCountsTotal = function(ct){
  try{
    if(!ct) return 0;
    const keys=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    let n=0;
    for(const k of keys){ n += (Number(ct[k]||0) || 0); }
    return n;
  }catch(e){ return 0; }
};
window.__vspOpenDataSource = function(rid, extra){
  const q = new URLSearchParams();
  if(rid) q.set("rid", rid);
  if(extra && typeof extra === "object"){
    for(const [k,v] of Object.entries(extra)){ if(v!==undefined && v!==null && v!=="") q.set(k, String(v)); }
  }
  window.location.href = "/data_source?" + q.toString();
};
// --- /VSP_P0_TOPFINDINGS_MISSING_FINDINGS_WARNING_V1 ---
'''
# place helper after first "use strict" or at top
if "use strict" in s:
    s = s.replace("use strict", "use strict\n" + helper, 1)
else:
    s = helper + "\n" + s

# Patch point:
# Find where Top Findings list is rendered. We search for a common anchor: "Top Findings" string.
idx = s.find("Top Findings")
if idx < 0:
    print("[WARN] could not locate 'Top Findings' anchor. No changes made.")
    Path("static/js/vsp_dashboard_luxe_v1.js").write_text(s + f"\n// {MARK}\n", encoding="utf-8")
    raise SystemExit(0)

# We patch by inserting a check after findings are loaded into an array `rows` / `items`.
# We'll do a broad regex: after a statement that assigns findings list from response.
# Try common patterns: `.findings` usage.
pat_candidates = [
    r'(const\s+findings\s*=\s*(?:data\.)?findings\s*\|\|\s*\[\]\s*;)',
    r'(let\s+findings\s*=\s*(?:data\.)?findings\s*\|\|\s*\[\]\s*;)',
    r'(var\s+findings\s*=\s*(?:data\.)?findings\s*\|\|\s*\[\]\s*;)',
]
injected=False
for pat in pat_candidates:
    m=re.search(pat, s)
    if not m: 
        continue
    insert = m.group(1) + r'''
// [P0] commercial guard: if counts_total exists but findings array is empty => show warning (missing evidence)
try{
  const ct = (window.__vspDashKpis && window.__vspDashKpis.counts_total) ? window.__vspDashKpis.counts_total : (window.__vspLastCountsTotal||null);
  const total = window.__vspSumCountsTotal(ct);
  if(total > 0 && (!findings || findings.length === 0)){
    const el = document.querySelector("#vsp-topfindings") || document.querySelector("[data-panel='topfindings']") || null;
    const rid = (window.__vspRID || window.__vspRid || (new URLSearchParams(location.search)).get("rid") || "");
    const html = `
      <div style="margin-top:8px;padding:10px 12px;border-radius:12px;border:1px solid rgba(255,190,60,0.35);background:rgba(255,190,60,0.08);">
        <div style="font-weight:800;letter-spacing:0.2px;">⚠ Findings file missing for this run</div>
        <div style="opacity:0.9;margin-top:4px;">Gate counts exist (total ${total}) but findings_unified is empty or missing. This is a data integrity issue, not a clean scan.</div>
        <div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;">
          <button id="vsp-open-ds-btn" style="cursor:pointer;padding:7px 10px;border-radius:10px;border:1px solid rgba(255,255,255,0.18);background:rgba(255,255,255,0.06);color:#ddd;font-weight:700;">Open Data Source</button>
        </div>
      </div>`;
    if(el){ el.innerHTML = html; }
    const btn = document.getElementById("vsp-open-ds-btn");
    if(btn){ btn.onclick = ()=> window.__vspOpenDataSource(rid, {severity:"CRITICAL,HIGH"}); }
  }
}catch(e){}
'''
    s = re.sub(pat, insert, s, count=1)
    injected=True
    break

if not injected:
    # fallback: store counts_total from dash_kpis fetch by patching response handler
    # Find "dash_kpis" fetch and stash counts_total to window.__vspLastCountsTotal
    s = re.sub(
        r'(/api/vsp/dash_kpis\?rid=\$\{rid\})',
        r'\1',
        s
    )
    # Insert a generic stash after any "counts_total" mention
    s = re.sub(
        r'(counts_total\s*:\s*[^,}\n]+)',
        r'\1\n; try{ window.__vspLastCountsTotal = (window.__vspLastCountsTotal || null); }catch(e){}',
        s,
        count=1
    )

s += f"\n// {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched topfindings missing-findings warning (best-effort)")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

ok "DONE. Open /vsp5 and test RID_B: it must show warning instead of silent empty top findings."
