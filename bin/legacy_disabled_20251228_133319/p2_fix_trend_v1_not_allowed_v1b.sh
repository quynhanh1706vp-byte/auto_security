#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [0] locate python file containing /api/vsp/trend_v1 =="
CAND="$(grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' \
  '/api/vsp/trend_v1' . | grep -E '\.py:' | head -n 1 || true)"

if [ -z "$CAND" ]; then
  echo "[ERR] cannot locate '/api/vsp/trend_v1' in any .py under $(pwd)"
  echo "[HINT] try: grep -RIn '/api/vsp/trend_v1' ."
  exit 2
fi

FILE="$(echo "$CAND" | cut -d: -f1)"
LINE="$(echo "$CAND" | cut -d: -f2)"
echo "[INFO] found in: $FILE:$LINE"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$FILE" "${FILE}.bak_trendfix_${TS}"
echo "[BACKUP] ${FILE}.bak_trendfix_${TS}"

python3 - "$FILE" <<'PY'
from pathlib import Path
import re, sys, textwrap

path = Path(sys.argv[1])
s = path.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_TREND_V1_ALLOW_AND_ROBUST_V1B"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# Find any line containing the route string
idx = s.find("/api/vsp/trend_v1")
if idx < 0:
    print("[ERR] route string not found in file at runtime (unexpected)")
    raise SystemExit(2)

# Find decorator start: go upward from the line containing route, capture first '@...(' line
route_line_start = s.rfind("\n", 0, idx) + 1
# walk upward line by line
lines = s.splitlines(True)
# compute line number of route occurrence
line_no = s.count("\n", 0, idx)
i = line_no
decor_start = None
while i >= 0:
    l = lines[i]
    if re.match(r'^\s*@', l):
        decor_start = i
        # continue upward to include stacked decorators
        i -= 1
        while i >= 0 and re.match(r'^\s*@', lines[i]):
            decor_start = i
            i -= 1
        break
    # stop if we hit a blank gap too far without decorator
    if re.match(r'^\s*def\s+|^\s*class\s+', l):
        break
    i -= 1

if decor_start is None:
    print("[ERR] cannot find decorator line above trend_v1 route occurrence")
    raise SystemExit(2)

# Find def line after decorators
j = decor_start
while j < len(lines) and re.match(r'^\s*@', lines[j]):
    j += 1
if j >= len(lines) or not re.match(r'^\s*(async\s+def|def)\s+\w+\s*\(', lines[j]):
    print("[ERR] cannot find def line after decorators")
    raise SystemExit(2)

def_line = j
def_indent = re.match(r'^(\s*)', lines[def_line]).group(1)

# Determine function block end: next line that has indentation <= def_indent and starts a new decorator/def/class
end = len(lines)
for k in range(def_line+1, len(lines)):
    l = lines[k]
    if not l.strip():
        continue
    ind = re.match(r'^(\s*)', l).group(1)
    if len(ind.replace("\t","    ")) <= len(def_indent.replace("\t","    ")) and re.match(r'^\s*(@|def\s+|async\s+def\s+|class\s+)', l):
        end = k
        break

# Extract the object used in the first decorator: @OBJ.route( ... ) or @OBJ.get( ... )
m = re.match(r'^\s*@\s*([A-Za-z0-9_.]+)\.(route|get|post|put|delete|patch)\s*\(', lines[decor_start])
obj = m.group(1) if m else "app"

indent_decor = re.match(r'^(\s*)', lines[decor_start]).group(1)

