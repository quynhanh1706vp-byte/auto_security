#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need curl; need grep; need head

targets=(
  "static/js/vsp_bundle_tabs5_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
  "static/js/vsp_dashboard_consistency_patch_v1.js"
  "static/js/vsp_rid_switch_refresh_all_v1.js"
  "static/js/vsp_rid_persist_patch_v1.js"
  "static/js/vsp_topbar_commercial_v1.js"
  "static/js/vsp_tabs4_autorid_v1.js"
)

echo "== [0] Backup =="
for f in "${targets[@]}"; do
  [ -f "$f" ] || continue
  cp -f "$f" "${f}.bak_timeoutfix_${TS}"
  echo "[BACKUP] ${f}.bak_timeoutfix_${TS}"
done

echo "== [1] Revert __vspSafeTimeout back to setTimeout (keep SafeInterval) =="
python3 - <<'PY'
from pathlib import Path
import re
targets = [
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_rid_switch_refresh_all_v1.js",
  "static/js/vsp_rid_persist_patch_v1.js",
  "static/js/vsp_topbar_commercial_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
]
for f in targets:
    p=Path(f)
    if not p.exists(): 
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    s2=s.replace("window.__vspSafeTimeout(", "setTimeout(")
    if s2!=s:
        p.write_text(s2, encoding="utf-8")
        print("[OK] reverted timeout in", f)
    else:
        print("[OK] timeout unchanged in", f)
PY

echo "== [2] Parse check =="
node - <<'NODE'
const fs=require("fs");
const files=[
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_rid_switch_refresh_all_v1.js",
  "static/js/vsp_rid_persist_patch_v1.js",
  "static/js/vsp_topbar_commercial_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
];
let bad=0;
for(const f of files){
  if(!fs.existsSync(f)) continue;
  try{ new Function(fs.readFileSync(f,"utf8")); }
  catch(e){ bad++; console.error("[BAD]", f, e.message); }
}
process.exit(bad?2:0);
NODE
echo "[OK] parse ok"

echo "== [3] Restart =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [4] Verify helper still present in bundle =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --max-time 3 "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_SAFE_INTERVAL_V1\|__vspSafeInterval" | head || true
echo "[DONE] Ctrl+Shift+R on /vsp5"
