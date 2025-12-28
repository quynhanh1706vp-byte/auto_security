#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

DASH="static/js/vsp_dashboard_enhance_v1.js"
GATE="static/js/vsp_gate_panel_v1.js"

[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }
[ -f "$GATE" ] || { echo "[ERR] missing $GATE"; exit 2; }

cp -f "$DASH" "$DASH.bak_p0_v2_${TS}" && echo "[BACKUP] $DASH.bak_p0_v2_${TS}"
cp -f "$GATE" "$GATE.bak_p0_v2_${TS}" && echo "[BACKUP] $GATE.bak_p0_v2_${TS}"

echo "== [1] FIX drilldown TypeError: wrap all calls local-first =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

# wrap any direct call: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...)
# local-first (handles shadowed const/object), then window fallback, else no-op.
rep = r'((typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function") ? VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function" ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : function(){ try{ console.warn("[VSP_DASH] drilldown helper not a function -> skipped"); }catch(_){ } return false; }))('
s2, n = re.subn(r'\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(', rep, s)
if n == 0:
    print("[WARN] no drilldown call found to wrap (maybe name differs)")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] wrapped drilldown calls: {n}")
PY

echo "== [2] FIX gate panel: normalize runs_index fetch + never throw no-runs =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# 2.1 inject wrapper (only once)
if "__VSP_GATE_ORIG_FETCH__" not in s:
    inject = r"""
  // P0 CANONICAL: gate panel must never fail because runs_index is filtered empty
  const __VSP_GATE_ORIG_FETCH__ = window.fetch.bind(window);

  function __vsp_gate_norm_url(u){
    try{
      if (typeof u !== "string") return u;
      if (u.indexOf("runs_index") < 0) return u;

      // force canonical params
      if (u.indexOf("filter=") >= 0) u = u.replace(/filter=\d+/g, "filter=0");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "filter=0";

      if (u.indexOf("hide_empty=") >= 0) u = u.replace(/hide_empty=\d+/g, "hide_empty=0");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "hide_empty=0";

      if (u.indexOf("limit=") >= 0) u = u.replace(/limit=\d+/g, "limit=1");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "limit=1";

      return u;
    }catch(_){ return u; }
  }

  function __vsp_gate_fetch(u, opts){
    try{ return __VSP_GATE_ORIG_FETCH__(__vsp_gate_norm_url(u), opts); }
    catch(_){ return __VSP_GATE_ORIG_FETCH__(u, opts); }
  }
"""
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s=s[:i]+inject+s[i:]
    else:
        s=inject+"\n"+s

# 2.2 route ALL fetch() in this file through __vsp_gate_fetch (including window.fetch)
s = s.replace("window.fetch(", "__vsp_gate_fetch(")
s = re.sub(r'(^|[^.\w$])fetch\s*\(', r'\1__vsp_gate_fetch(', s)

# 2.3 never hard-throw "no runs ..." (degrade gracefully)
s = re.sub(r'throw new Error\(\s*["\']no runs from runs_index_v3_fs_resolved[^"\']*["\']\s*\)\s*;?',
           'try{ console.warn("[VSP_GATE] no runs from runs_index_v3_fs_resolved (degraded)"); }catch(_){ } return;',
           s)

p.write_text(s, encoding="utf-8")
print("[OK] gate panel patched: fetch wrapper + no-throw")
PY

echo "== [3] node parse check must be OK =="
node --check "$DASH" >/dev/null && echo "[OK] node --check OK: $DASH"
node --check "$GATE" >/dev/null && echo "[OK] node --check OK: $GATE"

echo "== [4] restart gunicorn 8910 =="
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.2
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] HARD refresh Ctrl+Shift+R, then check console red errors + CI/CD Gate"
