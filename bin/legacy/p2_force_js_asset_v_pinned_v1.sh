#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need head

# get pinned asset_v from systemd env
PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd; abort"
  exit 2
fi
echo "[OK] pinned VSP_ASSET_V=$PIN"

TS="$(date +%Y%m%d_%H%M%S)"

patch_js(){
  local f="$1"
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; return 0; }
  cp -f "$f" "${f}.bak_pinassetv_${TS}"
  echo "[BACKUP] ${f}.bak_pinassetv_${TS}"

  python3 - "$f" "$PIN" <<'PY'
import sys, re
from pathlib import Path
fn=sys.argv[1]
pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_JS_ASSET_V_PINNED_V1"
if marker in s:
    # still hard-replace any Date.now/time usage for v=
    pass

# 1) ensure a helper exists
helper = f'''
/* {marker} */
(function(){{
  try {{
    if (!window.__VSP_ASSET_V) window.__VSP_ASSET_V = "{pin}";
  }} catch(e) {{}}
}})();
function __vspAssetV(){{
  try {{
    return (window.__VSP_ASSET_V || "{pin}");
  }} catch(e) {{
    return "{pin}";
  }}
}}
'''.lstrip("\n")

if marker not in s:
    s = helper + "\n" + s

# 2) normalize common patterns:
#    - "?v="+Date.now()
#    - "?v="+(new Date().getTime())
#    - "?v="+Math.floor(Date.now()/1000)
#    - "?v="+(something with time)
#    - "?v="+YYYYMMDD (8 digits) style
#    - "?v="+int(time.time()) was in python; JS uses Date*
s = re.sub(r'\?v="\s*\+\s*(?:Date\.now\(\)|new Date\(\)\.getTime\(\)|Math\.floor\(\s*Date\.now\(\)\s*/\s*1000\s*\))', r'?v="+__vspAssetV()', s)
s = re.sub(r'\?v=\'+\s*(?:Date\.now\(\)|new Date\(\)\.getTime\(\)|Math\.floor\(\s*Date\.now\(\)\s*/\s*1000\s*\))', r"?v='+__vspAssetV()", s)

# Also replace any literal "?v=20251224" on these core loader js
s = re.sub(r'(\.js\?v=)(\d{8})(?!\d)', r'\1"+__vspAssetV()+"', s)

# If they build with template literal: `?v=${Date.now()}`
s = re.sub(r'`(\?v=\$\{)\s*Date\.now\(\)\s*(\})`', r'`?v=${__vspAssetV()}`', s)

p.write_text(s, encoding="utf-8")
print("[OK] patched", fn)
PY
}

# core duplicated basenames
patch_js "static/js/vsp_bundle_tabs5_v1.js"
patch_js "static/js/vsp_dashboard_luxe_v1.js"
patch_js "static/js/vsp_tabs4_autorid_v1.js"
patch_js "static/js/vsp_topbar_commercial_v1.js"

# also ensure templates expose window.__VSP_ASSET_V early
echo "== patch templates to seed window.__VSP_ASSET_V =="
python3 - "$PIN" <<'PY'
from pathlib import Path
import re, time, sys
pin=sys.argv[1]
root=Path("templates")
if not root.exists():
    print("[WARN] templates/ missing")
    raise SystemExit(0)

seed = r'<script>window.__VSP_ASSET_V="{{ asset_v }}";</script>'
changed=0
for fp in root.rglob("*.html"):
    s=fp.read_text(encoding="utf-8", errors="replace")
    if "window.__VSP_ASSET_V" in s:
        continue
    # insert right after <head> if possible else at top
    if "<head" in s:
        s2=re.sub(r'(<head[^>]*>)', r'\1\n'+seed, s, count=1, flags=re.I)
    else:
        s2=seed+"\n"+s
    if s2!=s:
        bak=fp.with_suffix(fp.suffix+f".bak_seedassetv_{int(time.time())}")
        bak.write_text(s, encoding="utf-8")
        fp.write_text(s2, encoding="utf-8")
        changed += 1
print("[OK] templates seeded:", changed)
PY

echo "== restart service =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick verify: grep duplicated basenames per tab =="
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE '(vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9_]+)' | sort -u || true
done

echo "[OK] done"
