#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_mark_builtin_p0_v6_${TS}"
echo "[BACKUP] ${F}.bak_mark_builtin_p0_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# remove old injected blocks (v5) to avoid confusion
s = re.sub(r"(?s)\n# --- VSP_MARK_FIX_P0_V5 ---.*?# --- /VSP_MARK_FIX_P0_V5 ---\n", "\n", s)

MARKER = "VSP_MARK_FIX_P0_V6"

# find insertion point: after shebang/encoding/docstring
lines = s.splitlines(True)
i = 0
if lines and lines[0].startswith("#!"):
    i += 1
if i < len(lines) and "coding" in lines[i]:
    i += 1

# module docstring skip
if i < len(lines) and re.match(r'^\s*[ruRU]{0,2}("""|\'\'\')', lines[i]):
    q = '"""' if '"""' in lines[i] else "'''"
    i += 1
    while i < len(lines) and q not in lines[i]:
        i += 1
    if i < len(lines):
        i += 1

inject = (
    f"\n# --- {MARKER} ---\n"
    f"# Fix: make MARK always available (also via builtins to avoid NameError in any scope).\n"
    f"import builtins as _vsp_builtins\n"
    f"if not hasattr(_vsp_builtins, 'MARK'):\n"
    f"    _vsp_builtins.MARK = 'VSP_UI_GATEWAY_MARK_V1'\n"
    f"MARK = getattr(_vsp_builtins, 'MARK', 'VSP_UI_GATEWAY_MARK_V1')\n"
    f"MARK_B = (MARK.encode() if isinstance(MARK, str) else str(MARK).encode())\n"
    f"# --- /{MARKER} ---\n\n"
)

if MARKER not in s:
    lines.insert(i, inject)
    s = "".join(lines)

# also replace MARK.encode() usages to MARK_B (safe)
s = re.sub(r"\bMARK\.encode\(\)", "MARK_B", s)

p.write_text(s, encoding="utf-8")
print("[OK] injected builtins MARK block + MARK_B")
PY

echo "== py_compile =="
python3 -m py_compile "$F"

echo "== truncate old error log (so we know if NEW errors still happen) =="
mkdir -p out_ci
sudo truncate -s 0 out_ci/ui_8910.error.log || true

echo "== daemon-reload (silence unit warning) =="
sudo systemctl daemon-reload || true

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service
sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,60p' || true

echo "== quick verify =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || true
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,30p' || true

echo "== hit /runs once (force handler path) =="
curl -sS http://127.0.0.1:8910/runs >/dev/null || true

echo "== check NEW error log for MARK NameError =="
if grep -n "NameError: name 'MARK' is not defined" out_ci/ui_8910.error.log >/dev/null 2>&1; then
  echo "[FAIL] MARK NameError still present (NEW) -> show tail:"
  tail -n 220 out_ci/ui_8910.error.log
  exit 4
else
  echo "[OK] no NEW MARK NameError"
fi
