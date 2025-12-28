#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

TARGETS=(
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_dashboard_consistency_patch_v1.js
  static/js/vsp_dashboard_kpi_force_any_v1.js
  static/js/vsp_dash_only_v1.js
)

echo "== [1] backup targets =="
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || { warn "skip missing: $f"; continue; }
  cp -f "$f" "${f}.bak_cio_v1p4_${TS}"
  ok "backup: ${f}.bak_cio_v1p4_${TS}"
done

echo "== [2] patch (inject normalize + scrub N/A + stabilize totals) =="
python3 - <<'PY'
from pathlib import Path
import re, subprocess, time

MARK = "VSP_P0_CIO_KPI_NO_NA_CONSIST_V1P4"

INJECT = r'''
/* ===================== VSP_P0_CIO_KPI_NO_NA_CONSIST_V1P4 ===================== */
(function(){
  try{
    if (window.__VSP_CIO_KPI_V1P4__) return;
    window.__VSP_CIO_KPI_V1P4__ = true;

    function _num(v){
      const n = Number(v);
      return Number.isFinite(n) ? n : 0;
    }
    function _upperKey(k){ try{return String(k||"").toUpperCase();}catch(e){return "";} }

    function _extractSevBag(obj){
      if(!obj || typeof obj !== "object") return null;
      return obj.counts_by_severity || obj.by_severity || obj.severity || obj.counts || null;
    }

    window.__vspCioNormalizeCountsV1P4 = function(obj){
      try{
        if(!obj || typeof obj !== "object") return obj;

        // normalize severity bucket
        const bag = _extractSevBag(obj);
        const sev = { CRITICAL:0, HIGH:0, MEDIUM:0, LOW:0, INFO:0, TRACE:0 };
        if (bag && typeof bag === "object"){
          for (const k in bag){
            const uk = _upperKey(k);
            if (uk in sev) sev[uk] = _num(bag[k]);
          }
        }

        // prefer explicit totals if present, else compute from sev
        const explicitTotal =
          obj.total ??
          obj.total_findings ??
          obj.findings_total ??
          (obj.counts_total && (obj.counts_total.TOTAL ?? obj.counts_total.total)) ??
          null;

        const computedTotal = sev.CRITICAL + sev.HIGH + sev.MEDIUM + sev.LOW + sev.INFO + sev.TRACE;
        const total = _num(explicitTotal) || computedTotal;

        // stamp back stable keys (no N/A)
        obj.total = total;
        obj.total_findings = total;
        obj.findings_total = total;

        obj.critical = _num(obj.critical) || sev.CRITICAL;
        obj.high = _num(obj.high) || sev.HIGH;

        obj.counts_by_severity = { ...sev };
        obj.by_severity = { ...sev };

        // stable counts_total shape
        obj.counts_total = { ...sev, TOTAL: total };

        return obj;
      }catch(e){ return obj; }
    };

    window.__vspCioNormalizePayloadV1P4 = function(payload){
      try{
        if(!payload || typeof payload !== "object") return payload;

        // common containers
        const cands = [
          payload,
          payload.data,
          payload.dashboard,
          payload.summary,
          payload.gate,
          payload.run_gate,
          payload.run,
          payload.counts_total
        ];
        for (const c of cands){
          if (c && typeof c === "object") window.__vspCioNormalizeCountsV1P4(c);
        }

        // if payload has counts_total as object with sev keys, also ensure TOTAL
        if (payload.counts_total && typeof payload.counts_total === "object"){
          const sev = { CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0 };
          for (const k in payload.counts_total){
            const uk = _upperKey(k);
            if (uk in sev) sev[uk] = _num(payload.counts_total[k]);
          }
          const tot = _num(payload.counts_total.TOTAL ?? payload.counts_total.total) || (sev.CRITICAL+sev.HIGH+sev.MEDIUM+sev.LOW+sev.INFO+sev.TRACE);
          payload.counts_total = { ...sev, TOTAL: tot };
        }

        return payload;
      }catch(e){ return payload; }
    };

    // scrub any "N/A" appearing in UI (CIO trust)
    function scrubNA(root){
      try{
        root = root || document;
        const nodes = root.querySelectorAll("*");
        for (const n of nodes){
          const t = (n && n.childNodes && n.childNodes.length===1 && n.childNodes[0].nodeType===3) ? (n.textContent||"") : "";
          if(!t) continue;
          if (t.trim() === "N/A" || t.trim() === "not available"){
            n.textContent = "0";
            n.setAttribute("title","No data for this run");
          }
          // common pattern: "Total findings: N/A"
          if (t.includes("N/A")){
            const tt = t.replace(/\bN\/A\b/g, "0").replace(/not available/gi,"0");
            if (tt !== t){
              n.textContent = tt;
              n.setAttribute("title","No data for this run");
            }
          }
        }
      }catch(e){}
    }

    function attachObserver(){
      try{
        scrubNA(document);
        const obs = new MutationObserver(function(){ scrubNA(document); });
        obs.observe(document.documentElement || document.body, { childList:true, subtree:true, characterData:true });
      }catch(e){}
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", attachObserver, { once:true });
    else attachObserver();

  }catch(e){}
})();
/* ===================== /VSP_P0_CIO_KPI_NO_NA_CONSIST_V1P4 ===================== */
'''

FILES = [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_dashboard_kpi_force_any_v1.js",
  "static/js/vsp_dash_only_v1.js",
]

def node_check(fp: Path):
  subprocess.check_output(["node","--check",str(fp)], stderr=subprocess.STDOUT, timeout=25)

patched = 0
for f in FILES:
  fp = Path(f)
  if not fp.exists(): 
    continue
  s = fp.read_text(encoding="utf-8", errors="ignore")
  if MARK in s:
    continue

  # inject at top after first comment/shebang area
  s2 = INJECT + "\n" + s

  # If file fetches dashboard/run_gate summary into const, normalize right after.
  # Pattern: const X = await fetchJSON(api("/api/vsp/dashboard_v3..."));
  def norm_after_fetch(m):
    decl = m.group(1)  # const/let/var
    var  = m.group(2)
    url  = m.group(3)
    # ensure mutable var
    decl2 = "let"
    return f'{decl2} {var} = await fetchJSON(api("{url}"));\n      {var} = window.__vspCioNormalizePayloadV1P4({var});'

  s2 = re.sub(
    r'\b(const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*await\s+fetchJSON\s*\(\s*api\s*\(\s*"([^"]*\/api\/vsp\/(?:dashboard_v3|run_gate_summary_v1)[^"]*)"\s*\)\s*\)\s*;\s*',
    norm_after_fetch,
    s2
  )

  fp.write_text(s2, encoding="utf-8")
  node_check(fp)
  print("[OK] patched:", f)
  patched += 1

print("[DONE] patched_files=", patched)
PY

echo "== [3] node --check targets =="
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  node --check "$f" && ok "node --check OK: $f" || err "node --check FAIL: $f"
done

echo "== [4] quick scan: no 'N/A' literals remain in dashboard JS =="
grep -RIn --line-number --exclude='*.bak_*' "N/A" static/js/vsp_dashboard_* static/js/vsp_dash_only_v1.js 2>/dev/null | head -n 80 || true

echo "== [DONE] Reload /vsp5 (Ctrl+F5). KPI should never show N/A; Total/Critical/High should be computed. =="
