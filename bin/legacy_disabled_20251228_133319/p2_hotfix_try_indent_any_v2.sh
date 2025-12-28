#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_tryindentV2_${TS}"
echo "[BACKUP] ${F}.bak_tryindentV2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(errors="ignore").splitlines(True)

def leading_ws(s: str) -> str:
    m = re.match(r'^([ \t]*)', s)
    return m.group(1) if m else ""

changed = 0
hits = []

for i in range(len(lines)-1):
    a = lines[i]
    b = lines[i+1]
    # line i: try:
    if re.match(r'^[ \t]*try:\s*(#.*)?$', a.rstrip("\n")):
        # next line: import os as _os (maybe has spaces/tabs)
        if re.match(r'^[ \t]*import\s+os\s+as\s+_os\b', b.rstrip("\n")):
            try_ws = leading_ws(a)
            want = try_ws + "    "   # indent inside try-block
            # if b is not indented enough => fix
            if not b.startswith(want):
                b_new = want + b.lstrip(" \t")
                lines[i+1] = b_new
                changed += 1
                hits.append(i+1)

p.write_text("".join(lines), encoding="utf-8")
print("[OK] try-indent fixes applied =", changed, "at lines (0-based indexes)=", hits[:8])

# must compile
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

echo "== restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC"
  sleep 0.5
  sudo systemctl status "$SVC" -l --no-pager || true
fi

echo "== quick probe =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for u in /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done
