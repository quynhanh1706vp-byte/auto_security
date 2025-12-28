#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
ELOG="out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dedupe_mark_v8c_${TS}"
echo "[BACKUP] ${F}.bak_dedupe_mark_v8c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out = []
inserted_alias = False
commented_legacy = 0

for line in lines:
    out.append(line)
    if line.strip() == "# --- /VSP_MARK_FIX_P0_V6 ---" and not inserted_alias:
        out.append("\n# VSP_MARK_DEDUPE_SAFE_P0_V8C: keep legacy alias (do not override MARK)\n")
        out.append("MARKB = MARK_B  # legacy alias\n")
        out.append("# /VSP_MARK_DEDUPE_SAFE_P0_V8C\n\n")
        inserted_alias = True

txt = "".join(out)

# 1) Comment legacy reassignment MARK="VSP_MARK_P0"
txt, n1 = re.subn(r'(?m)^\s*MARK\s*=\s*["\']VSP_MARK_P0["\']\s*$',
                  '# (P0_V8C) disabled legacy MARK reassignment', txt)
commented_legacy += n1

# 2) Comment legacy MARKB=b"..."
txt, n2 = re.subn(r'(?m)^\s*MARKB\s*=\s*b["\']VSP_MARK_P0["\']\s*$',
                  '# (P0_V8C) disabled legacy MARKB bytes (use MARKB=MARK_B alias)', txt)
commented_legacy += n2

p.write_text(txt, encoding="utf-8")
print(f"[OK] inserted_alias={inserted_alias} commented_legacy={commented_legacy}")
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

echo "== truncate error log (NEW only) =="
mkdir -p out_ci
sudo truncate -s 0 "$ELOG" 2>/dev/null || true

echo "== restart service =="
sudo systemctl restart "$SVC"
sleep 0.8

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p'
echo "[OK] v8c applied, service healthy"
