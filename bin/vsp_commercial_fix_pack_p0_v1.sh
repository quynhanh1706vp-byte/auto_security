#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "== VSP COMMERCIAL FIX PACK (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

APP="vsp_demo_app.py"

backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "$f.bak_fixpack_${TS}"
  echo "[BACKUP] $f.bak_fixpack_${TS}"
}

# (1) Backend: ensure latest_rid_v1 returns rid (compat) via after_request shim
backup_file "$APP"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_AFTERREQ_LATEST_RID_COMPAT_P0_V1"
if MARK in s:
    print("[OK] after_request compat already present")
    raise SystemExit(0)

shim = r'''
# --- {MARK}: ensure /api/vsp/latest_rid_v1 returns `rid` (compat with UI) ---
@app.after_request
def vsp_afterreq_latest_rid_compat_p0_v1(resp):
    try:
        from flask import request
        if request.path == "/api/vsp/latest_rid_v1" and getattr(resp, "is_json", False):
            j = resp.get_json(silent=True)
            if isinstance(j, dict):
                # normalize keys
                rid = j.get("rid") or j.get("run_id") or j.get("id")
                if rid and not j.get("rid"):
                    j["rid"] = rid
                if rid and not j.get("run_id"):
                    j["run_id"] = rid
                # re-emit JSON
                import json as _json
                resp.set_data(_json.dumps(j, ensure_ascii=False))
                resp.mimetype = "application/json"
    except Exception:
        pass
    return resp
'''.replace("{MARK}", MARK)

# inject near end, before if __name__ or at EOF
m = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
ins = m.start() if m else len(s)
s2 = s[:ins] + "\n" + shim + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected after_request compat shim")
PY
python3 -m py_compile "$APP" && echo "[OK] py_compile OK"

# (2) Replace 2 BAD JS files with clean stubs (commercial mode)
write_stub() {
  local f="$1"; local name="$2"
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; return 0; }
  backup_file "$f"
  cat > "$f" <<EOF
/* ${name} STUB (COMMERCIAL P0) */
(function(){
  'use strict';
  try{
    // Keep API surface so older code won't crash
    window.${name} = window.${name} || function(){ return true; };
  }catch(_){}
})();
EOF
  node --check "$f" >/dev/null 2>&1 && echo "[OK] stubbed + syntax OK: $f" || { echo "[ERR] stub syntax fail: $f"; node --check "$f"; exit 3; }
}

write_stub "static/js/vsp_runs_tab_8tools_v1.js" "VSP_RUNS_TAB_8TOOLS_V1"
write_stub "static/js/vsp_dashboard_live_v2.js" "VSP_DASHBOARD_LIVE_V2"

# (3) Disable dynamic loader family (these should NOT run in commercial bundle-only)
disable_script() {
  local f="$1"; local tag="$2"
  [ -f "$f" ] || return 0
  backup_file "$f"
  cat > "$f" <<EOF
/* ${tag} DISABLED (COMMERCIAL BUNDLE-ONLY) */
(function(){
  'use strict';
  try{
    // In commercial mode we never dynamically load other scripts.
    if (window && (window.__VSP_BUNDLE_COMMERCIAL_V2 || window.__VSP_BUNDLE_COMMERCIAL_V1)) return;
  }catch(_){}
})();
EOF
  node --check "$f" >/dev/null 2>&1 && echo "[OK] disabled + syntax OK: $f" || { echo "[ERR] disable syntax fail: $f"; node --check "$f"; exit 4; }
}

disable_script "static/js/vsp_ui_loader_route_v1.js" "VSP_UI_LOADER_ROUTE_V1"
disable_script "static/js/vsp_ui_features_v1.js" "VSP_UI_FEATURES_V1"
disable_script "static/js/vsp_hash_normalize_v1.js" "VSP_HASH_NORMALIZE_V1"
disable_script "static/js/vsp_drilldown_stub_safe_v1.js" "VSP_DRILLDOWN_STUB_SAFE_V1"

# (4) Rebuild bundle v2 + patch templates to load ONLY bundle v2
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/rebuild_bundle_commercial_v2_p0_v2.sh
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_templates_bundle_v2_only_p0_v1.sh

echo "== DONE FIX PACK =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R"
echo "[VERIFY] curl -sS http://127.0.0.1:8910/api/vsp/latest_rid_v1 | python3 -m json.tool"
