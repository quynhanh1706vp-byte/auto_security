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
cp -f "$F" "${F}.bak_pre_v3f_${TS}"
echo "[BACKUP] ${F}.bak_pre_v3f_${TS}"

echo "== [1] restore latest compiling backup of vsp_demo_app.py (if current is broken) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

f = Path("vsp_demo_app.py")
def compiles(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception:
        return False

if compiles(f):
    print("[OK] current vsp_demo_app.py compiles -> no restore needed")
    sys.exit(0)

baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for b in baks:
    if compiles(b):
        f.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored from compiling backup:", b.name)
        sys.exit(0)

print("[ERR] no compiling backup found for vsp_demo_app.py")
sys.exit(2)
PY

echo "== [2] patch /api/vsp/rid_latest_gate_root to pick latest run WITH details (V3F) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

route = "/api/vsp/rid_latest_gate_root"
idx = s.find(route)
if idx == -1:
    raise SystemExit(f"[ERR] cannot find route string: {route}")

lines = s.splitlines(True)

# find line index containing route
pos=0
li=0
for i, ln in enumerate(lines):
    if pos <= idx < pos + len(ln):
        li=i; break
    pos += len(ln)

# find nearest decorator block above (any @xxxx)
dec_start=None; dec_end=None
j=li
while j>=0 and (li-j)<=120:
    if lines[j].lstrip().startswith("@"):
        dec_end=j
        k=j
        while k>=0 and lines[k].lstrip().startswith("@"):
            k-=1
        dec_start=k+1
        break
    j-=1
if dec_start is None:
    dec_start=li; dec_end=li

# find def after decorator block
def_line=None
k=dec_end+1
while k < len(lines) and k <= dec_end+260:
    if re.match(r'^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(.*\)\s*:\s*$', lines[k].rstrip("\n")):
        def_line=k
        break
    k+=1
if def_line is None:
    # fallback: any def
    k=dec_end+1
    while k < len(lines) and k <= dec_end+400:
        if re.match(r'^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', lines[k]):
            def_line=k
            break
        k+=1
if def_line is None:
    ctx="".join(lines[max(0,li-8):min(len(lines),li+12)])
    raise SystemExit("[ERR] cannot locate def near route. Context:\n"+ctx)

mname = re.match(r'^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', lines[def_line])
func_name = mname.group(1) if mname else "api_vsp_rid_latest_gate_root"

start_pos = sum(len(x) for x in lines[:def_line])
tail = s[start_pos:]

# end at next top-level decorator or def
m_end = re.search(r'\n(?=@\w|\ndef\s+)', tail)
end_pos = start_pos + (m_end.start() if m_end else len(tail))

MARK="VSP_P0_RID_LATEST_PICK_ANY_DETAILS_V3F"

new_func = textwrap.dedent(f"""
def {func_name}():
    # {MARK}
    import os, glob, time, json

    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]

    def csv_has_2_lines(path: str) -> bool:
        try:
            if not os.path.isfile(path) or os.path.getsize(path) < 120:
                return False
            n = 0
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for _ in f:
                    n += 1
                    if n >= 2:
                        return True
            return False
        except Exception:
            return False

    def sarif_has_results(path: str) -> bool:
        try:
            if not os.path.isfile(path) or os.path.getsize(path) < 200:
                return False
            j = json.load(open(path, "r", encoding="utf-8", errors="ignore"))
            for run in (j.get("runs") or []):
                if (run.get("results") or []):
                    return True
            return False
        except Exception:
            return False

    def has_any_details(run_dir: str) -> str:
        fu = os.path.join(run_dir, "findings_unified.json")
        try:
            if os.path.isfile(fu) and os.path.getsize(fu) > 500:
                return "findings_unified.json"
        except Exception:
            pass

        csvp = os.path.join(run_dir, "reports", "findings_unified.csv")
        if csv_has_2_lines(csvp):
            return "reports/findings_unified.csv"

        sarifp = os.path.join(run_dir, "reports", "findings_unified.sarif")
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

    def pick_latest_with_details(max_scan=260):
        best = None  # (mtime, rid, root, why)
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands = []
            for rid in os.listdir(root):
                if not rid or rid.startswith("."):
                    continue
                run_dir = os.path.join(root, rid)
                if not os.path.isdir(run_dir):
                    continue
                try:
                    mtime = int(os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0
                cands.append((mtime, rid, run_dir))
            cands.sort(reverse=True)
            for mtime, rid, run_dir in cands[:max_scan]:
                why = has_any_details(run_dir)
                if why:
                    cand = (mtime, rid, root, why)
                    if best is None or cand[0] > best[0]:
                        best = cand
                    break
        return best

    def pick_latest_existing():
        best = None
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands=[]
            for rid in os.listdir(root):
                run_dir = os.path.join(root, rid)
                if os.path.isdir(run_dir):
                    try: cands.append((int(os.path.getmtime(run_dir)), rid))
                    except Exception: cands.append((0, rid))
            cands.sort(reverse=True)
            if cands:
                mtime, rid = cands[0]
                cand=(mtime, rid, root)
                if best is None or cand[0] > best[0]:
                    best = cand
        return best

    best = pick_latest_with_details()
    if best:
        _, rid, root, why = best
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
        "reason": "no_roots_found",
        "why": "",
        "ts": int(time.time()),
    }}), 200
""").lstrip("\n")

s2 = s[:start_pos] + new_func + s[end_pos:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK, "function=", func_name)
PY

echo "== [3] restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [4] verify rid_latest_gate_root now =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
