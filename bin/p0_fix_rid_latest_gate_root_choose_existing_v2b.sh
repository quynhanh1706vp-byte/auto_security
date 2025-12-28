#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ridpick_v2b_${TS}"
echo "[BACKUP] ${F}.bak_ridpick_v2b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_PICK_EXISTING_V2B"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# Ensure imports
def ensure_import(mod):
    nonlocal_s = None

if re.search(r'^\s*import\s+os\s*$', s, re.M) is None:
    m = re.search(r'^(import .+\n)+', s, flags=re.M)
    if m: s = s[:m.end()] + "import os\n" + s[m.end():]
    else: s = "import os\n" + s

if re.search(r'^\s*import\s+time\s*$', s, re.M) is None:
    m = re.search(r'^(import .+\n)+', s, flags=re.M)
    if m: s = s[:m.end()] + "import time\n" + s[m.end():]
    else: s = "import time\n" + s

# Helper block (NO f-string, braces escaped for .format)
helper = """
# ===================== {MARK} =====================
def _vsp__file_ok(path: str, min_bytes: int = 64) -> bool:
    try:
        return os.path.isfile(path) and os.path.getsize(path) >= min_bytes
    except Exception:
        return False

def _vsp__pick_latest_valid_rid(roots):
    best = None  # (mtime, rid, root)
    for root in roots:
        try:
            if not os.path.isdir(root):
                continue
            for name in os.listdir(root):
                if not name or name.startswith("."):
                    continue
                run_dir = os.path.join(root, name)
                if not os.path.isdir(run_dir):
                    continue

                gate_sum = os.path.join(run_dir, "run_gate_summary.json")
                gate = os.path.join(run_dir, "run_gate.json")
                if not (_vsp__file_ok(gate_sum, 10) or _vsp__file_ok(gate, 10)):
                    continue

                fu = os.path.join(run_dir, "findings_unified.json")
                if not _vsp__file_ok(fu, 200):
                    continue

                try:
                    mtime = int(os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0

                cand = (mtime, name, root)
                if (best is None) or (cand[0] > best[0]):
                    best = cand
        except Exception:
            continue

    if best:
        return {{ "ok": True, "rid": best[1], "root": best[2], "reason": "gate+findings_unified" }}
    return {{ "ok": False, "rid": "", "root": "", "reason": "no_valid_run_with_findings_unified" }}
# ===================== /{MARK} =====================
""".format(MARK=MARK)

# Insert helper after imports
m = re.search(r'^(import .+\n)+', s, flags=re.M)
if m:
    s = s[:m.end()] + "\n" + helper + "\n" + s[m.end():]
else:
    s = helper + "\n" + s

# Locate endpoint by searching the route string, then next def
idx = s.find("/api/vsp/rid_latest_gate_root")
if idx == -1:
    raise SystemExit("[ERR] cannot find '/api/vsp/rid_latest_gate_root' in vsp_demo_app.py")

mdef = re.search(r'\ndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', s[idx:], flags=re.M)
if not mdef:
    raise SystemExit("[ERR] cannot find function def after rid_latest_gate_root route")

def_pos = idx + mdef.start() + 1
line_end = s.find("\n", def_pos)
if line_end == -1:
    raise SystemExit("[ERR] malformed def line for rid_latest_gate_root")

inject = """
    # {MARK}: always prefer an existing RID that has findings_unified.json (avoid 404)
    try:
        roots = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]
        pick = _vsp__pick_latest_valid_rid(roots)
        if pick.get("ok") and pick.get("rid"):
            rid = pick["rid"]
            return jsonify({{
                "ok": True,
                "rid": rid,
                "gate_root": "gate_root_" + rid,
                "roots": roots,
                "reason": pick.get("reason",""),
                "ts": int(time.time()),
            }})
    except Exception:
        pass
""".format(MARK=MARK)

# Avoid double-inject near start of function
near = s[line_end: line_end+1200]
if MARK in near:
    print("[SKIP] injection already present near function body")
else:
    s = s[:line_end+1] + inject + s[line_end+1:]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] rid_latest_gate_root =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo

RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"

echo "== [verify] run_gate_summary.json (should NOT be 404) =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -c 160; echo

echo "== [verify] findings_unified.json (should NOT be 404) =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" | head -c 160; echo

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). Now TopFind should stop 'đơ'."
