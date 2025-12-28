#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

inject_one(){
  local F="$1"
  [ -f "$F" ] || { echo "[WARN] missing $F"; return 0; }

  if grep -q "VSP_BADGEPIN_V2_LOADER" "$F" 2>/dev/null; then
    echo "[OK] already injected: $F"
    return 0
  fi

  cp -f "$F" "${F}.bak_badgepinfix_${TS}"
  python3 - "$F" <<'PY'
import sys
from pathlib import Path

fn=sys.argv[1]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_BADGEPIN_V2_LOADER"
loader=f"""
// {marker}
(function(){{
  try{{
    if (window.__VSP_BADGEPIN_V2_LOADER) return;
    window.__VSP_BADGEPIN_V2_LOADER = true;
    var id="vsp-pin-dataset-badge-v2";
    if (document.getElementById(id)) return;
    var sc=document.createElement("script");
    sc.id=id;
    sc.src="/static/js/vsp_pin_dataset_badge_v2.js?v=" + (window.__VSP_ASSET_V || Date.now());
    sc.async=true;
    sc.defer=true;
    (document.head||document.documentElement).appendChild(sc);
  }}catch(e){{}}
}})();
"""

if marker in s:
    print("[OK] noop (marker already present)")
else:
    lines=s.splitlines(True)
    ins_at=1 if len(lines)>1 else len(lines)
    lines.insert(ins_at, loader+"\n")
    p.write_text("".join(lines), encoding="utf-8")
    print("[OK] injected loader into", fn)
PY
}

inject_one "static/js/vsp_dashboard_luxe_v1.js"
inject_one "static/js/vsp_bundle_tabs5_v1.js"
inject_one "static/js/vsp_tabs4_autorid_v1.js"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] findings_page_v3 fields (data_source + pin_mode)"
curl -sS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0&pin=auto" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"data_source=",j.get("data_source"),"pin_mode=",j.get("pin_mode"))'

echo "[DONE] Open: $BASE/vsp5?rid=$RID  then Ctrl+F5"
