#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v2_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1()
m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")
dindent = m.group("dindent")
start = m.start()

m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
fn = txt[start:end]

# find last 'return jsonify(st)' to inject before it
ret_iter = list(re.finditer(r"(?m)^[ \t]*return\s+jsonify\s*\(\s*st\s*\)\s*$", fn))
if not ret_iter:
    raise SystemExit("[ERR] cannot find 'return jsonify(st)' inside run_status_v1()")
ret = ret_iter[-1]
ret_line = fn[ret.start():ret.end()]
indent = re.match(r"^([ \t]*)return", ret_line).group(1)

i1 = indent
i2 = indent + "  "
i3 = indent + "    "

inject = f"""{i1}# {MARK}
{i1}try:
{i2}_json = __import__('json')
{i2}_P = __import__('pathlib').Path
{i2}_req_id = st.get("req_id") or st.get("request_id") or req_id
{i2}# only persist when we already know ci_run_dir/runner_log
{i2}if _req_id and (st.get("ci_run_dir") or st.get("runner_log")):
{i3}# prefer helper if exists
{i3}if "_state_file_path_v1" in globals():
{i3}  sp = _state_file_path_v1(_req_id)
{i3}else:
{i3}  sp = _P(_VSP_UIREQ_DIR) / f"{{_req_id}}.json"
{i3}try:
{i3}  sp.parent.mkdir(parents=True, exist_ok=True)
{i3}except Exception:
{i3}  pass
{i3}cur = {{}}
{i3}try:
{i3}  if sp.exists():
{i3}    cur = _json.loads(sp.read_text(encoding="utf-8", errors="replace"))
{i3}except Exception:
{i3}  cur = {{}}
{i3}cur["request_id"] = cur.get("request_id") or _req_id
{i3}cur["req_id"] = cur.get("req_id") or _req_id
{i3}cur["ci_run_dir"] = st.get("ci_run_dir")
{i3}cur["runner_log"] = st.get("runner_log")
{i3}sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
{i3}try:
{i3}  print("[{MARK}] persisted", str(sp), "ci_run_dir=", cur.get("ci_run_dir"), "runner_log=", cur.get("runner_log"))
{i3}except Exception:
{i3}  pass
{i1}except Exception as _e:
{i2}try:
{i3}print("[{MARK}] WARN", _e)
{i2}except Exception:
{i3}pass

"""

fn2 = fn[:ret.start()] + inject + fn[ret.start():]
txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
