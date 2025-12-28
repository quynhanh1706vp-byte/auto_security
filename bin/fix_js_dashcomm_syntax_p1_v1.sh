#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

# (0) backup current broken file
cp -f "$F" "$F.bak_before_fix_${TS}"
echo "[BACKUP] $F.bak_before_fix_${TS}"

# (1) restore from latest safe backup (prefer bak_dashcomm_*)
B="$(ls -1t ${F}.bak_dashcomm_* 2>/dev/null | head -n1 || true)"
if [ -z "${B:-}" ]; then
  # fallback to full backup
  B="$(ls -1t ${F}.bak_full_* 2>/dev/null | head -n1 || true)"
fi
[ -n "${B:-}" ] || { echo "[ERR] no backup found for $F"; exit 3; }

cp -f "$B" "$F"
echo "[RESTORE] $F <= $B"

# (2) patch safely: replace ONLY the dashboard_v3 fetch line with commercial->fallback
python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DASH_USE_COMMERCIAL_P1_SAFE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

needle = "STATE.dashboard = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now());"
if needle not in s:
    print("[ERR] cannot find dashboard_v3 fetch line to patch")
    raise SystemExit(2)

replacement = """// %s
      try{
        STATE.dashboard = await fetchJson('/api/vsp/dashboard_commercial_v1?ts=' + Date.now());
      }catch(_e1){
        STATE.dashboard = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now());
      }""" % MARK

s = s.replace(needle, replacement, 1)
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

echo "== node --check =="
node --check "$F"

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R /vsp4#dashboard → KPI phải có số (từ dashboard_commercial_v1). Console phải sạch."
