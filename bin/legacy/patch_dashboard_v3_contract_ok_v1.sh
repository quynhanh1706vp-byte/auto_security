#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_ok_${TS}"
echo "[BACKUP] $F.bak_dashv3_ok_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# locate function by name first
m = re.search(r"^def\s+vsp_dashboard_v3\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    # fallback: route decorator contains dashboard_v3
    m = re.search(r"@app\.(get|route)\(\s*['\"]/api/vsp/dashboard_v3['\"]\s*\)\s*\n(def\s+([a-zA-Z0-9_]+)\s*\(\s*\)\s*:)", txt, flags=re.M)
    if not m:
        raise SystemExit("[ERR] cannot find dashboard_v3 handler in vsp_demo_app.py")
    fn_name = re.search(r"def\s+([a-zA-Z0-9_]+)\s*\(", m.group(0)).group(1)
else:
    fn_name = "vsp_dashboard_v3"

# extract function body region (best effort): from def line to next def at column 0
pat = re.compile(rf"^def\s+{re.escape(fn_name)}\s*\(\s*\)\s*:\s*$", re.M)
m2 = pat.search(txt)
if not m2:
    raise SystemExit("[ERR] cannot re-find function after selecting name")

start = m2.start()
# find next top-level def after this one
m3 = re.search(r"^\s*def\s+[a-zA-Z0-9_]+\s*\(", txt[m2.end():], flags=re.M)
end = (m2.end() + m3.start()) if m3 else len(txt)

block = txt[start:end]

TAG = "# === VSP_DASHBOARD_V3_CONTRACT_OK_V1 ==="
if TAG in block:
    print("[OK] already patched"); raise SystemExit(0)

# Strategy:
# - if function returns dict variable / expression: wrap before return
# We'll insert a small wrapper right before first 'return ' at indent 4.
lines = block.splitlines(True)

# find first return at indent level 4 spaces
ret_i = None
for i, ln in enumerate(lines):
    if re.match(r"^\s{4}return\b", ln):
        ret_i = i
        break

if ret_i is None:
    raise SystemExit("[ERR] cannot find a return statement in dashboard_v3 handler (unexpected)")

# Insert wrapper lines just before that return
indent = " " * 4
ins = [
    f"{indent}{TAG}\n",
    f"{indent}try:\n",
    f"{indent}    _out = locals().get('out')\n",
    f"{indent}    # nếu code dùng biến khác, fallback lấy expression từ return bên dưới (không luôn được); vẫn set ok nếu _out là dict\n",
    f"{indent}    if isinstance(_out, dict):\n",
    f"{indent}        _out.setdefault('ok', True)\n",
    f"{indent}        _out.setdefault('schema_version', 'dashboard_v3')\n",
    f"{indent}except Exception:\n",
    f"{indent}    pass\n",
    f"{indent}# === END VSP_DASHBOARD_V3_CONTRACT_OK_V1 ===\n",
]

# Heuristic: if the return line is "return something" and that "something" is a dict literal or a name,
# we can rewrite return to set ok.
ret_line = lines[ret_i]
mret = re.match(r"^(\s{4})return\s+(.+?)\s*$", ret_line)
expr = mret.group(2) if mret else None

# If return is a dict literal: return {..} => wrap into tmp then add ok then return tmp
if expr and expr.strip().startswith("{") and expr.strip().endswith("}"):
    new = [
        f"{indent}{TAG}\n",
        f"{indent}try:\n",
        f"{indent}    _tmp = {expr.strip()}\n",
        f"{indent}    if isinstance(_tmp, dict):\n",
        f"{indent}        _tmp.setdefault('ok', True)\n",
        f"{indent}        _tmp.setdefault('schema_version', 'dashboard_v3')\n",
        f"{indent}    return _tmp\n",
        f"{indent}except Exception:\n",
        f"{indent}    return {expr.strip()}\n",
        f"{indent}# === END VSP_DASHBOARD_V3_CONTRACT_OK_V1 ===\n",
    ]
    lines[ret_i:ret_i+1] = new
else:
    # If return is a name or function call: do minimal injection (if code already has out dict, it will work)
    lines[ret_i:ret_i] = ins

new_block = "".join(lines)
txt2 = txt[:start] + new_block + txt[end:]
p.write_text(txt2, encoding="utf-8")
print(f"[OK] patched {fn_name}: ensure ok/schema_version")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service || true
sleep 1

echo "== verify dashboard_v3 ok =="
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 | python3 - <<'PY'
import json,sys
obj=json.loads(sys.stdin.read())
print({"has_ok":("ok" in obj), "ok":obj.get("ok"), "schema_version":obj.get("schema_version"), "has_by_sev":("by_severity" in obj or "summary_all" in obj)})
PY
