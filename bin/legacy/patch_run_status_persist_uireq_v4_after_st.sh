#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v4_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V4_AFTER_ST"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1() block
m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")
dindent = m.group("dindent")
start = m.start()
m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
fn = txt[start:end]

# find st = { ... } dict inside run_status_v1()
st_m = re.search(r"(?ms)^(?P<indent>[ \t]*)st\s*=\s*\{.*?^(?P=indent)\}\s*$", fn)
if not st_m:
    raise SystemExit("[ERR] cannot find 'st = {...}' block inside run_status_v1()")

indent = st_m.group("indent")
inject_indent = indent  # same indent level as "st = ..."
i1 = inject_indent
i2 = inject_indent + "  "
i3 = inject_indent + "    "

inject = f"""
{i1}# {MARK}
{i1}try:
{i2}_json = __import__('json')
{i2}_P = __import__('pathlib').Path
{i2}_req = st.get("req_id") or st.get("request_id") or locals().get("req_id") or locals().get("request_id")
{i2}if not _req:
{i3}_req = locals().get("req_id") or locals().get("request_id")
{i2}if _req:
{i3}# state file path (prefer helper if exists)
{i3}if "_state_file_path_v1" in globals():
{i3}  sp = _state_file_path_v1(_req)
{i3}else:
{i3}  sp = _P(_VSP_UIREQ_DIR) / f"{{_req}}.json"
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
{i3}cur["request_id"] = cur.get("request_id") or _req
{i3}cur["req_id"] = cur.get("req_id") or _req
{i3}# persist what we already computed in run_status
{i3}if st.get("ci_run_dir"):
{i3}  cur["ci_run_dir"] = st.get("ci_run_dir")
{i3}if st.get("runner_log"):
{i3}  cur["runner_log"] = st.get("runner_log")
{i3}try:
{i3}  sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
{i3}  print("[{MARK}] persisted", str(sp), "ci_run_dir=", cur.get("ci_run_dir"))
{i3}except Exception as _we:
{i3}  print("[{MARK}] WARN write_failed", _we)
{i1}except Exception as _e:
{i2}print("[{MARK}] WARN", _e)
"""

# insert right after st-dict block
fn2 = fn[:st_m.end()] + inject + fn[st_m.end():]
txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
