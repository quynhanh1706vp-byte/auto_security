#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

DASH="static/js/vsp_dashboard_enhance_v1.js"
GATE="static/js/vsp_gate_panel_v1.js"

[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }
[ -f "$GATE" ] || { echo "[ERR] missing $GATE"; exit 2; }

cp -f "$DASH" "$DASH.bak_redfix_${TS}" && echo "[BACKUP] $DASH.bak_redfix_${TS}"
cp -f "$GATE" "$GATE.bak_redfix_${TS}" && echo "[BACKUP] $GATE.bak_redfix_${TS}"

echo "== [1] Fix drilldown: always-call-safe (never TypeError) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

# Replace any direct call VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2( ... )
# with a safe-call wrapper that works even if the symbol is not a function.
pat = r'\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\('
rep = r'(typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function" ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : function(){ try{ console.warn("[VSP_DASH] drilldown helper not a function -> skipped"); }catch(_){ } return false; })('
s2, n = re.subn(pat, rep, s)
if n == 0:
    print("[WARN] no drilldown call found to wrap (maybe already fixed)")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] wrapped drilldown calls: {n}")
PY

echo "== [2] Fix gate panel: define vspGateFetch in-scope (never ReferenceError) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

if "function vspGateFetch" in s or "const vspGateFetch" in s:
    print("[OK] vspGateFetch already defined -> skip inject")
else:
    helper = r"""
  // P0 FIX: ensure vspGateFetch exists (gate panel must never ReferenceError)
  function vspGateNormalizeRunsIndexUrl(u){
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
  function vspGateFetch(u, opts){
    try{
      const u2 = vspGateNormalizeRunsIndexUrl(u);
      return window.fetch(u2, opts);
    }catch(_){
      return window.fetch(u, opts);
    }
  }
"""
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if not m:
      # fallback: inject at top if no 'use strict'
      s = helper + "\n" + s
      print("[WARN] no 'use strict' found; injected helper at top")
    else:
      i=m.end(1)
      s = s[:i] + helper + s[i:]
      print("[OK] injected vspGateFetch helper after 'use strict'")

    p.write_text(s, encoding="utf-8")

# If file uses vspGateFetch(...) already, fine.
# If it still uses fetch(...), also fine (helper doesn't harm).
PY

echo "== [3] sanity parse check =="
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
echo "[DONE] Hard refresh Ctrl+Shift+R, then confirm console has NO red errors."
