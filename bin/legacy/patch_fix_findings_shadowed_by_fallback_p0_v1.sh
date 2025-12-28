#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_findings_fallback_${TS}"
echo "[BACKUP] ${APP}.bak_fix_findings_fallback_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Find any decorator route that matches /api/vsp/<path:...> or /api/vsp/<...>
# This wildcard is the one shadowing /api/vsp/findings
pat = re.compile(r'@app\.(?:get|route)\(\s*[\'"](/api/vsp/<[^\'"]+>)[\'"]\s*(?:,|\))', re.M)

hits = list(pat.finditer(s))
if not hits:
    print("[OK] no wildcard /api/vsp/<...> route found. Nothing to patch.")
    raise SystemExit(0)

# Patch ALL wildcard /api/vsp/<...> to a compat-only path so it won't shadow real endpoints.
# Keep run_status_v1/<REQ_ID> untouched (it doesn't match this pattern).
def repl(m):
    old = m.group(1)
    # Move compat endpoint under a clearly-namespaced path
    # so /api/vsp/findings, /api/vsp/dashboard_commercial_v2... won't be eaten.
    new = "/api/vsp/_compat/" + old.split("/api/vsp/",1)[1]
    return m.group(0).replace(old, new)

s2, n = pat.subn(repl, s)
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched wildcard routes: {n}")
print("[NOTE] moved /api/vsp/<...> -> /api/vsp/_compat/<...> (compat only)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile: $APP"

echo
echo "[NEXT] restart gunicorn 8910, then test:"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/findings | jq 'keys, (.items|length? // .items_len? // length? // empty)' -C"
echo "  python3 - <<'PY'\nimport vsp_demo_app as m\nprint('wildcards=', [r.rule for r in m.app.url_map.iter_rules() if r.rule.startswith('/api/vsp/<')])\nprint('compat=', [r.rule for r in m.app.url_map.iter_rules() if r.rule.startswith('/api/vsp/_compat/')])\nPY"
