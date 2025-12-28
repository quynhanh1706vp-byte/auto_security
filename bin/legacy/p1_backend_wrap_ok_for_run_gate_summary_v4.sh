#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")
MARK = "VSP_P1_OKWRAP_RUNGATE_SUMMARY_V4"

F = Path("vsp_demo_app.py")
if not F.exists():
    raise SystemExit("[ERR] missing vsp_demo_app.py (run in /home/test/Data/SECURITY_BUNDLE/ui)")

s = F.read_text(encoding="utf-8", errors="replace")
bak = F.with_name(F.name + f".bak_okwrap_v4_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# 1) locate the route decorator block that contains /api/vsp/run_file_allow, then the next def
#    robust against multi-line decorators
m = re.search(
    r"(?s)(^|\n)\s*@.*?route\s*\(\s*(?:.|\n)*?['\"]/api/vsp/run_file_allow['\"].*?\)\s*\n\s*def\s+(?P<fname>[A-Za-z_]\w*)\s*\(",
    s,
    flags=re.MULTILINE,
)
if not m:
    # fallback: direct string search then next def
    pos = s.find("/api/vsp/run_file_allow")
    if pos < 0:
        raise SystemExit("[ERR] cannot find route '/api/vsp/run_file_allow' in vsp_demo_app.py")
    mdef = re.search(r"(?m)^\s*def\s+(?P<fname>[A-Za-z_]\w*)\s*\(", s[pos:])
    if not mdef:
        raise SystemExit("[ERR] found route string but cannot find following def")
    fname = mdef.group("fname")
    # find def absolute start
    abs_def = pos + mdef.start()
else:
    fname = m.group("fname")
    # find the def line start for that fname (first after decorator match)
    abs_def = s.find(f"def {fname}", m.start())

print("[INFO] handler function =", fname)

# 2) extract function block (top-level def -> next top-level def)
mstart = re.search(r"(?m)^\s*def\s+" + re.escape(fname) + r"\s*\(", s[abs_def:])
if not mstart:
    raise SystemExit("[ERR] cannot locate def start for handler")
start = abs_def + mstart.start()

mnext = re.search(r"(?m)^\s*def\s+\w+\s*\(", s[start + 1:])
end = (start + 1 + mnext.start()) if mnext else len(s)

block = s[start:end]

# 3) find return send_file(...) inside handler
mret = re.search(r"(?m)^(?P<ind>\s*)return\s+.*?\bsend_file\s*\(\s*(?P<arg>[^,\n\)]+)", block)
if not mret:
    # try send_from_directory
    mret = re.search(r"(?m)^(?P<ind>\s*)return\s+.*?\bsend_from_directory\s*\(\s*(?P<arg>[^,\n\)]+)", block)
if not mret:
    raise SystemExit("[ERR] cannot find return send_file/send_from_directory inside handler; need a different patch point")

ind = mret.group("ind")
arg = mret.group("arg").strip()

# 4) inject a wrapper before the return line.
#    We do NOT assume variables exist; we read them from locals() safely.
inject = f"""{ind}# ===================== {MARK} =====================
{ind}try:
{ind}    _path = (locals().get("path") or locals().get("rel_path") or locals().get("p") or "")
{ind}    _rid  = (locals().get("rid")  or locals().get("run_id") or locals().get("rid_latest") or "")
{ind}    if _path and (str(_path).endswith("run_gate_summary.json") or str(_path).endswith("run_gate.json")):
{ind}        import json as _json
{ind}        from pathlib import Path as _Path
{ind}        _jsonify = globals().get("jsonify")
{ind}        if _jsonify is None:
{ind}            import flask as _flask
{ind}            _jsonify = _flask.jsonify
{ind}        _fp = {arg}
{ind}        _fp = _Path(str(_fp))
{ind}        _j = _json.loads(_fp.read_text(encoding="utf-8", errors="replace"))
{ind}        if isinstance(_j, dict):
{ind}            _j.setdefault("ok", True)
{ind}            if _rid:
{ind}                _j.setdefault("rid", _rid)
{ind}                _j.setdefault("run_id", _rid)
{ind}        return _jsonify(_j)
{ind}except Exception:
{ind}    pass
{ind}# ===================== /{MARK} =====================
"""

insert_at = mret.start()
block2 = block[:insert_at] + inject + block[insert_at:]
s2 = s[:start] + block2 + s[end:]

F.write_text(s2, encoding="utf-8")
py_compile.compile(str(F), doraise=True)
print("[OK] patched:", F)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] ok-wrap v4 applied."
