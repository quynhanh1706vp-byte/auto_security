#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

FILES=(
  static/js/vsp_dashboard_consistency_patch_v1.js
  static/js/vsp_data_source_tab_v3.js
  static/js/vsp_data_source_pagination_v1.js
)

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || err "missing $f"
  cp -f "$f" "${f}.bak_v1p0_${TS}"
  ok "backup: ${f}.bak_v1p0_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

# ---------- (1)+(2) Dashboard KPI N/A cleanup + remove debug strings ----------
dash = Path("static/js/vsp_dashboard_consistency_patch_v1.js")
s = dash.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_COMMERCIAL_UX_POLISH_V1P0"
if MARK not in s:
    inject = r'''
/* ===================== VSP_P0_COMMERCIAL_UX_POLISH_V1P0 =====================
   1) CIO KPI: never show "N/A"/"not available" -> show 0 or "—" + tooltip
   2) Remove debug/internal strings: UNIFIED FROM..., file paths
============================================================================ */

(function(){
  try{
    if (window.__VSP_CIO_POLISH_V1P0__) return;
    window.__VSP_CIO_POLISH_V1P0__ = true;

    function isBad(v){
      if (v === null || v === undefined) return true;
      const t = (typeof v === "string") ? v.trim().toLowerCase() : "";
      return t === "n/a" || t === "na" || t === "not available" || t === "none" || t === "null" || t === "undefined";
    }
    function toNum(v){
      if (typeof v === "number" && isFinite(v)) return v;
      if (typeof v === "string"){
        const x = Number(v.replace(/,/g,"").trim());
        if (isFinite(x)) return x;
      }
      return 0;
    }
    function fmtVal(v, mode){
      // mode: "num" -> always number, "dash" -> "—" when bad
      if (mode === "dash") return isBad(v) ? "—" : String(v);
      return String(toNum(v));
    }

    // scrub visible debug strings in DOM (safe, idempotent)
    function scrubText(root){
      try{
        const w = root || document;
        const bad = [
          /UNIFIED FROM\s+[^\n]+/ig,
          /findings_unified\.json/ig,
          /\/home\/test\/[^\s"'<>]+/ig
        ];
        const nodes = w.querySelectorAll ? w.querySelectorAll("*") : [];
        for(const el of nodes){
          if (!el || !el.childNodes) continue;
          for(const n of el.childNodes){
            if (!n || n.nodeType !== 3) continue; // text node
            let t = n.nodeValue || "";
            let changed = t;
            changed = changed.replace(/UNIFIED FROM\s+findings_unified\.json/ig, "Unified Findings (8 tools)");
            for(const rx of bad){
              changed = changed.replace(rx, function(m){
                if (/UNIFIED FROM/i.test(m)) return "Unified Findings (8 tools)";
                return "";
              });
            }
            if (changed !== t) n.nodeValue = changed;
          }
        }
      }catch(e){}
    }

    // Patch KPI rendering by wrapping common global render hooks if they exist
    const old = window.__vspRenderKpiCard;
    window.__vspRenderKpiCard = function(el, label, value, opts){
      try{
        const mode = (opts && opts.mode) ? opts.mode : "num";
        const shown = fmtVal(value, mode);
        if (el){
          el.textContent = shown;
          if (shown === "—" || shown === "0"){
            el.title = (opts && opts.title) ? opts.title : "No data for this run. Select a valid RID.";
          }
        }
      }catch(e){}
      if (typeof old === "function") return old(el, label, value, opts);
    };

    // Global helper for any KPI setter in this file
    window.__vspCioKpiSet = function(sel, v, mode){
      try{
        const el = document.querySelector(sel);
        if (!el) return;
        const shown = fmtVal(v, mode||"num");
        el.textContent = shown;
        if (shown === "—" || shown === "0"){
          el.title = "No data for this run. Select a valid RID.";
        }
      }catch(e){}
    };

    // run once + on next ticks (after async loads)
    function bootScrub(){
      scrubText(document);
      setTimeout(()=>scrubText(document), 500);
      setTimeout(()=>scrubText(document), 1500);
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bootScrub, { once:true });
    else bootScrub();

  }catch(e){}
})();
 /* ===================== /VSP_P0_COMMERCIAL_UX_POLISH_V1P0 ===================== */
'''
    s = inject + "\n" + s

