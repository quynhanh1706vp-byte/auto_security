#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# locate real python defining def run_file_allow(...)
PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "def run_file_allow" . 2>/dev/null | cut -d: -f1 || true)"
if [ -z "$PYF" ]; then
  # fallback: find route decorator mentioning run_file_allow
  PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "run_file_allow" vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null | cut -d: -f1 || true)"
fi
[ -n "$PYF" ] || { echo "[ERR] cannot locate python file defining run_file_allow"; exit 2; }
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "${PYF}.bak_no_fallback_gate_${TS}"
echo "[BACKUP] ${PYF}.bak_no_fallback_gate_${TS}"
echo "[INFO] patch target: $PYF"

python3 - "$PYF" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_RUN_FILE_ALLOW_NO_FALLBACK_GATE_V1B"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

no_fb = "{'run_gate.json','run_gate_summary.json','reports/run_gate.json','reports/run_gate_summary.json'}"

# 1) Ensure allowlist contains reports/run_gate*.json (common allowlist styles)
allow_add = 0
allow_items = ["run_gate.json","run_gate_summary.json","reports/run_gate.json","reports/run_gate_summary.json"]

m = re.search(r'(?P<lhs>\bALLOW(?:_PATHS)?\b\s*=\s*)(?P<rhs>set\(\s*\[.*?\]\s*\)|\{.*?\})', s, flags=re.S)
if m:
    rhs = m.group("rhs")
    for it in allow_items:
        if it in rhs: 
            continue
        rhs2 = re.sub(r'(\]\s*\)\s*$)', rf'  "{it}",\n\1', rhs, flags=re.S)
        if rhs2 == rhs:
            rhs2 = re.sub(r'(\}\s*$)', rf'  "{it}",\n\1', rhs, flags=re.S)
        rhs = rhs2
        allow_add += 1
    s = s[:m.start("rhs")] + rhs + s[m.end("rhs"):]

# 2) Inject NO-FALLBACK guard inside run_file_allow: after reading query args for path
# find function block start
func = re.search(r'(def\s+run_file_allow\s*\(.*?\)\s*:)', s, flags=re.S)
if not func:
    raise SystemExit("[ERR] cannot find def run_file_allow(...)")

# find first occurrence of request.args.get('path') after func
after = s[func.end():]
mp = re.search(r'(?m)^\s*(?P<var>(path|rel_path|req_path))\s*=\s*request\.args\.get\(\s*[\'"]path[\'"]', after)
if not mp:
    # sometimes it's request.values.get
    mp = re.search(r'(?m)^\s*(?P<var>(path|rel_path|req_path))\s*=\s*request\.(args|values)\.get\(\s*[\'"]path[\'"]', after)
if not mp:
    # if can't find, still try to guard before SUMMARY fallback assignment later
    pass
else:
    var = mp.group("var")
    ins = (
        f"\n    # {marker}\n"
        f"    _NO_FALLBACK = {no_fb}\n"
        f"    _req_path = {var}\n"
    )
    # insert right after that assignment line
    insert_at = func.end() + mp.end()
    s = s[:insert_at] + ins + s[insert_at:]

# 3) Prevent fallback-to-SUMMARY for gate JSON: before any SUMMARY fallback assignment
# insert guard immediately before setting fallback_path='SUMMARY.txt' (or similar)
pat = re.compile(r'(?m)^(?P<indent>\s*)(?P<lhs>fallback_path|fallback|alt_path)\s*=\s*[\'"]SUMMARY\.txt[\'"]\s*$', re.M)
m2 = pat.search(s)
if m2:
    ind = m2.group("indent")
    guard = (
        f"{ind}# gate JSON must not fallback\n"
        f"{ind}try:\n"
        f"{ind}    _p = _req_path if '_req_path' in locals() else (path if 'path' in locals() else None)\n"
        f"{ind}except Exception:\n"
        f"{ind}    _p = None\n"
        f"{ind}if _p in _NO_FALLBACK:\n"
        f"{ind}    from flask import jsonify\n"
        f"{ind}    return jsonify({{'ok': False, 'err': 'file not found', 'rid': rid, 'path': _p}}), 404\n"
        "\n"
    )
    s = s[:m2.start()] + guard + s[m2.start():]
else:
    # fallback pattern not found; append marker so we know injection didn't happen
    s += f"\n# {marker}: WARN fallback SUMMARY.txt pattern not found; please adjust manually.\n"

s += f"\n# {marker}: allow_add={allow_add}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
print("[OK] allow_add:", allow_add)
PY

echo "== py_compile =="
python3 -m py_compile "$PYF" && echo "[OK] py_compile OK"

echo "[DONE] restart service: sudo systemctl restart vsp-ui-8910.service"
