#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dedupe_mark_v8b_${TS}"
echo "[BACKUP] ${F}.bak_dedupe_mark_v8b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out = []
did_alias = False
did_comment_reassign = 0

# helper: after the P0_V6 block end, inject alias if not present
# We detect the end line: "# --- /VSP_MARK_FIX_P0_V6 ---"
for i, line in enumerate(lines):
    out.append(line)
    if line.strip() == "# --- /VSP_MARK_FIX_P0_V6 ---":
        # if later in file there is legacy MARKB usage, keep alias here
        # add only if not already defined
        out.append("\n# VSP_MARK_DEDUPE_SAFE_P0_V8B: keep legacy alias\n")
        out.append("try:\n")
        out.append("    MARKB\n")
        out.append("except Exception:\n")
        out.append("    MARKB = MARK_B  # legacy alias for old code paths\n")
        out.append("# /VSP_MARK_DEDUPE_SAFE_P0_V8B\n\n")
        did_alias = True

txt = "".join(out)

# Comment out any reassign MARK = "VSP_MARK_P0" that appears AFTER P0_V6 block
# (we only comment the first occurrences; keep it minimal)
def comment_mark_reassign(m):
    return "# (P0_V8B) disabled legacy MARK reassignment -> " + m.group(0)

txt2, n = re.subn(r'(?m)^\s*MARK\s*=\s*["\']VSP_MARK_P0["\']\s*$', comment_mark_reassign, txt)
did_comment_reassign = n
txt = txt2

# Also, if there's the tiny legacy block header, keep it but disable content safely
# # VSP_MARK_FIX_P0_V3 / MARK="VSP_MARK_P0" / MARKB=b"..."
pat_block = re.compile(r'(?ms)^\s*#\s*VSP_MARK_FIX_P0_V3\s*\n(?:\s*#.*\n)*\s*MARK\s*=.*\n\s*MARKB\s*=.*\n')
if pat_block.search(txt):
    txt = pat_block.sub("# VSP_MARK_FIX_P0_V3 (P0_V8B disabled: use MARK + MARK_B + MARKB alias)\n", txt, count=1)

p.write_text(txt, encoding="utf-8")
print(f"[OK] did_alias={did_alias} commented_mark_reassign={did_comment_reassign}")
PY

echo "== py_compile + import check (BEFORE restart) =="
python3 -m py_compile "$F"
python3 - <<'PY'
import traceback
try:
    import wsgi_vsp_ui_gateway
    print("[OK] import wsgi_vsp_ui_gateway OK")
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
    raise SystemExit(3)
PY

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p'