new_block = textwrap.dedent(f"""
{indent_decor}@{obj}.route("/api/vsp/trend_v1", methods=["GET"])
{indent_decor}def api_vsp_trend_v1():
{indent_decor}    \"\"\"{MARK}
{indent_decor}    Robust trend endpoint: never returns ok:false 'not allowed'.
{indent_decor}    Schema: ok, rid_requested, limit, points[{{
{indent_decor}      label, run_id, total, ts
{indent_decor}    }}]
{indent_decor}    \"\"\"
{indent_decor}    import os, json, datetime
{indent_decor}    from flask import request, jsonify

{indent_decor}    rid = (request.args.get("rid") or "").strip()
{indent_decor}    limit = int(request.args.get("limit") or 20)
{indent_decor}    if limit < 5: limit = 5
{indent_decor}    if limit > 80: limit = 80

{indent_decor}    roots = [
{indent_decor}        "/home/test/Data/SECURITY_BUNDLE/out_ci",
{indent_decor}        "/home/test/Data/SECURITY_BUNDLE/out",
{indent_decor}    ]
{indent_decor}    roots = [r for r in roots if os.path.isdir(r)]

{indent_decor}    def list_run_dirs():
{indent_decor}        dirs = []
{indent_decor}        for r in roots:
{indent_decor}            try:
{indent_decor}                for name in os.listdir(r):
{indent_decor}                    if not (name.startswith("VSP_") or name.startswith("RUN_")):
{indent_decor}                        continue
{indent_decor}                    full = os.path.join(r, name)
{indent_decor}                    if os.path.isdir(full):
{indent_decor}                        try:
{indent_decor}                            mt = os.path.getmtime(full)
{indent_decor}                        except Exception:
{indent_decor}                            mt = 0
{indent_decor}                        dirs.append((mt, name, full))
{indent_decor}            except Exception:
{indent_decor}                pass
{indent_decor}        dirs.sort(key=lambda x: x[0], reverse=True)
{indent_decor}        return dirs

{indent_decor}    def load_json(path):
{indent_decor}        try:
{indent_decor}            with open(path, "r", encoding="utf-8") as f:
{indent_decor}                return json.load(f)
{indent_decor}        except Exception:
{indent_decor}            return None

{indent_decor}    def get_total_from_gate(j):
{indent_decor}        if not isinstance(j, dict): return None
{indent_decor}        for k in ("total", "total_findings", "findings_total", "total_unified"):
{indent_decor}            v = j.get(k)
{indent_decor}            if isinstance(v, int): return v
{indent_decor}        c = j.get("counts") or j.get("severity_counts") or j.get("by_severity")
{indent_decor}        if isinstance(c, dict):
{indent_decor}            sm = 0
{indent_decor}            for vv in c.values():
{indent_decor}                if isinstance(vv, int): sm += vv
{indent_decor}            return sm
{indent_decor}        return None

{indent_decor}    points = []
{indent_decor}    for mt, name, d in list_run_dirs()[: max(limit*3, limit) ]:
{indent_decor}        gate = load_json(os.path.join(d, "run_gate_summary.json")) or load_json(os.path.join(d, "reports", "run_gate_summary.json"))
{indent_decor}        total = get_total_from_gate(gate)
{indent_decor}        if total is None:
{indent_decor}            fu = load_json(os.path.join(d, "findings_unified.json")) or load_json(os.path.join(d, "reports", "findings_unified.json"))
{indent_decor}            if isinstance(fu, list):
{indent_decor}                total = len(fu)
{indent_decor}            elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
{indent_decor}                total = len(fu.get("findings"))
{indent_decor}        if total is None:
{indent_decor}            continue

{indent_decor}        ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
{indent_decor}        label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
{indent_decor}        points.append({{"label": label, "run_id": name, "total": int(total), "ts": ts}})
{indent_decor}        if len(points) >= limit:
{indent_decor}            break

{indent_decor}    return jsonify({{"ok": True, "rid_requested": rid, "limit": limit, "points": points}})
""").lstrip("\n")

out = "".join(lines[:decor_start]) + new_block + "\n" + "".join(lines[end:])
path.write_text(out, encoding="utf-8")
print("[OK] patched:", path)
PY

echo "== [1] py_compile patched file =="
python3 -m py_compile "$FILE"
echo "[OK] py_compile OK"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-units --type=service | grep -q "$SVC"; then
    echo "[INFO] restarting $SVC ..."
    sudo systemctl restart "$SVC" || systemctl restart "$SVC" || true
  else
    echo "[INFO] service $SVC not found in systemctl list (skip restart)"
  fi
else
  echo "[INFO] no systemctl (skip restart)"
fi

echo "== [2] smoke trend_v1 =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[SMOKE] RID=$RID"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 260; echo
