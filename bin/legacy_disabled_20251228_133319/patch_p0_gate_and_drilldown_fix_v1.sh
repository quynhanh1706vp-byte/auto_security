#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F1="static/js/vsp_dashboard_enhance_v1.js"
F2="static/js/vsp_gate_panel_v1.js"

[ -f "$F1" ] || { echo "[ERR] missing $F1"; exit 2; }
[ -f "$F2" ] || { echo "[ERR] missing $F2"; exit 2; }

cp -f "$F1" "$F1.bak_p0fix_${TS}" && echo "[BACKUP] $F1.bak_p0fix_${TS}"
cp -f "$F2" "$F2.bak_p0fix_${TS}" && echo "[BACKUP] $F2.bak_p0fix_${TS}"

echo "== [1] Fix ReferenceError drilldown undefined (add safe stub) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

# Nếu đã có stub thì thôi
if "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" in s and "is not defined" not in s:
    pass

stub = r"""
  // P0 FIX: avoid ReferenceError if drilldown artifacts helper is missing
  if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') {
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
      try{ console.warn("[VSP_DASH] drilldown helper missing -> skipped"); }catch(_){}
      return false;
    };
  }
"""

# chèn ngay sau 'use strict';
m=re.search(r"(['\"]use strict['\"];\s*)", s)
if not m:
    raise SystemExit("[ERR] cannot find 'use strict' to inject stub")
i=m.end(1)
s2=s[:i]+stub+s[i:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected drilldown stub")
PY

echo "== [2] Fix gate panel: runs_index_v3_fs_resolved params + fallback =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# 2.1) ép URL có params thương mại (limit=1 hide_empty=0 filter=1)
s = re.sub(
    r'("/api/vsp/runs_index_v3_fs_resolved)(\?[^"]*)?"',
    r'"\1?limit=1&hide_empty=0&filter=1"',
    s,
    count=1
)

# 2.2) nếu vẫn không có runs => fallback filter=0
# tìm đoạn throw "no runs from runs_index_v3_fs_resolved"
pat = r'(throw new Error\(\s*["\']no runs from runs_index_v3_fs_resolved[^;]*;\s*)'
m=re.search(pat, s)
if not m:
    # nếu pattern khác, vẫn OK (đã ép params), không hard-fail
    p.write_text(s, encoding="utf-8")
    print("[WARN] cannot locate throw-no-runs to add fallback (params already forced)")
else:
    inject = r"""
      // P0 FIX: fallback: try filter=0 if filter=1 returns empty
      try{
        const u2 = "/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=0";
        const r2 = await fetch(u2, {cache:"no-store"});
        const j2 = await r2.json();
        if (j2 && Array.isArray(j2.items) && j2.items.length>0){
          runs = j2.items;
        }
      }catch(_){}
      if (runs && runs.length>0){ /* recovered */ }
      else
"""
    # chèn inject ngay trước throw
    s2 = s[:m.start(1)] + inject + s[m.start(1):]
    p.write_text(s2, encoding="utf-8")
    print("[OK] added fallback before throw-no-runs")
PY

echo "== [3] sanity check JS parse =="
node --check "$F1" >/dev/null && echo "[OK] node --check OK: $F1"
node --check "$F2" >/dev/null && echo "[OK] node --check OK: $F2"

echo "== [4] restart gunicorn 8910 =="
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.0
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] Hard refresh Ctrl+Shift+R, then check Gate panel + Console"
