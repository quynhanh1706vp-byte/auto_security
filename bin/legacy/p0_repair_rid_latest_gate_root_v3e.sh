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
cp -f "$F" "${F}.bak_repair_rid_v3e_${TS}"
echo "[BACKUP] ${F}.bak_repair_rid_v3e_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

route = "/api/vsp/rid_latest_gate_root"
idx = s.find(route)
if idx == -1:
    raise SystemExit(f"[ERR] cannot find route string: {route}")

# Find line number containing route
line_start = s.rfind("\n", 0, idx) + 1
line_end = s.find("\n", idx)
if line_end == -1:
    line_end = len(s)

# Walk upwards to find decorator block: consecutive lines starting with "@"
# We'll search up to 80 lines above.
lines = s.splitlines(True)
# Compute current line index
pos = 0
li = 0
for i, ln in enumerate(lines):
    if pos <= idx < pos + len(ln):
        li = i
        break
    pos += len(ln)

dec_start = None
dec_end = None

# Find nearest decorator line above the route line (including same line)
j = li
while j >= 0 and (li - j) <= 80:
    if lines[j].lstrip().startswith("@"):
        dec_end = j
        # extend upward while decorators continue
        k = j
        while k >= 0 and lines[k].lstrip().startswith("@"):
            k -= 1
        dec_start = k + 1
        break
    j -= 1

if dec_start is None:
    # No decorator lines found; still try: search upward for "def" directly after route.
    dec_start = li
    dec_end = li

# Find def after decorator block
k = dec_end + 1
def_line = None
while k < len(lines) and k <= dec_end + 120:
    if re.match(r'^\s*def\s+[A-Za-z_][A-Za-z0-9_]*\s*\(.*\)\s*:\s*$', lines[k].rstrip("\n")):
        def_line = k
        break
    k += 1

if def_line is None:
    # fallback: look for any "def name(" within next 200 lines
    k = dec_end + 1
    while k < len(lines) and k <= dec_end + 200:
        if re.match(r'^\s*def\s+[A-Za-z_][A-Za-z0-9_]*\s*\(', lines[k]):
            def_line = k
            break
        k += 1

if def_line is None:
    # show context lines to help
    ctx = "".join(lines[max(0, li-6): min(len(lines), li+10)])
    raise SystemExit("[ERR] cannot locate function def near route. Context:\n" + ctx)

# Find end of function: next top-level decorator/def at col 0 (or minimal indent)
start_pos = sum(len(x) for x in lines[:def_line])
tail = s[start_pos:]
m_end = re.search(r'\n(?=@\w|\ndef\s+)', tail)
if m_end:
    end_pos = start_pos + m_end.start()
else:
    end_pos = len(s)

MARK = "VSP_P0_RID_LATEST_PICK_ANY_DETAILS_V3E_REPAIR"

new_func = textwrap.dedent(f"""
def api_vsp_rid_latest_gate_root():
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
            "semgrep/**/*.json",
            "grype/**/*.json",
            "trivy/**/*.json",
            "kics/**/*.json",
            "bandit/**/*.json",
            "gitleaks/**/*.json",
            "codeql/**/*.sarif",
            "**/*codeql*.sarif",
            "**/*semgrep*.json",
            "**/*grype*.json",
            "**/*trivy*.json",
            "**/*kics*.json",
            "**/*bandit*.json",
            "**/*gitleaks*.json",
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

    def pick_latest_with_details(max_scan=250):
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
            try:
                rids = []
                for rid in os.listdir(root):
                    run_dir = os.path.join(root, rid)
                    if os.path.isdir(run_dir):
                        try:
                            rids.append((int(os.path.getmtime(run_dir)), rid, root))
                        except Exception:
                            rids.append((0, rid, root))
                rids.sort(reverse=True)
                if rids:
                    cand = rids[0]
                    if best is None or cand[0] > best[0]:
                        best = cand
            except Exception:
                continue
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

# Replace function from def_line to end_pos, keep decorator lines intact.
s2 = s[:start_pos] + new_func + s[end_pos:]

p.write_text(s2, encoding="utf-8")
print("[OK] repaired function at route:", route)
print("[INFO] def_line_index=", def_line, "decorators_lines=", (dec_start, dec_end))
PY

python3 -m py_compile vsp_demo_app.py

systemctl restart "$SVC" 2>/dev/null || true

echo "== verify rid_latest_gate_root =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
