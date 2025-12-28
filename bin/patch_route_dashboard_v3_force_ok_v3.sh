#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_route_forceok_${TS}"
echo "[BACKUP] $F.bak_dashv3_route_forceok_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_ROUTE_DASHBOARD_V3_FORCE_OK_V3 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

lines = t.splitlines(True)

# find decorator line containing /api/vsp/dashboard_v3 (not latest)
idxs = []
for i, ln in enumerate(lines):
    if "/api/vsp/dashboard_v3" in ln and "dashboard_v3_latest" not in ln:
        idxs.append(i)

if not idxs:
    raise SystemExit("[ERR] cannot find decorator line containing /api/vsp/dashboard_v3")

# pick first match, then find the def right after decorators
i0 = idxs[0]
j = i0
while j < len(lines) and not re.match(r"^def\s+[A-Za-z0-9_]+\s*\(", lines[j]):
    j += 1
if j >= len(lines):
    raise SystemExit("[ERR] cannot find handler def after dashboard_v3 decorator")

# function name
mfn = re.match(r"^def\s+([A-Za-z0-9_]+)\s*\(", lines[j])
fn = mfn.group(1)

# function region: from def line j to next top-level def
start = sum(len(x) for x in lines[:j])
k = j + 1
while k < len(lines) and not re.match(r"^def\s+[A-Za-z0-9_]+\s*\(", lines[k]):
    k += 1
end = sum(len(x) for x in lines[:k])

block = t[start:end]

def wrap_return(line: str) -> str:
    # Wrap return dict or jsonify(arg)
    m = re.match(r"^(\s{4})return\s+(.+?)\s*$", line)
    if not m:
        return line
    indent, expr = m.group(1), m.group(2).strip()

    # skip send_file/redirect/Response/make_response raw
    skip_tokens = ["send_file(", "redirect(", "Response(", "make_response("]
    if any(tok in expr for tok in skip_tokens):
        return line

    # handle return jsonify(X)
    mjson = re.match(r"^jsonify\((.*)\)\s*$", expr)
    if mjson:
        arg = mjson.group(1).strip()
        return (
            f"{indent}{TAG}\n"
            f"{indent}_r = {arg}\n"
            f"{indent}try:\n"
            f"{indent}    if isinstance(_r, dict):\n"
            f"{indent}        _r.setdefault('ok', True)\n"
            f"{indent}        _r.setdefault('schema_version', 'dashboard_v3')\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
            f"{indent}return jsonify(_r)\n"
        )

    # default: return <expr>  (Flask will JSONify dict automatically)
    return (
        f"{indent}{TAG}\n"
        f"{indent}_r = {expr}\n"
        f"{indent}try:\n"
        f"{indent}    if isinstance(_r, dict):\n"
        f"{indent}        _r.setdefault('ok', True)\n"
        f"{indent}        _r.setdefault('schema_version', 'dashboard_v3')\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
        f"{indent}return _r\n"
    )

# rewrite function body lines
b_lines = block.splitlines(True)
out = []
for ln in b_lines:
    if re.match(r"^\s{4}return\b", ln):
        out.append(wrap_return(ln))
    else:
        out.append(ln)

new_block = "".join(out)
t2 = t[:start] + new_block + t[end:]
p.write_text(t2, encoding="utf-8")

print(f"[OK] patched dashboard_v3 route handler: {fn}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify dashboard_v3 ok =="
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 \
| python3 -c 'import json,sys; o=json.loads(sys.stdin.read()); print({"has_ok":"ok" in o,"ok":o.get("ok"),"schema_version":o.get("schema_version"),"has_by_sev":("by_severity" in o) or ("summary_all" in o and "by_severity" in (o["summary_all"] or {}))})'
