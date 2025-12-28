#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_forcejson_route_${TS}"
echo "[BACKUP] $PYF.bak_forcejson_route_${TS}"

python3 - << 'PY'
import re, json
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_FORCE_JSON_BY_ROUTE_V2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find decorator line containing run_status_v1 route
# capture blueprint var: @bp.route("...run_status_v1/<...>")
route_re = re.compile(r"""(?m)^\s*@\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*route\(\s*['"]([^'"]*run_status_v1/[^'"]*)['"]""")
m = route_re.search(txt)
if not m:
    print("[ERR] cannot find @<bp>.route(...run_status_v1/...) in file")
    raise SystemExit(2)

bp_var = m.group(1)
route_str = m.group(2)

# Find the def right after this decorator block
after = txt.find("\n", m.end())
def_re = re.compile(r"(?m)^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*:")
mdef = def_re.search(txt, after)
if not mdef:
    print("[ERR] cannot find def <fn>(<param>) after route decorator")
    raise SystemExit(3)

fn_name = mdef.group(1)
param = mdef.group(2)
fn_indent = re.match(r"(?m)^(\s*)def\s+", txt[mdef.start():]).group(1)

# Determine function block end: next top-level decorator/def with same indent
rest = txt[mdef.end():]
mnext = re.search(r"(?m)^\s*(?:" + re.escape(fn_indent) + r"def\s+|" + re.escape(fn_indent) + r"@)", rest)
end = (mdef.end() + mnext.start()) if mnext else len(txt)

start = mdef.start()
old_block = txt[start:end]

new_block = f"""{fn_indent}# === {MARK} (auto) ===
{fn_indent}@{bp_var}.route("{route_str}")
{fn_indent}def {fn_name}({param}):
{fn_indent}  # commercial: ALWAYS return JSON (never text/html)
{fn_indent}  try:
{fn_indent}    import json, re
{fn_indent}    from pathlib import Path
{fn_indent}    from flask import jsonify
{fn_indent}    req_id = {param}
{fn_indent}    ui_root = Path(__file__).resolve().parents[1]  # .../ui
{fn_indent}    st_dir = ui_root / "out_ci" / "uireq_v1"
{fn_indent}    st_path = st_dir / f"{{req_id}}.json"
{fn_indent}    if not st_path.exists():
{fn_indent}      return jsonify({{"ok": False, "req_id": req_id, "error": "not_found"}}), 404
{fn_indent}    st = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{fn_indent}    st["ok"] = True
{fn_indent}    st["req_id"] = req_id

{fn_indent}    # tail from log_file
{fn_indent}    log_file = st.get("log_file") or str(st_dir / f"{{req_id}}.log")
{fn_indent}    st["log_file"] = log_file
{fn_indent}    lf = Path(log_file)
{fn_indent}    tail = ""
{fn_indent}    if lf.exists():
{fn_indent}      lines = lf.read_text(encoding="utf-8", errors="ignore").splitlines()
{fn_indent}      tail = "\\n".join(lines[-250:])
{fn_indent}    st["tail"] = tail

{fn_indent}    # infer ci_run_dir if empty
{fn_indent}    if not st.get("ci_run_dir"):
{fn_indent}      target = ((st.get("meta") or {{}}).get("target") or "").strip()
{fn_indent}      if target:
{fn_indent}        base = Path(target) / "out_ci"
{fn_indent}        if base.is_dir():
{fn_indent}          cands = sorted(base.glob("VSP_CI_*"), key=lambda x: x.stat().st_mtime, reverse=True)
{fn_indent}          if cands:
{fn_indent}            st["ci_run_dir"] = str(cands[0])

{fn_indent}    # parse stage from tail: ===== [i/8] NAME =====
{fn_indent}    stage = st.get("stage") or {{"i":0,"n":8,"name":"","progress":0}}
{fn_indent}    stage_re = re.compile(r"^=+\\s*\\[(\\d+)\\s*/\\s*(\\d+)\\]\\s*(.*?)\\s*=+$")
{fn_indent}    last = None
{fn_indent}    for line in (tail or "").splitlines():
{fn_indent}      mm = stage_re.match(line.strip())
{fn_indent}      if mm:
{fn_indent}        last = (int(mm.group(1)), int(mm.group(2)), (mm.group(3) or "").strip())
{fn_indent}    if last:
{fn_indent}      i, n, name = last
{fn_indent}      stage["i"] = i
{fn_indent}      stage["n"] = n
{fn_indent}      stage["name"] = name
{fn_indent}      stage["progress"] = int(round((i / n) * 100)) if n else 0
{fn_indent}    st["stage"] = stage
{fn_indent}    st["stage_index"] = int(stage.get("i", 0) or 0)
{fn_indent}    st["stage_total"] = int(stage.get("n", 0) or 0)
{fn_indent}    st["stage_name"] = str(stage.get("name", "") or "")
{fn_indent}    st["progress_pct"] = int(stage.get("progress", 0) or 0)

{fn_indent}    # write back (so UI reads consistent)
{fn_indent}    st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
{fn_indent}    return jsonify(st)
{fn_indent}  except Exception as e:
{fn_indent}    from flask import jsonify
{fn_indent}    return jsonify({{"ok": False, "req_id": {param}, "error": str(e)}}), 500
{fn_indent}# === END {MARK} ===
"""

txt2 = txt[:start] + new_block + "\n" + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched handler by route. bp=", bp_var, "fn=", fn_name, "param=", param)
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
