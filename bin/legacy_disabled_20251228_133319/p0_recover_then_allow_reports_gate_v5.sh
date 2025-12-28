#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [1] snapshot current (possibly broken) =="
cp -f "$W" "${W}.bak_v5_snapshot_${TS}"
echo "[SNAPSHOT] ${W}.bak_v5_snapshot_${TS}"

echo "== [2] restore latest compiling backup =="
python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# prefer current if compile OK
if ok(w):
    print("[OK] current wsgi already compiles; keep it")
    raise SystemExit(0)

for b in baks:
    if ok(b):
        w.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored from:", b.name)
        raise SystemExit(0)

raise SystemExit("[ERR] no compiling backup found")
PY

echo "== [3] patch ONLY list-style allowlists that contain run_gate_summary.json =="
cp -f "$W" "${W}.bak_v5_before_patch_${TS}"
python3 - <<'PY'
from pathlib import Path
import re, sys

MARK = "VSP_P0_ALLOW_REPORTS_GATE_LISTONLY_V5"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

lines = s.splitlines(True)

def patch_lists(lines):
    changed_lists = 0
    added_items = 0

    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\[\s*$', lines[i])
        if not m:
            i += 1
            continue

        base_indent = m.group(1)
        # find matching closing bracket at SAME indent
        j = i + 1
        while j < len(lines):
            if re.match(r'^' + re.escape(base_indent) + r'\]\s*,?\s*$', lines[j]):
                break
            j += 1
        if j >= len(lines):
            i += 1
            continue

        block = "".join(lines[i:j+1])
        # only touch lists that are clearly the run_file_allow allowlist: contains run_gate_summary.json
        if '"run_gate_summary.json"' not in block:
            i = j + 1
            continue

        # determine item indent
        item_indent = base_indent + "    "
        for k in range(i+1, j):
            if lines[k].strip() and not lines[k].lstrip().startswith("#"):
                item_indent = re.match(r'^(\s*)', lines[k]).group(1)
                break

        need1 = '"reports/run_gate_summary.json"' not in block
        need2 = '"reports/run_gate.json"' not in block

        if need1 or need2:
            ins = []
            ins.append(f"{item_indent}# {MARK}\n")
            if need1:
                ins.append(f'{item_indent}"reports/run_gate_summary.json",\n')
                added_items += 1
            if need2:
                ins.append(f'{item_indent}"reports/run_gate.json",\n')
                added_items += 1
            # insert right before closing bracket
            lines[j:j] = ins
            changed_lists += 1
            # adjust j due to insertion
            j += len(ins)

        i = j + 1

    return changed_lists, added_items

cl, ai = patch_lists(lines)
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched list-allowlists: changed_lists={cl} added_items={ai}")
PY

echo "== [4] compile check =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== [5] restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== [6] sanity (reports gate summary should be 200 or file-not-found, NOT 403 not-allowed) =="
RID="RUN_20251120_130310"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80
