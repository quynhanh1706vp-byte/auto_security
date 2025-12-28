#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dedupe_mark_v8bfix_${TS}"
echo "[BACKUP] ${F}.bak_dedupe_mark_v8bfix_${TS}"

python3 -c '
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)
out=[]
did_alias=False

for line in lines:
    out.append(line)
    if line.strip() == "# --- /VSP_MARK_FIX_P0_V6 ---":
        out.append("\n# VSP_MARK_DEDUPE_SAFE_P0_V8B: keep legacy alias\n")
        out.append("try:\n    MARKB\nexcept Exception:\n    MARKB = MARK_B  # legacy alias for old code paths\n")
        out.append("# /VSP_MARK_DEDUPE_SAFE_P0_V8B\n\n")
        did_alias=True

txt="".join(out)

# disable legacy reassignment MARK="VSP_MARK_P0"
txt = re.sub(r"(?m)^\\s*MARK\\s*=\\s*[\\\"\\\']VSP_MARK_P0[\\\"\\\']\\s*$",
             "# (P0_V8B) disabled legacy MARK reassignment", txt)

# disable the tiny legacy block if present
pat = re.compile(r"(?ms)^\\s*#\\s*VSP_MARK_FIX_P0_V3\\s*\\n(?:\\s*#.*\\n)*\\s*MARK\\s*=.*\\n\\s*MARKB\\s*=.*\\n")
txt = pat.sub("# VSP_MARK_FIX_P0_V3 (P0_V8B disabled: use MARK + MARK_B + MARKB alias)\\n", txt)

p.write_text(txt, encoding="utf-8")
print(f"[OK] did_alias={did_alias}")
'

echo "== py_compile + import check =="
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
ss -ltnp | grep -E ":8910\\b" || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n "1,25p"
