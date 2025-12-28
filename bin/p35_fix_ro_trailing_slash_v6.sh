#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p35_ro_slash_v6_${TS}"
echo "[BACKUP] ${W}.bak_p35_ro_slash_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P34P35_SINGLE_WSGI_WRAP_V5"
if MARK not in s:
    raise SystemExit("[ERR] V5 wrapper not found; abort")

# Patch only the small path-matching part inside V5 wrapper application()
# Find the first occurrence of the path check and replace with normalized variant.
pat = re.compile(r"""
(?xms)
(?P<indent>^[ \t]*)path=\(environ\.get\("PATH_INFO"\)\s*or\s*""\)
\R(?P=indent)if\s+path\s+in\s+\(("/api/vsp/rule_overrides_v1","/api/vsp/rule_overrides_ui_v1"|"/api/vsp/rule_overrides_ui_v1","/api/vsp/rule_overrides_v1")\)\:
""")

m=pat.search(s)
if not m:
    raise SystemExit("[ERR] could not locate V5 rule_overrides path check pattern")

indent=m.group("indent")
replacement = (
    f'{indent}path=(environ.get("PATH_INFO") or "")\n'
    f'{indent}p = path[:-1] if (path.endswith("/") and path != "/") else path\n'
    f'{indent}if p in ("/api/vsp/rule_overrides_v1","/api/vsp/rule_overrides_ui_v1"):\n'
)

s2 = s[:m.start()] + replacement + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched: normalize trailing slash for rule_overrides in V5")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true

echo "== [warm selfcheck] =="
ok=0
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck ok (try#$i)"; ok=1; break
  else
    sleep 0.2
  fi
done
[ "$ok" -eq 1 ] || { echo "[ERR] selfcheck still failing"; exit 2; }

echo "== [CHECK] slash + non-slash both should be ok JSON =="
for u in "$BASE/api/vsp/rule_overrides_v1" "$BASE/api/vsp/rule_overrides_v1/"; do
  echo "-- $u --"
  curl -sS -D- -o /tmp/_ro_check.bin "$u" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}'
  head -c 220 /tmp/_ro_check.bin; echo
done
