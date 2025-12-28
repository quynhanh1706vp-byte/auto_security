#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# ------------------------------------------------------------
# (1) Make vsp_rid_autofix_v1.js a SAFE NO-OP (so even if still loaded, it won't fetch/pin rid)
# ------------------------------------------------------------
RIDFIX="static/js/vsp_rid_autofix_v1.js"
mkdir -p "$(dirname "$RIDFIX")"
if [ -f "$RIDFIX" ]; then
  cp -f "$RIDFIX" "${RIDFIX}.bak_noop_${TS}"
  echo "[BACKUP] ${RIDFIX}.bak_noop_${TS}"
fi

cat > "$RIDFIX" <<'JS'
/* VSP_P1_RID_AUTOFIX_NOOP_V1
 * Commercial Step-2 contract:
 * Dashboard must NOT run any "rid autofix" logic.
 */
(()=> {
  try { window.__vsp_rid_autofix_disabled_v1 = true; } catch(_){}
  try { console.log("[VSP] rid_autofix DISABLED (commercial Step-2)"); } catch(_){}
})();
JS
echo "[OK] wrote NO-OP: $RIDFIX"

# ------------------------------------------------------------
# (2) Patch bundle:
#   - lock flags early with defineProperty (can't be overwritten)
#   - hard-disable SARIF probe (prevent 404 spam)
#   - guard legacy V6C/V6D/V6E blocks even if strings changed
# ------------------------------------------------------------
B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }
cp -f "$B" "${B}.bak_step2clean_${TS}"
echo "[BACKUP] ${B}.bak_step2clean_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_CLEAN_STEP2_CONTRACT_V1"

BOOT = r"""
/* VSP_P1_CLEAN_STEP2_CONTRACT_V1
 * Lock commercial flags early (non-writable) + disable SARIF probe.
 */
(()=>{try{
  const lock=(k,v)=>{ try{ Object.defineProperty(window,k,{value:v,writable:false,configurable:false}); }catch(_){ window[k]=v; } };
  lock("__vsp_disable_legacy_dash_v1", true);
  lock("__vsp_disable_interceptors_v1", true);
  lock("__vsp_disable_fetch_shim_v1", true);
  lock("__vsp_disable_probe_sarif_v1", true);
  lock("__vsp_latest_rid_url_v1", "/api/vsp/rid_latest_gate_root");
}catch(_){}})();
"""

if MARK not in s:
    s = BOOT + "\n" + s

# --- (2a) Guard legacy modules by searching for their *new* log strings
def guard_iife_containing(text: str, needle: str, tag: str) -> str:
    idx = text.find(needle)
    if idx < 0:
        return text
    start = text.rfind("(()=>", 0, idx)
    if start < 0:
        start = text.rfind("(function", 0, idx)
        if start < 0:
            return text
    brace = text.find("{", start)
    if brace < 0 or brace > idx:
        return text
    end = text.find("})();", idx)
    if end < 0:
        end = text.find("}());", idx)
        if end < 0:
            return text
    window = text[start:end+4]
    if "__vsp_disable_legacy_dash_v1" in window:
        return text
    insert = f"\nif (window.__vsp_disable_legacy_dash_v1) {{ /* disabled: {tag} */ return; }}\n"
    return text[:brace+1] + insert + text[brace+1:]

needles = [
    ("legacy disabled (V6E)", "DASH_V6E"),
    ("legacy disabled (V6D)", "DASH_V6D"),
    ("legacy disabled (V6C)", "DASH_V6C"),
]
for needle, tag in needles:
    # wrap all occurrences
    for _ in range(0, 50):
        before = s
        s = guard_iife_containing(s, needle, tag)
        if s == before:
            break

# --- (2b) Disable SARIF probe robustly: patch probeText definition (many forms)
def patch_probe_text(text: str) -> str:
    if "VSP_DISABLE_PROBE_SARIF_V1" in text:
        return text

    patterns = [
        r'(async\s+function\s+probeText\s*\([^)]*\)\s*\{)',
        r'(function\s+probeText\s*\([^)]*\)\s*\{)',
        r'((?:const|let|var)\s+probeText\s*=\s*async\s*\([^)]*\)\s*=>\s*\{)',
        r'((?:const|let|var)\s+probeText\s*=\s*\([^)]*\)\s*=>\s*\{)',
    ]

    guard = r"""
/* VSP_DISABLE_PROBE_SARIF_V1 */
try{
  if (window.__vsp_disable_probe_sarif_v1) {
    const _p = (typeof path!=="undefined" ? path : (arguments.length>1 ? arguments[1] : "")) || "";
    if (/\.sarif(\?|$)/i.test(_p) || /findings_unified\.sarif/i.test(_p)) {
      return Promise.resolve(false);
    }
  }
}catch(_){}
"""
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            # inject right after opening "{"
            head = m.group(1)
            pos = m.start(1) + head.rfind("{") + 1
            text = text[:pos] + "\n" + guard + "\n" + text[pos:]
            return text

    # fallback: if cannot find probeText definition, block fetch URL at string-level
    # Replace findings_unified.sarif with a harmless token so probe won't hit run_file_allow
    text = text.replace("findings_unified.sarif", "findings_unified.sarif__DISABLED__")
    return text

s = patch_probe_text(s)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$B" && echo "[OK] node --check bundle passed"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
