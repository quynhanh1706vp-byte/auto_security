#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_gate_panel_v1.js"

echo "== [0] restore latest pre-broken backup =="
BKP="$(ls -1t ${F}.bak_p0fix_* 2>/dev/null | head -n1 || true)"
[ -n "${BKP:-}" ] || { echo "[ERR] cannot find ${F}.bak_p0fix_*"; exit 2; }
cp -f "$BKP" "$F"
echo "[RESTORE] $F <= $BKP"

cp -f "$F" "$F.bak_gatecanon_${TS}" && echo "[BACKUP] $F.bak_gatecanon_${TS}"

echo "== [1] inject URL normalizer + wrap fetch(url, ...) when url contains runs_index =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# 1) inject helper after 'use strict'
helper = r"""
  // P0 CANONICAL: normalize runs_index URL (avoid empty gate panel)
  function vspGateNormalizeRunsIndexUrl(u){
    try{
      if (typeof u !== "string") return u;
      if (u.indexOf("runs_index") < 0) return u;

      // force filter=0
      if (u.indexOf("filter=") >= 0) {
        u = u.replace(/filter=\d+/g, "filter=0");
      } else {
        u += (u.indexOf("?")>=0 ? "&" : "?") + "filter=0";
      }

      // ensure hide_empty=0
      if (u.indexOf("hide_empty=") >= 0) u = u.replace(/hide_empty=\d+/g, "hide_empty=0");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "hide_empty=0";

      // ensure limit=1
      if (u.indexOf("limit=") >= 0) u = u.replace(/limit=\d+/g, "limit=1");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "limit=1";

      return u;
    }catch(_){ return u; }
  }
"""

m=re.search(r"(['\"]use strict['\"];\s*)", s)
if not m:
    raise SystemExit("[ERR] cannot find 'use strict' in gate panel to inject helper")
i=m.end(1)
s = s[:i] + helper + s[i:]

# 2) wrap fetch("...runs_index... ", opts)
#   fetch("...runs_index...", {..})  -> fetch(vspGateNormalizeRunsIndexUrl("...runs_index..."), {..})
s, n1 = re.subn(
    r'fetch\(\s*(["\'][^"\']*runs_index[^"\']*["\'])\s*,',
    r'fetch(vspGateNormalizeRunsIndexUrl(\1),',
    s
)

# 3) wrap fetch("...runs_index...") no opts
s, n2 = re.subn(
    r'fetch\(\s*(["\'][^"\']*runs_index[^"\']*["\'])\s*\)',
    r'fetch(vspGateNormalizeRunsIndexUrl(\1))',
    s
)

# 4) wrap fetch(urlVar, opts) when urlVar name suggests runs
# (best-effort) fetch(runUrl,...) where runUrl/runsUrl/... contains "runs"
s, n3 = re.subn(
    r'fetch\(\s*([A-Za-z_$][\w$]*runs[\w$]*)\s*,',
    r'fetch(vspGateNormalizeRunsIndexUrl(\1),',
    s,
    count=1
)

p.write_text(s, encoding="utf-8")
print(f"[OK] injected helper; wrapped fetch literal runs_index: {n1+n2} ; wrapped runs* var (best-effort): {n3}")
PY

echo "== [2] JS parse must be OK =="
node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

echo "== [3] restart gunicorn 8910 =="
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

sleep 1.2
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] Hard refresh Ctrl+Shift+R, check CI/CD Gate panel"
