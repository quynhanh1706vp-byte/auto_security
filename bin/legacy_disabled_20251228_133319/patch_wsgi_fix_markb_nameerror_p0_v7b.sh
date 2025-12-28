#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_markb_v7b_${TS}"
echo "[BACKUP] ${F}.bak_fix_markb_v7b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK = "VSP_MARKB_FIX_V7B"

out = []
fixed = 0
inserted_guard = False

for line in s:
    # Fix the exact buggy self-referential pattern (and close variants)
    if re.search(r'^\s*MARK_B\s*=\s*\(\s*MARK_B\s*if\s*isinstance\(\s*MARK\s*,\s*str\s*\)\s*else\s*str\(\s*MARK\s*\)\.encode\(\s*\)\s*\)\s*$', line):
        indent = re.match(r'^(\s*)', line).group(1)
        out.append(f"{indent}# {MARK}: fix self-referential MARK_B\n")
        out.append(f"{indent}MARK_B = (MARK.encode('utf-8') if isinstance(MARK, str) else str(MARK).encode('utf-8'))\n")
        fixed += 1
        continue

    # Also catch any line that assigns MARK_B using MARK_B on RHS (paranoid)
    if re.search(r'^\s*MARK_B\s*=\s*\(.*\bMARK_B\b.*\)\s*$', line):
        indent = re.match(r'^(\s*)', line).group(1)
        out.append(f"{indent}# {MARK}: normalize MARK_B\n")
        out.append(f"{indent}MARK_B = (MARK.encode('utf-8') if isinstance(MARK, str) else str(MARK).encode('utf-8'))\n")
        fixed += 1
        continue

    out.append(line)

txt = "".join(out)

# Ensure MARK exists early (safe) — only inject once near top if missing
if "MARK =" not in txt and "builtins" not in txt:
    # insert after imports (best-effort)
    lines = txt.splitlines(True)
    ins = 0
    # find last import line
    last_imp = -1
    for i,l in enumerate(lines[:120]):
        if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', l):
            last_imp = i
    ins = last_imp + 1 if last_imp >= 0 else 0

    guard = (
        f"\n# {MARK}: ensure MARK is always defined\n"
        "import builtins as _vsp_builtins\n"
        "if not hasattr(_vsp_builtins, 'MARK'):\n"
        "    _vsp_builtins.MARK = 'VSP_UI_GATEWAY_MARK_V1'\n"
        "MARK = getattr(_vsp_builtins, 'MARK', 'VSP_UI_GATEWAY_MARK_V1')\n"
        "MARK_B = (MARK.encode('utf-8') if isinstance(MARK, str) else str(MARK).encode('utf-8'))\n"
        f"# /{MARK}\n\n"
    )
    lines.insert(ins, guard)
    txt = "".join(lines)
    inserted_guard = True

p.write_text(txt, encoding="utf-8")
print(f"[OK] patched={fixed} inserted_guard={inserted_guard}")
PY

echo "== py_compile =="
python3 -m py_compile "$F"

echo "== truncate error log (so we only see NEW errors) =="
mkdir -p out_ci
sudo truncate -s 0 out_ci/ui_8910.error.log || true

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed vsp-ui-8910.service || true
sudo systemctl restart vsp-ui-8910.service

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p'
