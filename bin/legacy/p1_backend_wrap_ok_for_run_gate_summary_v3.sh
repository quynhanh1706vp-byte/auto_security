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
MARK = "VSP_P1_OKWRAP_RUNGATE_SUMMARY_V3"

F = Path("vsp_demo_app.py")
if not F.exists():
    raise SystemExit("[ERR] missing vsp_demo_app.py (run this in /home/test/Data/SECURITY_BUNDLE/ui)")

s = F.read_text(encoding="utf-8", errors="replace")
bak = F.with_name(F.name + f".bak_okwrap_v3_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# Find run_file_allow function block
m = re.search(r"(?m)^def\s+run_file_allow\s*\(.*?\)\s*:\s*\n", s)
if not m:
    raise SystemExit("[ERR] cannot find def run_file_allow(...) in vsp_demo_app.py")

start = m.start()
m2 = re.search(r"(?m)^\s*def\s+\w+\s*\(", s[m.end():])
end = (m.end() + m2.start()) if m2 else len(s)

block = s[start:end]

# Find first `return send_file(<arg>...` inside the block
m3 = re.search(r"(?m)^(?P<ind>\s*)return\s+(?P<fn>send_file)\s*\(\s*(?P<arg>[^,\n\)]+)", block)
if not m3:
    # sometimes uses flask.send_file
    m3 = re.search(r"(?m)^(?P<ind>\s*)return\s+(?P<fn>\w+\.\s*send_file)\s*\(\s*(?P<arg>[^,\n\)]+)", block)
if not m3:
    raise SystemExit("[ERR] cannot find return send_file(...) inside run_file_allow in vsp_demo_app.py")

ind = m3.group("ind")
arg = m3.group("arg").strip()

inject = f"""{ind}# ===================== {MARK} =====================
{ind}try:
{ind}    if path and (str(path).endswith("run_gate_summary.json") or str(path).endswith("run_gate.json")):
{ind}        import json as _json
{ind}        from pathlib import Path as _Path
{ind}        _jsonify = globals().get("jsonify")
{ind}        if _jsonify is None:
{ind}            import flask as _flask
{ind}            _jsonify = _flask.jsonify
{ind}        _p = {arg}
{ind}        _p = _Path(str(_p))
{ind}        _j = _json.loads(_p.read_text(encoding="utf-8", errors="replace"))
{ind}        if isinstance(_j, dict):
{ind}            _j.setdefault("ok", True)
{ind}            if rid:
{ind}                _j.setdefault("rid", rid)
{ind}                _j.setdefault("run_id", rid)
{ind}        return _jsonify(_j)
{ind}except Exception:
{ind}    pass
{ind}# ===================== /{MARK} =====================
"""

# Insert inject right before that return line
insert_at = m3.start()
block2 = block[:insert_at] + inject + block[insert_at:]

s2 = s[:start] + block2 + s[end:]
F.write_text(s2, encoding="utf-8")

py_compile.compile(str(F), doraise=True)
print("[OK] patched:", F)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] backend ok-wrap v3 applied."
