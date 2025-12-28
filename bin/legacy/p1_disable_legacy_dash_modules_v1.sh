#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_legacy_${TS}"
echo "[BACKUP] ${JS}.bak_disable_legacy_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DISABLE_LEGACY_DASH_MODULES_V1"
if MARK not in s:
    inject = r"""
/* VSP_P1_DISABLE_LEGACY_DASH_MODULES_V1
 * Commercial contract: keep ONLY gate_root + run_gate_summary.
 * Disable legacy dashboard modules (V6C/V6D/V6E) and fetch_shim which cause:
 *  - rid pinning to old RUN_*
 *  - noisy "check ids"
 *  - 404 vsp_p0_fetch_shim_v1.js
 */
try { window.__vsp_disable_legacy_dash_v1 = true; } catch(_){}
"""
    s = inject + "\n" + s

def guard_iife_containing(needle: str, tag: str) -> str:
    nonlocal_s = s  # will be overwritten by outer scope assignment
    idx = nonlocal_s.find(needle)
    if idx < 0:
        return nonlocal_s

    # find the closest IIFE start "(()=>{" before idx
    start = nonlocal_s.rfind("(()=>", 0, idx)
    if start < 0:
        start = nonlocal_s.rfind("(function", 0, idx)
        if start < 0:
            return nonlocal_s

    # find the open brace of that IIFE
    brace = nonlocal_s.find("{", start)
    if brace < 0 or brace > idx:
        return nonlocal_s

    # find the IIFE end after idx
    end = nonlocal_s.find("})();", idx)
    if end < 0:
        end = nonlocal_s.find("}());", idx)
        if end < 0:
            return nonlocal_s

    # avoid double-wrapping
    window = nonlocal_s[start:end+4]
    if "__vsp_disable_legacy_dash_v1" in window:
        return nonlocal_s

    # insert guard right after the first "{"
    insert_head = f"\nif (window.__vsp_disable_legacy_dash_v1) {{ /* disabled: {tag} */ return; }}\n"
    nonlocal_s = nonlocal_s[:brace+1] + insert_head + nonlocal_s[brace+1:]
    return nonlocal_s

# Apply guards for legacy dashboard variants and fetch shim loader
needles = [
    ("[VSP][DASH][V6E]", "DASH_V6E"),
    ("[VSP][DASH][V6D]", "DASH_V6D"),
    ("[VSP][DASH][V6C]", "DASH_V6C"),
    ("vsp_p0_fetch_shim_v1.js", "FETCH_SHIM"),
]

for needle, tag in needles:
    # repeat until no more occurrences (some bundles contain multiple copies)
    changed = True
    while changed:
        before = s
        s = guard_iife_containing(needle, tag)
        changed = (s != before)
        # move forward by replacing first occurrence so we can find the next safely
        if not changed:
            break
        # prevent infinite loop: replace one occurrence of needle with itself (no-op) but shift search by slicing technique
        # simpler: mark the guarded block by inserting tag already; subsequent pass finds same needle again but now it contains guard; guard_iife_containing checks that.
        pass

# Also suppress remaining noisy logs if any (optional)
s = s.replace("[VSP][DASH][V6E] check ids", "[VSP][DASH] legacy disabled (V6E)")
s = s.replace("[VSP][DASH][V6D] gave up", "[VSP][DASH] legacy disabled (V6D)")
s = s.replace("[VSP][DASH][V6C] gave up", "[VSP][DASH] legacy disabled (V6C)")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
else
  echo "[WARN] node not found, skipped syntax check"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
