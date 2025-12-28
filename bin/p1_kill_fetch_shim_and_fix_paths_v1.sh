#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"

# ------------------------------------------------------------
# (1) Make fetch_shim a SAFE NO-OP (so even if template still loads it, it won't rewrite fetch)
# ------------------------------------------------------------
SHIM="static/js/vsp_p0_fetch_shim_v1.js"
mkdir -p "$(dirname "$SHIM")"

if [ -f "$SHIM" ]; then
  cp -f "$SHIM" "${SHIM}.bak_${TS}"
  echo "[BACKUP] ${SHIM}.bak_${TS}"
fi

cat > "$SHIM" <<'JS'
/* VSP_P1_FETCH_SHIM_NOOP_V1
 * Commercial clean: disable any fetch/XHR rewrite shim.
 * Reason: shim was rewriting /api/vsp/rid_latest_gate_root -> /api/vsp/rid_latest_gate_root_gate_root (404),
 * and causing noise/incorrect contract.
 */
(()=> {
  try { window.__vsp_fetch_shim_disabled_v1 = true; } catch(_){}
  try { console.log("[VSP] fetch shim DISABLED (commercial clean)"); } catch(_){}
})();
JS
echo "[OK] wrote NO-OP shim: $SHIM"

# ------------------------------------------------------------
# (2) Patch bundle to:
#   - force disable any legacy shim behavior
#   - normalize wrong rewritten endpoint if it appears
#   - normalize SARIF path reports/findings_unified.sarif -> findings_unified.sarif
#   - clear pinned RID keys (old RUN_...) at boot
# ------------------------------------------------------------
JSB="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JSB" ] || { echo "[ERR] missing $JSB"; exit 2; }

cp -f "$JSB" "${JSB}.bak_killshim_${TS}"
echo "[BACKUP] ${JSB}.bak_killshim_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_KILL_FETCH_SHIM_AND_FIX_PATHS_V1"
if MARK not in s:
    inject = r"""
/* VSP_P1_KILL_FETCH_SHIM_AND_FIX_PATHS_V1
 * - Ensure any fetch shim is effectively disabled
 * - Clear pinned RID keys (avoid old RUN_* taking over)
 * - Keep commercial contract: rid_latest_gate_root + run_gate_summary only
 */
(()=> {
  try {
    window.__vsp_disable_interceptors_v1 = true;
    window.__vsp_disable_fetch_shim_v1 = true;
    window.__vsp_disable_legacy_dash_v1 = true;

    // Clear common RID pin keys (best-effort; safe if absent)
    const keys = [
      "vsp.rid","VSP_RID","VSP_RID_PIN","vsp_rid","rid_pin",
      "vsp_last_rid","vsp.latest.rid","vsp.latestRid"
    ];
    for (const k of keys) { try { localStorage.removeItem(k); } catch(_){} }
  } catch(_){}
})();
"""
    # put it at the very top (before anything runs)
    s = inject + "\n" + s

# If any wrong rewritten endpoint exists in the bundle (from previous rewrites), normalize it.
s = s.replace("/api/vsp/rid_latest_gate_root_gate_root", "/api/vsp/rid_latest_gate_root")
s = s.replace("rid_latest_gate_root_gate_root", "rid_latest_gate_root")

# Normalize SARIF probe path: your evidence seems not under reports/, and the old probe 404s.
s = s.replace("reports/findings_unified.sarif", "findings_unified.sarif")
s = s.replace("reports%2Ffindings_unified.sarif", "findings_unified.sarif")

# Also normalize other common report paths (harmless if unused)
s = s.replace("reports/findings_unified.csv", "reports/findings_unified.csv")  # keep
s = s.replace("reports/findings_unified.json", "findings_unified.json")        # if any legacy

p.write_text(s, encoding="utf-8")
print("[OK] patched bundle marker:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JSB" && echo "[OK] node --check passed"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
