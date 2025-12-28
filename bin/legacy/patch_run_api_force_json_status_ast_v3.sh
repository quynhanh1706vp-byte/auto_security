#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_forcejson_ast_${TS}"
echo "[BACKUP] $PYF.bak_forcejson_ast_${TS}"

python3 - << 'PY'
import ast, re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
src = p.read_text(encoding="utf-8", errors="ignore")
lines = src.splitlines(True)

MARK = "VSP_FORCE_JSON_STATUS_AST_V3"
if MARK in src:
    print("[OK] already patched")
    raise SystemExit(0)

tree = ast.parse(src)

target = None  # (start_line, end_line, bp_name, route_str, fn_name, param_name, indent)
for node in tree.body:
    if isinstance(node, ast.FunctionDef):
        route_hit = None
        bp_name = None
        route_str = None
        for dec in node.decorator_list:
            if isinstance(dec, ast.Call) and isinstance(dec.func, ast.Attribute):
                # @bp.route(...) or @bp.get(...)
                if dec.args and isinstance(dec.args[0], ast.Constant) and isinstance(dec.args[0].value, str):
                    s = dec.args[0].value
                    if "run_status_v1" in s:
                        route_hit = True
                        route_str = s
                        if isinstance(dec.func.value, ast.Name):
                            bp_name = dec.func.value.id
                        else:
                            bp_name = "bp"
        if route_hit:
            # assume 1 param
            param_name = node.args.args[0].arg if node.args.args else "req_id"
            start_line = min([getattr(d, "lineno", node.lineno) for d in node.decorator_list] + [node.lineno])
            end_line = getattr(node, "end_lineno", node.lineno)
            # indent from def line
            def_line = lines[node.lineno - 1]
            indent = re.match(r"^(\s*)", def_line).group(1)
            target = (start_line, end_line, bp_name or "bp", route_str, node.name, param_name, indent)
            break

if not target:
    print("[ERR] cannot locate handler with decorator route containing 'run_status_v1'")
    raise SystemExit(2)

start_line, end_line, bp, route_str, fn_name, param, indent = target

new_block = f"""{indent}# === {MARK} (auto) ===
{indent}@{bp}.route("{route_str}", methods=["GET"])
{indent}def {fn_name}({param}):
{indent}  # commercial: ALWAYS JSON
{indent}  from flask import jsonify
{indent}  import json, re, time
{indent}  from pathlib import Path
{indent}  req_id = {param}
{indent}  ui_root = Path(__file__).resolve().parents[1]  # .../ui
{indent}  st_dir = ui_root / "out_ci" / "uireq_v1"
{indent}  st_path = st_dir / f"{{req_id}}.json"
{indent}  if not st_path.exists():
{indent}    return jsonify({{"ok": False, "req_id": req_id, "error": "not_found"}}), 404
{indent}  try:
{indent}    st = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{indent}  except Exception:
{indent}    st = {{}}
{indent}  st["ok"] = True
{indent}  st["req_id"] = req_id

{indent}  # tail from log_file
{indent}  log_file = st.get("log_file") or str(st_dir / f"{{req_id}}.log")
{indent}  st["log_file"] = log_file
{indent}  lf = Path(log_file)
{indent}  tail = ""
{indent}  if lf.exists():
{indent}    try:
{indent}      arr = lf.read_text(encoding="utf-8", errors="ignore").splitlines()
{indent}      tail = "\\n".join(arr[-250:])
{indent}    except Exception:
{indent}      tail = ""
{indent}  st["tail"] = tail

{indent}  # fill ci_run_dir from log if empty: RUN_DIR    = ...
{indent}  if not st.get("ci_run_dir"):
{indent}    m = re.search(r"^\\[VSP_CI_OUTER\\]\\s*RUN_DIR\\s*=\\s*(.+)$", tail, flags=re.M)
{indent}    if m:
{indent}      st["ci_run_dir"] = m.group(1).strip()

{indent}  # stage/progress from tool banner: ===== [i/8] NAME =====
{indent}  stage = st.get("stage") or {{"i":0,"n":8,"name":"","progress":0}}
{indent}  st_re = re.compile(r"^=+\\s*\\[(\\d+)\\s*/\\s*(\\d+)\\]\\s*(.*?)\\s*=+$")
{indent}  last = None
{indent}  for line in (tail or "").splitlines():
{indent}    mm = st_re.match(line.strip())
{indent}    if mm:
{indent}      last = (int(mm.group(1)), int(mm.group(2)), (mm.group(3) or "").strip())
{indent}  if last:
{indent}    i, n, name = last
{indent}    stage["i"] = i
{indent}    stage["n"] = n
{indent}    stage["name"] = name
{indent}    stage["progress"] = int(round((i/n)*100)) if n else 0
{indent}  st["stage"] = stage
{indent}  st["stage_index"] = int(stage.get("i",0) or 0)
{indent}  st["stage_total"] = int(stage.get("n",0) or 0)
{indent}  st["stage_name"] = str(stage.get("name","") or "")
{indent}  st["progress_pct"] = int(stage.get("progress",0) or 0)

{indent}  # mark final if outer ended (success/fail) based on log keywords
{indent}  if "=== VSP CI OUTER:" in tail:
{indent}    if "THẤT BẠI" in tail:
{indent}      st["status"] = "FAIL"
{indent}      st["final"] = True
{indent}    if "THÀNH CÔNG" in tail:
{indent}      st["status"] = "DONE"
{indent}      st["final"] = True

{indent}  # persist
{indent}  st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}  return jsonify(st)
{indent}# === END {MARK} ===
"""

# replace [start_line-1 : end_line]
new_lines = new_block.splitlines(True)
lines[start_line-1:end_line] = new_lines
p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched run_status handler:", fn_name, "route=", route_str)
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
