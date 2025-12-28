#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F (expected ui/vsp_demo_app.py)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ridpick_${TS}"
echo "[BACKUP] ${F}.bak_ridpick_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_PICK_EXISTING_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# 1) Ensure imports include os + json (most likely already)
if "import os" not in s:
    s = s.replace("import json", "import json\nimport os") if "import json" in s else ("import os\n" + s)

# 2) Insert helper picker near top (after imports block)
helper = textwrap.dedent(f"""
# ===================== {MARK} =====================
def _vsp_file_ok(path: str, min_bytes: int = 2) -> bool:
    try:
        return os.path.isfile(path) and os.path.getsize(path) >= min_bytes
    except Exception:
        return False

def _vsp_pick_latest_valid_rid() -> dict:
    # Roots to scan for run folders (CI + local). Adjust list without breaking old behavior.
    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]
    best = None  # (mtime, rid, root, reason)
    for root in roots:
        try:
            if not os.path.isdir(root):
                continue
            # only one level deep: root/<RID>/
            for name in os.listdir(root):
                if not name or name.startswith("."):
                    continue
                run_dir = os.path.join(root, name)
                if not os.path.isdir(run_dir):
                    continue
                # must have run_gate_summary OR run_gate
                gate_sum = os.path.join(run_dir, "run_gate_summary.json")
                gate = os.path.join(run_dir, "run_gate.json")
                # prefer having findings_unified.json for TopFind
                fu = os.path.join(run_dir, "findings_unified.json")
                if not (_vsp_file_ok(gate_sum, 10) or _vsp_file_ok(gate, 10)):
                    continue
                if not _vsp_file_ok(fu, 200):  # require real content
                    continue
                mtime = 0
                try:
                    mtime = int(os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0
                cand = (mtime, name, root, "gate+findings_unified")
                if (best is None) or (cand[0] > best[0]):
                    best = cand
        except Exception:
            continue

    if best:
        return {{"ok": True, "rid": best[1], "root": best[2], "reason": best[3]}}
    return {{"ok": False, "rid": "", "root": "", "reason": "no_valid_run_with_findings_unified"}}
# ===================== /{MARK} =====================
""").strip("\n") + "\n\n"

# place helper after initial imports (best-effort)
m = re.search(r'^(import .+\n)+', s, flags=re.M)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n" + helper + s[insert_at:]
else:
    s = helper + s

# 3) Patch endpoint function for /api/vsp/rid_latest_gate_root
# Try to find the route decorator and insert early-return
route_pat = r'@app\.(get|route)\(\s*[\'"]\/api\/vsp\/rid_latest_gate_root[\'"]\s*\)\s*\n(def\s+\w+\s*\(\)\s*:\s*|def\s+\w+\s*\(\)\s*:)\s*\n'
rm = re.search(route_pat, s)
if not rm:
    # fallback: just search for the string
    idx = s.find("/api/vsp/rid_latest_gate_root")
    if idx == -1:
        raise SystemExit("[ERR] cannot locate rid_latest_gate_root endpoint in vsp_demo_app.py")
    # attempt to locate def line after it
    start = s.rfind("\n", 0, idx)
    end = s.find("\n", idx)
    raise SystemExit("[ERR] found string but could not pattern-match route. Please show snippet around that line.")

# find function body start line after def line
def_start = rm.end()
# insert block at first indent inside function (assume 4 spaces)
inject = textwrap.dedent("""
    # VSP_P0_RID_LATEST_PICK_EXISTING_V1: always prefer an existing run that has findings_unified.json
    try:
        pick = _vsp_pick_latest_valid_rid()
        if pick.get("ok") and pick.get("rid"):
            return jsonify({"ok": True, "rid": pick["rid"], "root": pick.get("root",""), "reason": pick.get("reason","")})
    except Exception:
        pass
""")

# Insert right after function signature line
# Find the first newline after def line:
nl = s.find("\n", def_start)
if nl == -1:
    raise SystemExit("[ERR] unexpected file structure (no newline after def)")
s = s[:nl+1] + inject + s[nl+1:]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] rid_latest_gate_root =>"
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo

RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"

echo "== [verify] run_gate_summary.json (should NOT 404) =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -c 200; echo

echo "== [verify] findings_unified.json (should NOT 404) =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" | head -c 200; echo

echo "[DONE] Now HARD refresh /vsp5 (Ctrl+Shift+R) and click Load top findings (25)."
