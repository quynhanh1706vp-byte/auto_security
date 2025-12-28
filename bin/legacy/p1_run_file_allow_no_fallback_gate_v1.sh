#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# locate python that defines run_file_allow
PYF="$(grep -RIn --exclude='*.bak_*' -m1 "run_file_allow" . 2>/dev/null | cut -d: -f1 || true)"
[ -n "$PYF" ] || { echo "[ERR] cannot locate python file containing 'run_file_allow'"; exit 2; }
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "${PYF}.bak_no_fallback_gate_${TS}"
echo "[BACKUP] ${PYF}.bak_no_fallback_gate_${TS}"
echo "[INFO] patch target: $PYF"

python3 - "$PYF" <<'PY'
import sys,re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

marker="VSP_P1_RUN_FILE_ALLOW_NO_FALLBACK_GATE_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) widen allowlist if it exists (add reports/run_gate*.json)
added_allow=0
allow_items = [
  "run_gate.json","run_gate_summary.json",
  "reports/run_gate.json","reports/run_gate_summary.json",
]
# try common allowlist patterns: allow = set([...]) or ALLOW = {...}
m = re.search(r'(?P<name>\bALLOW(?:_PATHS)?\b)\s*=\s*(?P<rhs>set\(\s*\[.*?\]\s*\)|\{.*?\})', s, flags=re.S)
if m:
    name=m.group("name")
    rhs=m.group("rhs")
    # crude: inject missing strings before closing
    for it in allow_items:
        if it in rhs:
            continue
        # insert before last ] or }
        rhs2 = re.sub(r'(\]\s*\)\s*$)', rf'  "{it}",\n\1', rhs, flags=re.S)
        if rhs2 == rhs:
            rhs2 = re.sub(r'(\}\s*$)', rf'  "{it}",\n\1', rhs, flags=re.S)
        rhs = rhs2
        added_allow += 1
    s = s[:m.start("rhs")] + rhs + s[m.end("rhs"):]
else:
    # if no allowlist found, do nothing (still apply no-fallback)
    pass

# 2) inject "no fallback" guard near the fallback branch
# We look for a fallback marker header 'X-VSP-Fallback-Path' or 'Fallback-Path'
inserted=0
fallback_anchor = re.search(r'X-VSP-Fallback-Path|Fallback-Path', s)
if fallback_anchor:
    # inject helper near top of function area: after 'def run_file_allow' line
    func = re.search(r'def\s+run_file_allow\s*\(.*?\)\s*:', s)
    if func:
        # find next line after function def
        i = func.end()
        # insert just after function signature line
        ins = (
            f"\n    # {marker}\n"
            f"    _NO_FALLBACK = {{'run_gate.json','run_gate_summary.json','reports/run_gate.json','reports/run_gate_summary.json'}}\n"
            f"    # NOTE: gate JSON must never fallback to SUMMARY.txt; missing => 404 so UI can fallback to last-good RID.\n"
        )
        s = s[:i] + ins + s[i:]
        inserted += 1

# 3) patch the actual fallback behavior: if requested path in _NO_FALLBACK and file missing => 404 (no fallback)
# Try to find a block that checks existence and then sets fallback_path="SUMMARY.txt" or similar.
# We'll insert a guard right before any fallback assignment to SUMMARY.txt.
pat = re.compile(r'(fallback_path\s*=\s*[\'"]SUMMARY\.txt[\'"])', re.M)
m2 = pat.search(s)
if m2:
    # attempt to find nearby variable holding requested path, common names: path, rel_path, req_path
    guard = (
        "    # gate no-fallback guard\n"
        "    try:\n"
        "        _req_path = (path if 'path' in locals() else (rel_path if 'rel_path' in locals() else (req_path if 'req_path' in locals() else None)))\n"
        "    except Exception:\n"
        "        _req_path = None\n"
        "    if _req_path in _NO_FALLBACK:\n"
        "        from flask import jsonify\n"
        "        return jsonify({'ok': False, 'err': 'file not found', 'rid': rid, 'path': _req_path}), 404\n\n"
    )
    s = s[:m2.start()] + guard + s[m2.start():]
    inserted += 1

# 4) if we failed to find SUMMARY fallback assignment, still append a minimal guard by wrapping send_file/return part:
if inserted == 0:
    # append a very small note at EOF so we don't silently do nothing
    s += f"\n# {marker}: WARN could not auto-inject no-fallback guard (pattern not found)\n"

# footer marker
s += f"\n# {marker}: allow_added={added_allow}\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] patched: {p}")
print(f"[OK] allow_added={added_allow}")
print(f"[OK] injected_blocks={inserted}")
PY

echo "== py_compile =="
python3 -m py_compile "$PYF" && echo "[OK] py_compile OK"

echo "[DONE] restart UI service then hard refresh /vsp5"
echo "  sudo systemctl restart vsp-ui-8910.service || true"
echo "  (Ctrl+Shift+R on /vsp5)"
