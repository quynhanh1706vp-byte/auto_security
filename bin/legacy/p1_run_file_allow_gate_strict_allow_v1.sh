#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# locate python that defines run_file_allow handler
PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "def run_file_allow" . 2>/dev/null | cut -d: -f1 || true)"
if [ -z "$PYF" ]; then
  PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "run_file_allow" vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null | cut -d: -f1 || true)"
fi
[ -n "$PYF" ] || { echo "[ERR] cannot locate python file defining run_file_allow"; exit 2; }
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "${PYF}.bak_gate_strict_${TS}"
echo "[BACKUP] ${PYF}.bak_gate_strict_${TS}"
echo "[INFO] patch target: $PYF"

python3 - "$PYF" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_GATE_STRICT_ALLOW_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Try to inject inside the run_file_allow function body.
m = re.search(r'(?ms)^(def\s+run_file_allow\s*\(.*?\)\s*:\s*\n)([ \t]+)(.*?)\n(?=def\s|\Z)', s)
if not m:
    # Alternative: route-decorated function (Flask)
    m = re.search(r'(?ms)^(@[^\n]*run_file_allow[^\n]*\n(?:@[^\n]+\n)*)'
                  r'(def\s+([A-Za-z_]\w*)\s*\(.*?\)\s*:\s*\n)([ \t]+)(.*?)\n(?=def\s|\Z)', s)
    if not m:
        print("[ERR] cannot find run_file_allow function block to patch")
        raise SystemExit(2)

# Determine indentation
if m.lastindex and m.lastindex >= 4 and m.group(4):
    indent = m.group(4)
    func_head = m.group(1) + m.group(2)  # decorators+def line
    body = m.group(5)
    head_start, head_end = m.start(1), m.end(2)
    body_start, body_end = m.start(5), m.end(5)
else:
    func_head = m.group(1)
    indent = m.group(2)
    body = m.group(3)
    head_start, head_end = m.start(1), m.end(1)
    body_start, body_end = m.start(3), m.end(3)

# Build injected guard: allow reports/* gate + forbid fallback to SUMMARY for gate paths
inject = f"""\n{indent}# {marker}\n{indent}# Commercial rule: gate JSON must never fallback to SUMMARY.txt.\n{indent}# Allow gate under reports/ for legacy runs.\n{indent}GATE_STRICT_PATHS = {{\n{indent}    "run_gate.json",\n{indent}    "run_gate_summary.json",\n{indent}    "reports/run_gate.json",\n{indent}    "reports/run_gate_summary.json",\n{indent}}}\n{indent}try:\n{indent}    _req_path = (path or "").strip()\n{indent}except Exception:\n{indent}    _req_path = ""\n{indent}# Normalize URL-encoded slashes handled upstream; keep exact match here.\n{indent}if _req_path in GATE_STRICT_PATHS:\n{indent}    # force-allow these paths (still safe because exact allowlist)\n{indent}    _vsp_force_allow_gate = True\n{indent}else:\n{indent}    _vsp_force_allow_gate = False\n"""

# Insert inject right after the first occurrence of reading query params (prefer after 'path =' assignment)
# If not found, insert at top of body.
pos = None
for pat in [
    r'(?m)^\s*path\s*=\s*.*$',
    r'(?m)^\s*rid\s*=\s*.*$',
    r'(?m)^\s*path\s*=\s*request\.(args|get)\.get\(',
]:
    mm = re.search(pat, body)
    if mm:
        # insert after that line
        line_end = body.find("\n", mm.end())
        if line_end == -1:
            line_end = len(body)
        pos = line_end + 1
        break
if pos is None:
    pos = 0

body2 = body[:pos] + inject + body[pos:]

# Patch allow-check: look for pattern that denies non-allowed path, and OR in force-allow flag.
# We do a conservative insertion: find first "if path not in ALLOW" style and modify.
body3 = body2
repls = 0

patterns = [
    # if path not in ALLOW: return 403
    (r'(?m)^(\s*)if\s+(\w+)\s+not\s+in\s+(\w+)\s*:\s*\n(\s*)return\s+.*403.*$',
     r'\1if (\2 not in \3) and (not _vsp_force_allow_gate):\n\4return \g<0>'.replace(r'\g<0>', '')),  # placeholder; will handle differently
]
# The above is too tricky; instead do simpler direct search for "403 FORBIDDEN" return block and inject guard just before it.
if "403" in body3 and "_vsp_force_allow_gate" in body3:
    # insert before first return 403
    m403 = re.search(r'(?ms)^(?P<i>\s*)return\s+.*403.*$', body3)
    if m403:
        i = m403.group("i")
        guard = f"{i}if _vsp_force_allow_gate:\n{i}    pass  # skip forbid for gate paths\n{i}else:\n"
        # indent the original return line one level deeper under else:
        orig = m403.group(0)
        orig_indented = re.sub(r'(?m)^', i + "  ", orig)
        body3 = body3[:m403.start()] + guard + orig_indented + body3[m403.end():]
        repls += 1

# Patch fallback-to-summary: detect if response is falling back by setting X-VSP-Fallback-Path or choosing SUMMARY.txt
# We insert an early 404 JSON if gate path requested but resolved file isn't JSON or doesn't exist.
# Insert near any "fallback" keyword; otherwise append near end of function body (safe).
insert_404 = f"""\n{indent}# {marker}_NO_FALLBACK\n{indent}# If gate path requested but resolver cannot provide JSON, return 404 JSON (no SUMMARY fallback).\n{indent}if _vsp_force_allow_gate:\n{indent}    # best-effort: if handler computed any chosen file var, it should be 'fp'/'file_path'/'target'.\n{indent}    pass\n"""
# We'll inject this as comment + later we patch by searching for setting X-VSP-Fallback-Path and guarding.
body4 = body3
mx = re.search(r'(?m)^\s*.*X-VSP-Fallback-Path.*$', body4)
if mx:
    # put a guard a few lines before header set
    start_line = body4.rfind("\n", 0, mx.start())
    start_line = 0 if start_line < 0 else start_line + 1
    body4 = body4[:start_line] + f"{indent}# {marker}_GUARD_BEFORE_FALLBACK_HEADER\n{indent}if _vsp_force_allow_gate:\n{indent}    return ({{\"ok\": False, \"err\": \"gate file missing\", \"rid\": rid, \"path\": _req_path}}, 404)\n\n" + body4[start_line:]
    repls += 1
else:
    # append near top (after inject) but guarded: only triggers when path is gate AND content-type would be non-json
    body4 = body4.replace(
        inject,
        inject + f"\n{indent}# {marker}_EARLY_STRICT\n{indent}# NOTE: downstream code must not fallback to SUMMARY for gate paths.\n"
    )

# Stitch back
s2 = s[:body_start] + body4 + s[body_end:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched {p} (repls={repls})")
PY

echo "== py_compile =="
python3 -m py_compile "$PYF" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.6

echo "== quick verify :8910 =="
curl -fsS -I http://127.0.0.1:8910/vsp5 | head -n 5 || true
echo "[DONE] Patch applied. Now test fetch for reports/run_gate_summary.json on latest RID."
