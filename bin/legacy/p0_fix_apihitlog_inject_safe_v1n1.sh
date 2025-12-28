#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

APP="vsp_demo_app.py"
[ -f "$APP" ] || err "missing $APP"

# 1) restore from latest bak_apihit_*
BK="$(ls -1t ${APP}.bak_apihit_* 2>/dev/null | head -n 1 || true)"
[ -n "$BK" ] || err "no backup found: ${APP}.bak_apihit_*"

cp -f "$BK" "$APP"
ok "restored: $APP <= $BK"

# 2) patch safely (insert before if __name__ == '__main__')
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_before_v1n1_${TS}"
ok "backup: ${APP}.bak_before_v1n1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_API_HITLOG_V1N1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Ensure imports exist
if re.search(r'^\s*import\s+re\s*$', s, flags=re.M) is None:
    s = "import re\n" + s

# Ensure request imported (extend existing flask import if possible)
if not re.search(r'from\s+flask\s+import\s+.*\brequest\b', s):
    m = re.search(r'^(from\s+flask\s+import\s+.+)$', s, flags=re.M)
    if m and "request" not in m.group(1):
        line = m.group(1).rstrip()
        s = s[:m.start(1)] + (line + ", request") + s[m.end(1):]
    else:
        s = "from flask import request\n" + s

hook = f'''
# {MARK}: commercial audit logging for /api/vsp/* (no gunicorn accesslog required)
try:
    @app.before_request
    def __vsp_api_hitlog_v1n1():
        try:
            if request.path and request.path.startswith("/api/vsp/"):
                fp = getattr(request, "full_path", request.path) or request.path
                # normalize noisy ts=
                fp = re.sub(r'([?&])ts=\\d+', r'\\1ts=', fp)
                print(f"[VSP_API_HIT] {{request.method}} {{fp}}")
        except Exception:
            pass
except Exception:
    pass
'''

# Insert before main guard (safest top-level spot)
main_re = re.compile(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', re.M)
m = main_re.search(s)
if m:
    s = s[:m.start()] + hook + "\n" + s[m.start():]
else:
    s = s + "\n\n" + hook + "\n"

p.write_text(s, encoding="utf-8")

# compile check
py_compile.compile(str(p), doraise=True)
print("[OK] injected safely + py_compile OK")
PY

ok "py_compile OK: $APP"

echo "== [NEXT] restart service manually (safe) =="
echo "sudo systemctl restart vsp-ui-8910.service"
