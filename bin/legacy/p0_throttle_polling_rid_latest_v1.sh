#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

# targets most likely to poll
files=(
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dashboard_luxe_v1.js
)

python3 - <<'PY'
from pathlib import Path
import re

targets = [Path(p) for p in [
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
] if Path(p).exists()]

def patch_text(s: str) -> str:
    # increase common 1000/1500/2000ms polling to 10000ms
    s2 = re.sub(r"setInterval\(([^,]+),\s*(1000|1500|2000)\s*\)", r"setInterval(\1, 10000)", s)

    # add visibility guard around fetch('/api/vsp/rid_latest') patterns
    if "/api/vsp/rid_latest" in s2 and "visibilityState" not in s2:
        guard = """
// VSP_P0_THROTTLE_POLLING_RID_LATEST_V1
function __vspVisible(){ try{return document.visibilityState==='visible';}catch(e){return true;} }
"""
        s2 = guard + s2

        # naive wrap: replace `fetch('/api/vsp/rid_latest` with `(__vspVisible()?fetch(...):Promise.resolve(null))`
        s2 = s2.replace("fetch('/api/vsp/rid_latest", "(__vspVisible()?fetch('/api/vsp/rid_latest")
        s2 = s2.replace("fetch(\"/api/vsp/rid_latest", "(__vspVisible()?fetch(\"/api/vsp/rid_latest")
        # close paren best-effort: add `:Promise.resolve(null))` right after first `.then(` if present
        s2 = s2.replace(").then(", ":Promise.resolve(null))).then(", 1)

    return s2

for p in targets:
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "VSP_P0_THROTTLE_POLLING_RID_LATEST_V1" in s:
        print("[SKIP] already patched", p)
        continue
    s2 = patch_text(s)
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched", p)
    else:
        print("[NOOP] no changes", p)
PY

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.6
fi

ok "DONE (polling throttled where patterns matched)."
