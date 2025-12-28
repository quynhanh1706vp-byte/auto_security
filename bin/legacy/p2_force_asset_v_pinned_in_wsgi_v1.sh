#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd ($SVC)"; exit 2
fi
echo "[OK] pinned VSP_ASSET_V=$PIN"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_force_assetv_${TS}"
echo "[BACKUP] ${W}.bak_force_assetv_${TS}"

python3 - "$W" "$PIN" <<'PY'
import sys,re
from pathlib import Path

fn=sys.argv[1]; pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_FORCE_ASSET_V_PINNED_WSGI_V1"
if marker not in s:
    # add a single authoritative getter near top (after imports if possible)
    insert = f'''
# --- {marker} ---
def _vsp_get_asset_v():
    import os
    return os.environ.get("VSP_ASSET_V") or os.environ.get("VSP_RELEASE_TS") or "{pin}"
# --- end {marker} ---
'''
    # try inject after first "import" block
    m=re.search(r'(?ms)^(.*?\n)(\s*app\s*=\s*)', s)
    if m:
        s = s[:m.start(2)] + insert + "\n" + s[m.start(2):]
    else:
        s = insert + "\n" + s

# Replace common patterns that create epoch asset_v
# asset_v = int(time.time()) / time.time() / datetime.now().timestamp()
s = re.sub(r'asset_v\s*=\s*int\(\s*time\.time\(\)\s*\)', 'asset_v = _vsp_get_asset_v()', s)
s = re.sub(r'asset_v\s*=\s*time\.time\(\)\s*', 'asset_v = _vsp_get_asset_v()', s)
s = re.sub(r'asset_v\s*=\s*int\(\s*datetime\.now\(\)\.timestamp\(\)\s*\)', 'asset_v = _vsp_get_asset_v()', s)
s = re.sub(r'asset_v\s*=\s*int\(\s*datetime\.datetime\.now\(\)\.timestamp\(\)\s*\)', 'asset_v = _vsp_get_asset_v()', s)

# Replace any direct usage of int(time.time()) inside url builders like f"...?v={int(time.time())}"
s = re.sub(r'int\(\s*time\.time\(\)\s*\)', '_vsp_get_asset_v()', s)

# Replace "strftime('%Y%m%d')" style (cut day) used as v
s = re.sub(r"datetime\.(?:datetime\.)?now\(\)\.strftime\(\s*['\"]%Y%m%d['\"]\s*\)", '_vsp_get_asset_v()', s)

# Ensure context processor returns pinned always (override if exists)
# If there is a context_processor providing asset_v, normalize it
s = re.sub(r'("asset_v"\s*:\s*)[^,\n}]+', r'\1_vsp_get_asset_v()', s)

p.write_text(s, encoding="utf-8")
print("[OK] patched wsgi for pinned asset_v")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

echo "[INFO] restarting $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick check core basenames per tab =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE '(vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+)' | sort -u || true
done

