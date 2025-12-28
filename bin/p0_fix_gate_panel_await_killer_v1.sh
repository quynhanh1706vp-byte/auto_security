#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_gate_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_awaitkill_${TS}" && echo "[BACKUP] $F.bak_awaitkill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# 1) REMOVE the broken fallback block that introduced `const u2` + `await fetch(u2,...)`
#    (we remove from the comment OR from 'const u2' until the injected 'else' line)
patterns = [
  r'(?is)\n\s*//\s*P0\s*FIX:\s*fallback:.*?\n\s*else\s*\n',
  r'(?is)\n\s*const\s+u2\s*=\s*["\']\/api\/vsp\/runs_index[^;]*;.*?await\s+fetch\s*\(\s*u2[^;]*;.*?\n\s*else\s*\n',
]
for pat in patterns:
    s_new, n = re.subn(pat, "\n", s, count=1)
    if n:
        s = s_new

# also kill any leftover lines containing await fetch(u2...) to be safe
s = re.sub(r'(?m)^\s*const\s+u2\s*=.*\n', '', s)
s = re.sub(r'(?m)^\s*const\s+r2\s*=\s*await\s+fetch\s*\(\s*u2.*\n', '', s)
s = re.sub(r'(?m)^\s*const\s+j2\s*=\s*await\s+r2\.json\s*\(\s*\)\s*;.*\n', '', s)

# 2) Inject canonical normalizer + fetch wrapper (only if not already present)
if "function vspGateNormalizeRunsIndexUrl" not in s:
    helper = r"""
  // P0 CANONICAL: normalize runs_index URL (avoid empty gate panel)
  function vspGateNormalizeRunsIndexUrl(u){
    try{
      if (typeof u !== "string") return u;
      if (u.indexOf("runs_index") < 0) return u;

      // force filter=0
      if (u.indexOf("filter=") >= 0) u = u.replace(/filter=\d+/g, "filter=0");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "filter=0";

      // ensure hide_empty=0
      if (u.indexOf("hide_empty=") >= 0) u = u.replace(/hide_empty=\d+/g, "hide_empty=0");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "hide_empty=0";

      // ensure limit=1
      if (u.indexOf("limit=") >= 0) u = u.replace(/limit=\d+/g, "limit=1");
      else u += (u.indexOf("?")>=0 ? "&" : "?") + "limit=1";

      return u;
    }catch(_){ return u; }
  }

  // wrapper: always normalize runs_index url before calling fetch
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
        raise SystemExit("[ERR] cannot find 'use strict' in gate panel")
    i=m.end(1)
    s = s[:i] + helper + s[i:]

# 3) Replace bare `fetch(` with `vspGateFetch(` (but keep `.fetch(` / `window.fetch(` intact)
#    Pattern: start or a non-word/non-dot before fetch(
s = re.sub(r'(^|[^.\w$])fetch\s*\(', r'\1vspGateFetch(', s)

p.write_text(s, encoding="utf-8")
print("[OK] removed await-fallback + installed canonical vspGateFetch wrapper")
PY

echo "== [CHECK] JS parse must be OK =="
node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

echo "== [RESTART] gunicorn 8910 =="
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
echo "[DONE] Hard refresh Ctrl+Shift+R, then check CI/CD Gate panel + console"