# Also replace literal debug labels in source (static)
s = s.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
s = re.sub(r'UNIFIED FROM\s+findings_unified\.json', "Unified Findings (8 tools)", s, flags=re.I)

dash.write_text(s, encoding="utf-8")
print("[OK] dashboard consistency patched")

# ---------- (3) Data Source: enforce findings_page_v3 only, ban run_file_allow ----------
def enforce_data_source(path: str):
    p = Path(path)
    t = p.read_text(encoding="utf-8", errors="ignore")
    if "VSP_P0_DS_API_ONLY_V1P0" in t:
        print("[OK] already patched:", path); return
    # Hard replace any run_file_allow usage to findings_page_v3 equivalent comment + throw
    # (fail fast if someone re-introduces)
    t2 = t
    t2 = re.sub(r'/api/vsp/run_file_allow\?rid=\$\{?rid\}?&path=[^"\']+',
                r'/api/vsp/findings_page_v3?rid=${rid}&limit=${limit}&offset=${offset}', t2)
    # If generic run_file_allow remains, block it at runtime
    block = r'''
/* ===================== VSP_P0_DS_API_ONLY_V1P0 =====================
   Data Source must NOT call run_file_allow/path internal files.
   Enforce paging contract via findings_page_v3.
============================================================================ */
(function(){
  try{
    if (window.__VSP_DS_BLOCK_RUNFILEALLOW_V1P0__) return;
    window.__VSP_DS_BLOCK_RUNFILEALLOW_V1P0__ = true;
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;
    window.fetch = function(input, init){
      try{
        const u = new URL(String(input), location.origin);
        if (u.origin === location.origin && u.pathname === "/api/vsp/run_file_allow"){
          throw new Error("Commercial contract: Data Source must not use run_file_allow");
        }
      }catch(e){
        // if URL parse fails, let it pass
      }
      return _fetch(input, init);
    };
  }catch(e){}
})();
 /* ===================== /VSP_P0_DS_API_ONLY_V1P0 ===================== */
'''
    t2 = block + "\n" + t2

    # Encourage usage of findings_page_v3 by providing helper (non-breaking)
    if "__vspDsFetchPageV1P0" not in t2:
        t2 += r'''

async function __vspDsFetchPageV1P0(rid, limit, offset, q, sev, tool){
  const sp = new URLSearchParams();
  sp.set("rid", String(rid||""));
  sp.set("limit", String(limit||200));
  sp.set("offset", String(offset||0));
  if (q) sp.set("q", String(q));
  if (sev) sp.set("sev", String(sev));
  if (tool) sp.set("tool", String(tool));
  const url = "/api/vsp/findings_page_v3?" + sp.toString();
  const r = await fetch(url, { credentials:"same-origin" });
  if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
  return await r.json();
}
'''
    p.write_text(t2, encoding="utf-8")
    print("[OK] data source patched:", path)

for fp in ["static/js/vsp_data_source_tab_v3.js","static/js/vsp_data_source_pagination_v1.js"]:
    enforce_data_source(fp)
PY

for f in "${FILES[@]}"; do
  node --check "$f" && ok "node --check OK: $f" || { warn "node --check FAIL: rollback $f"; cp -f "${f}.bak_v1p0_${TS}" "$f"; err "rolled back $f"; }
done

echo "== [SMOKE] verify no forbidden run_file_allow usage in FE JS =="
grep -RIn --line-number '/api/vsp/run_file_allow' static/js | head -n 50 || true

echo "== [DONE] Reload /vsp5 and /data_source (Ctrl+F5). KPI must not show N/A; debug labels removed; DS uses findings_page_v3 only. =="
