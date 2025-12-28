#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_broken_snapshot_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_snapshot_${TS}"

echo "== [1] ensure wsgi compiles (auto-restore latest compiling backup if needed) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

w = Path("wsgi_vsp_ui_gateway.py")

def compiles(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

if compiles(w):
    print("[OK] current wsgi compiles -> no restore needed")
    sys.exit(0)

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

for b in baks:
    if compiles(b):
        w.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored from compiling backup:", b.name)
        sys.exit(0)

print("[ERR] no compiling backup found for wsgi_vsp_ui_gateway.py")
sys.exit(2)
PY

echo "== [2] patch /api/vsp/rid_latest_gate_root handler in wsgi (V5) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

ROUTE = "/api/vsp/rid_latest_gate_root"

# Find a decorator line that registers GET for this route (app_obj/app/application etc.)
m = re.search(r'^\s*@\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*\.get\(\s*["\']' + re.escape(ROUTE) + r'["\']\s*\)\s*$', s, flags=re.M)
if not m:
    # fallback: any decorator containing this route
    m = re.search(r'^\s*@.*\(\s*["\']' + re.escape(ROUTE) + r'["\'].*\)\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find decorator for /api/vsp/rid_latest_gate_root in wsgi")

# locate def right after decorator block
start = m.start()
tail = s[start:]
mdef = re.search(r'\ndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', tail)
if not mdef:
    raise SystemExit("[ERR] cannot find def after rid_latest decorator")
func_name = mdef.group(1)

def_start = start + mdef.start() + 1
# end of function: next decorator or def at col 0
tail2 = s[def_start:]
mend = re.search(r'\n(?=@\w|\ndef\s+)', tail2)
def_end = def_start + (mend.start() if mend else len(tail2))

MARK = "VSP_P0_WSGI_RID_LATEST_PICK_ANY_DETAILS_V5"

new_func = textwrap.dedent(f"""
def {func_name}():
    # {MARK}
    from flask import jsonify, request
    import os, glob, time, json as _json

    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]

    # allow override scan depth
    try:
        max_scan = int(request.args.get("max_scan", "260"))
    except Exception:
        max_scan = 260
    max_scan = max(50, min(max_scan, 800))

    SKIP = set(["kics","bandit","trivy","grype","semgrep","gitleaks","codeql","reports","out","out_ci","tmp","cache"])

    def looks_like_rid(name: str) -> bool:
        if not name or name.startswith("."): return False
        if name in SKIP: return False
        if name.startswith(("VSP_CI_","RUN_","RUN-","VSP_")): return True
        return False

    def is_run_dir(rid: str, run_dir: str) -> bool:
        if not os.path.isdir(run_dir): return False
        if looks_like_rid(rid): return True
        # accept dirs with run artifacts even if name is weird
        if os.path.isfile(os.path.join(run_dir,"run_gate_summary.json")) or os.path.isfile(os.path.join(run_dir,"run_manifest.json")):
            return True
        return False

    def csv_has_2_lines(path: str) -> bool:
        try:
            if (not os.path.isfile(path)) or os.path.getsize(path) < 120: return False
            n=0
            with open(path,"r",encoding="utf-8",errors="ignore") as f:
                for _ in f:
                    n += 1
                    if n >= 2: return True
            return False
        except Exception:
            return False

    def sarif_has_results(path: str) -> bool:
        try:
            if (not os.path.isfile(path)) or os.path.getsize(path) < 200: return False
            j=_json.load(open(path,"r",encoding="utf-8",errors="ignore"))
            for run in (j.get("runs") or []):
                if (run.get("results") or []):
                    return True
            return False
        except Exception:
            return False

    def has_details(run_dir: str) -> str:
        fu = os.path.join(run_dir,"findings_unified.json")
        try:
            if os.path.isfile(fu) and os.path.getsize(fu) > 500:
                return "findings_unified.json"
        except Exception:
            pass

        csvp = os.path.join(run_dir,"reports","findings_unified.csv")
        if csv_has_2_lines(csvp):
            return "reports/findings_unified.csv"

        sarifp = os.path.join(run_dir,"reports","findings_unified.sarif")
        if sarif_has_results(sarifp):
            return "reports/findings_unified.sarif"

        pats = [
            "semgrep/**/*.json","grype/**/*.json","trivy/**/*.json","kics/**/*.json",
            "bandit/**/*.json","gitleaks/**/*.json","codeql/**/*.sarif",
            "**/*semgrep*.json","**/*grype*.json","**/*trivy*.json",
            "**/*kics*.json","**/*bandit*.json","**/*gitleaks*.json","**/*codeql*.sarif",
        ]
        for pat in pats:
            for f in glob.glob(os.path.join(run_dir, pat), recursive=True):
                try:
                    if os.path.getsize(f) > 800:
                        rel = os.path.relpath(f, run_dir).replace("\\\\","/")
                        if rel == "reports/findings_unified.sarif":
                            continue
                        return rel
                except Exception:
                    continue
        return ""

    def pick_latest_with_details():
        best = None  # (mtime, rid, root, why)
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands=[]
            for rid in os.listdir(root):
                run_dir = os.path.join(root, rid)
                if not is_run_dir(rid, run_dir):
                    continue
                try:
                    mtime = int(os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0
                cands.append((mtime, rid, run_dir))
            cands.sort(reverse=True)
            for mtime, rid, run_dir in cands[:max_scan]:
                why = has_details(run_dir)
                if why:
                    cand = (mtime, rid, root, why)
                    if best is None or cand[0] > best[0]:
                        best = cand
                    break
        return best

    def pick_latest_existing():
        best = None  # (mtime, rid, root)
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands=[]
            for rid in os.listdir(root):
                run_dir = os.path.join(root, rid)
                if not is_run_dir(rid, run_dir):
                    continue
                try:
                    cands.append((int(os.path.getmtime(run_dir)), rid, root))
                except Exception:
                    cands.append((0, rid, root))
            cands.sort(reverse=True)
            if cands:
                if best is None or cands[0][0] > best[0]:
                    best = cands[0]
        return best

    best = pick_latest_with_details()
    if best:
        _, rid, _root, why = best
        return jsonify({{
            "ok": True,
            "rid": rid,
            "gate_root": "gate_root_" + rid,
            "roots": roots,
            "reason": "latest_with_details",
            "why": why,
            "ts": int(time.time()),
        }})

    fb = pick_latest_existing()
    if fb:
        _, rid, _root = fb
        return jsonify({{
            "ok": True,
            "rid": rid,
            "gate_root": "gate_root_" + rid,
            "roots": roots,
            "reason": "latest_existing_fallback_no_details",
            "why": "",
            "ts": int(time.time()),
        }})

    return jsonify({{
        "ok": False,
        "rid": "",
        "gate_root": "",
        "roots": roots,
        "reason": "no_runs_found",
        "why": "",
        "ts": int(time.time()),
    }}), 200
""").lstrip("\n")

s2 = s[:def_start] + new_func + s[def_end:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched route handler:", MARK, "func=", func_name)
PY

echo "== [3] restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [4] verify rid_latest_gate_root (expect reason/why + rid != 133204) =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
