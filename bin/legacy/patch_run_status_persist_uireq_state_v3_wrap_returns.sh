#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v3_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V3_WRAP_RETURNS"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# cut run_status_v1() body
m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")
dindent = m.group("dindent")
start = m.start()
m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
fn = txt[start:end]

# match return jsonify(st) with optional status code: return jsonify(st) or return jsonify(st), 200
ret_pat = re.compile(r"(?m)^(?P<indent>[ \t]*)return\s+jsonify\s*\(\s*st\s*\)\s*(?:,\s*(?P<code>\d+)\s*)?$")
rets = list(ret_pat.finditer(fn))
if not rets:
    # fallback: some code writes "return jsonify(st), 200" with extra spaces; still covered above,
    # so if none found, just fail loud
    raise SystemExit("[ERR] cannot find any 'return jsonify(st)' (with optional ,code) inside run_status_v1()")

out = []
last = 0
n = 0

for r in rets:
    out.append(fn[last:r.start()])
    indent = r.group("indent")
    code = r.group("code")
    i1 = indent
    i2 = indent + "  "
    i3 = indent + "    "

    inject = f"""{i1}# {MARK}
{i1}if not locals().get("_vsp_persisted_uireq_v3"):
{i2}locals()["_vsp_persisted_uireq_v3"] = True
{i2}try:
{i3}_json = __import__('json')
{i3}_P = __import__('pathlib').Path
{i3}_req_id = st.get("req_id") or st.get("request_id") or req_id
{i3}if _req_id and (st.get("ci_run_dir") or st.get("runner_log")):
{i3}  if "_state_file_path_v1" in globals():
{i3}    sp = _state_file_path_v1(_req_id)
{i3}  else:
{i3}    sp = _P(_VSP_UIREQ_DIR) / f"{{_req_id}}.json"
{i3}  try:
{i3}    sp.parent.mkdir(parents=True, exist_ok=True)
{i3}  except Exception:
{i3}    pass
{i3}  cur = {{}}
{i3}  try:
{i3}    if sp.exists():
{i3}      cur = _json.loads(sp.read_text(encoding="utf-8", errors="replace"))
{i3}  except Exception:
{i3}    cur = {{}}
{i3}  cur["request_id"] = cur.get("request_id") or _req_id
{i3}  cur["req_id"] = cur.get("req_id") or _req_id
{i3}  cur["ci_run_dir"] = st.get("ci_run_dir")
{i3}  cur["runner_log"] = st.get("runner_log")
{i3}  try:
{i3}    sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
{i3}    print("[{MARK}] persisted", str(sp))
{i3}  except Exception as _we:
{i3}    print("[{MARK}] WARN write_failed", _we)
{i2}except Exception as _e:
{i3}print("[{MARK}] WARN", _e)

"""
    out.append(inject)
    # keep original return line
    ret_line = f"{indent}return jsonify(st)" + (f", {code}" if code else "") + "\n"
    out.append(ret_line)
    n += 1
    last = r.end()

out.append(fn[last:])
fn2 = "".join(out)

txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "wrapped_returns=", n)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
