#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need head

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_v3_register_${TS}"
echo "[BACKUP] ${APP}.bak_fix_v3_register_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = r"# === CIO V3 REGISTER \(AUTO\) ==="

# 1) remove existing (possibly broken) register block anywhere
# We remove from marker line to the first line that contains "pass" after it (inclusive).
pat = re.compile(rf'(?ms)^\s*{MARK}\s*\n.*?^\s*pass\s*\n')
s2, n = pat.subn("", s)
if n == 0:
    # fallback: remove marker + next 6 lines
    s2 = re.sub(rf'(?m)^\s*{MARK}\s*\n(?:.*\n){{0,8}}', "", s2)
s = s2

# 2) build canonical register block (top-level safe)
block = textwrap.dedent("""
# === CIO V3 REGISTER (AUTO) ===
from vsp_api_v3 import register_v3 as _register_v3
try:
    _register_v3(app)
except Exception:
    pass
""").strip("\n") + "\n"

# 3) insert after app = Flask(...)
m = re.search(r'(?m)^\s*app\s*=\s*Flask\([^\n]*\)\s*$', s)
if not m:
    # fallback: first "app = Flask(" line
    m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)

if not m:
    # last resort: append at EOF (still top-level)
    s = s.rstrip() + "\n\n" + block
    print("[WARN] app=Flask not found; appended v3 register at EOF")
else:
    nl = s.find("\n", m.end())
    s = s[:nl+1] + block + "\n" + s[nl+1:]
    print("[OK] inserted v3 register right after app=Flask(...)")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

echo "== [RESTART] =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [SMOKE] v3 endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 180; echo
curl -fsS "$BASE/api/vsp/dashboard_v3" | head -c 220; echo
echo "[DONE]"
