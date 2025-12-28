#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need jq

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_precachekill_${TS}"
echo "[BACKUP] ${JS}.bak_precachekill_${TS}"

python3 - "$JS" "$TS" <<'PY'
import sys
from pathlib import Path
js=Path(sys.argv[1]); ts=sys.argv[2]
s=js.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_PRELOAD_DISABLE_CACHED_RID_V1"
if MARK in s:
    print("[OK] marker already present"); sys.exit(0)

pre = f"""/* {MARK} {ts}
   Force UI to ignore cached RID in localStorage so it must follow /api/vsp/runs rid_latest.
*/
(function(){{
  try{{
    const K = new Set(['vsp_active_rid','vsp_latest_rid','vsp_selected_rid','vsp_rid','rid','rid_latest']);
    // clear once (best-effort)
    for(const k of K){{ try{{ localStorage.removeItem(k); }}catch(e){{}} }}
    // override Storage.getItem globally
    const _get = Storage.prototype.getItem;
    Storage.prototype.getItem = function(k){{
      if(K.has(String(k))) return null;
      return _get.call(this, k);
    }};
  }}catch(e){{}}
}})();
"""
js.write_text(pre + "\n" + s, encoding="utf-8")
print("[OK] prepended:", MARK)
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== verify rid_latest =="
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.rid_latest,.items[0].run_id' || true

echo "== verify bootjs has marker =="
V="$(curl -sS http://127.0.0.1:8910/vsp5 | sed -n 's/.*vsp_p1_page_boot_v1.js?v=\\([^"]*\\)".*/\\1/p' | head -n1)"
curl -sS "http://127.0.0.1:8910/static/js/vsp_p1_page_boot_v1.js?v=${V}" | grep -n "VSP_P1_PRELOAD_DISABLE_CACHED_RID_V1" | head -n 2 || true

echo "[NEXT] Open Incognito /vsp5 (important) or Ctrl+F5"
