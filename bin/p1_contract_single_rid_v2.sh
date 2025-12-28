#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

FILES=(
  static/js/vsp_rid_autofix_v1.js
  static/js/vsp_dashboard_commercial_panels_v1.js
  static/js/vsp_bundle_commercial_v2.js
  static/js/vsp_dashboard_gate_story_v1.js
)

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "$f.bak_contract2_${TS}"
    echo "[BACKUP] $f.bak_contract2_${TS}"
  else
    echo "[WARN] missing (skip): $f"
  fi
done

python3 - <<'PY'
from pathlib import Path
import re

TS_MARK = "VSP_P1_CONTRACT_SINGLE_RID_V2"

BOOT_FLAGS = r"""
/* VSP_P1_CONTRACT_SINGLE_RID_V2
 * Lock commercial flags early (must run before any legacy code).
 * - force rid source: /api/vsp/rid_latest_gate_root
 * - disable legacy dash + interceptors + fetch shim
 * - disable SARIF probing (dashboard step2 doesn't need it)
 * - clear pinned RID keys (RUN_* noise)
 */
(()=>{try{
  const lock=(k,v)=>{try{Object.defineProperty(window,k,{value:v,writable:false,configurable:false});}catch(_){window[k]=v;}}
  lock("__vsp_disable_legacy_dash_v1", true);
  lock("__vsp_disable_interceptors_v1", true);
  lock("__vsp_disable_fetch_shim_v1", true);
  lock("__vsp_disable_probe_sarif_v1", true);
  lock("__vsp_latest_rid_url_v1", "/api/vsp/rid_latest_gate_root");

  // Clear typical RID pin keys (best-effort)
  const keys=["vsp.rid","VSP_RID","VSP_RID_PIN","vsp_rid","rid_pin","vsp_last_rid","vsp.latest.rid","vsp.latestRid"];
  for (const k of keys){ try{ localStorage.removeItem(k); }catch(_){ } }
}catch(_){}})();
"""

def inject_boot_flags(text: str) -> str:
    if TS_MARK in text:
        return text
    # inject at top, before any IIFE runs
    return BOOT_FLAGS + "\n" + text

def replace_latest_rid(text: str) -> str:
    # canonicalize legacy endpoints
    text = text.replace("/api/vsp/latest_rid", "/api/vsp/rid_latest_gate_root")
    text = text.replace("/api/vsp/rid_latest", "/api/vsp/rid_latest_gate_root")
    return text

def neuter_run_pin(text: str) -> str:
    # If code reads localStorage rid into a variable, ignore RUN_* automatically
    # Covers patterns: rid = localStorage.getItem(...)
    text = re.sub(
        r'(\b[a-zA-Z_$][\w$]*\s*=\s*localStorage\.getItem\([^\)]*\)\s*;)',
        r'\1\ntry{ if (typeof rid==="string" && rid.startsWith("RUN_")) rid=""; }catch(_){ }',
        text,
        count=1
    )
    return text

def disable_sarif_probe_in_bundle(text: str) -> str:
    # Insert guard into probeText() if present
    m = re.search(r'function\s+probeText\s*\(([^)]*)\)\s*\{', text)
    if not m:
        return text
    head_end = m.end()
    guard = r"""
if (window.__vsp_disable_probe_sarif_v1) {
  try {
    const _p = (typeof path!=="undefined" ? path : (arguments.length>1 ? arguments[1] : "")) || "";
    if (/\.sarif(\?|$)/i.test(_p) || /findings_unified\.sarif/i.test(_p)) {
      return Promise.resolve(false);
    }
  } catch(_){}
}
"""
    # avoid double-inject
    if "VSP_DISABLE_PROBE_SARIF" in text:
        return text
    guard = "/* VSP_DISABLE_PROBE_SARIF */\n" + guard
    return text[:head_end] + "\n" + guard + text[head_end:]

def patch_file(path: str):
    p = Path(path)
    if not p.exists():
        return
    s = p.read_text(encoding="utf-8", errors="replace")
    s = inject_boot_flags(s)
    s = replace_latest_rid(s)
    s = neuter_run_pin(s)
    if p.name == "vsp_bundle_commercial_v2.js":
        s = disable_sarif_probe_in_bundle(s)
        # Also remove any hardcoded sarif path probes (string-only)
        s = s.replace("findings_unified.sarif", "findings_unified.sarif")  # keep string for UI label; probeText guard will block fetch
    p.write_text(s, encoding="utf-8")

for f in [
  "static/js/vsp_rid_autofix_v1.js",
  "static/js/vsp_dashboard_commercial_panels_v1.js",
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_dashboard_gate_story_v1.js",
]:
    patch_file(f)

print("[OK] patched contract single rid v2")
PY

# quick syntax checks (best-effort)
if command -v node >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    [ -f "$f" ] && node --check "$f" >/dev/null && echo "[OK] node --check $f"
  done
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
