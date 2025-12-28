#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p62hotfix_v2_${TS}"
echo "[OK] backup ${APP}.bak_p62hotfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

comma200 = re.compile(r'^\s*,\s*200\s*$')
changed = 0
fixed_lines = []

for i in range(len(lines)):
    if not comma200.match(lines[i] or ""):
        continue

    # find previous non-empty line
    j = i - 1
    while j >= 0 and (lines[j].strip() == ""):
        j -= 1

    # if no previous line, just remove it
    if j < 0:
        lines[i] = ""
        changed += 1
        fixed_lines.append(i+1)
        continue

    prev = lines[j].rstrip("\n")
    # if prev already ends with ", 200" (or contains it), just drop current stray
    if re.search(r',\s*200\s*$', prev):
        lines[i] = ""
        changed += 1
        fixed_lines.append(i+1)
        continue

    # append ", 200" to previous line
    lines[j] = prev.rstrip() + ", 200\n"
    lines[i] = ""
    changed += 1
    fixed_lines.append(i+1)

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] fixed stray ', 200' lines: {changed}")
if fixed_lines:
    print("[OK] touched original line numbers:", fixed_lines[:30], ("..." if len(fixed_lines)>30 else ""))
PY

echo "== py_compile =="
if python3 -m py_compile "$APP"; then
  echo "[OK] py_compile OK"
else
  echo "[ERR] py_compile still failing -> show context"
  python3 - <<'PY'
import py_compile, traceback
from pathlib import Path

APP="vsp_demo_app.py"
try:
    py_compile.compile(APP, doraise=True)
except Exception as e:
    tb = traceback.format_exc()
    print(tb)
    # try extract line number from common SyntaxError string
    ln = None
    if hasattr(e, "lineno"):
        ln = e.lineno
    if not ln:
        import re
        m = re.search(r'line\s+(\d+)', tb)
        if m: ln = int(m.group(1))
    if ln:
        s = Path(APP).read_text(encoding="utf-8", errors="replace").splitlines()
        a = max(1, ln-20); b = min(len(s), ln+20)
        print(f"== context {a}..{b} (line {ln}) ==")
        for k in range(a, b+1):
            mark = ">>" if k==ln else "  "
            print(f"{mark}{k:6d}: {s[k-1]}")
PY
  exit 2
fi

echo "== restart service =="
sudo systemctl restart "$SVC"

echo "== wait /vsp5 up =="
ok=0
for i in $(seq 1 25); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.4
done
[ "$ok" = "1" ] || { echo "[ERR] UI not up"; exit 2; }
echo "[OK] /vsp5 200"
