#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_forceok_${TS}"
echo "[BACKUP] $F.bak_dashv3_forceok_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# locate def vsp_dashboard_v3 at col 0
m = re.search(r"^def\s+vsp_dashboard_v3\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_dashboard_v3()")

start = m.start()
# find next top-level def after this one
m_next = re.search(r"^\s*def\s+[A-Za-z0-9_]+\s*\(", txt[m.end():], flags=re.M)
end = (m.end() + m_next.start()) if m_next else len(txt)

block = txt[start:end]
TAG = "# === VSP_DASHBOARD_V3_FORCE_OK_V2 ==="
if TAG in block:
    print("[OK] already patched"); raise SystemExit(0)

lines = block.splitlines(True)

def should_skip(expr: str) -> bool:
    e = expr.strip()
    # nếu trả Response/jsonify thì không bọc
    bad = ["jsonify(", "make_response(", "Response(", "send_file(", "redirect("]
    return any(x in e for x in bad)

out_lines = []
for ln in lines:
    mret = re.match(r"^(\s{4})return\s+(.+?)\s*$", ln)
    if not mret:
        out_lines.append(ln); continue

    indent = mret.group(1)
    expr = mret.group(2)
    if should_skip(expr):
        out_lines.append(ln); continue

    # replace return expr -> _r=expr; set ok/schema if dict; return _r
    out_lines.append(f"{indent}{TAG}\n")
    out_lines.append(f"{indent}_r = {expr}\n")
    out_lines.append(f"{indent}try:\n")
    out_lines.append(f"{indent}    if isinstance(_r, dict):\n")
    out_lines.append(f"{indent}        _r.setdefault('ok', True)\n")
    out_lines.append(f"{indent}        _r.setdefault('schema_version', 'dashboard_v3')\n")
    out_lines.append(f"{indent}except Exception:\n")
    out_lines.append(f"{indent}    pass\n")
    out_lines.append(f"{indent}return _r\n")
    out_lines.append(f"{indent}# === END VSP_DASHBOARD_V3_FORCE_OK_V2 ===\n")

new_block = "".join(out_lines)
txt2 = txt[:start] + new_block + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched vsp_dashboard_v3(): force ok/schema on dict returns")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify dashboard_v3 ok =="
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 \
| python3 -c 'import json,sys; o=json.loads(sys.stdin.read()); print({"has_ok":"ok" in o,"ok":o.get("ok"),"schema_version":o.get("schema_version"),"has_by_sev":("by_severity" in o) or ("summary_all" in o and "by_severity" in (o["summary_all"] or {}))})'
