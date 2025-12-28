#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
ROUTE="/api/vsp/rid_latest_gate_root"

echo "== [0] locate route owner files =="
HITS="$(grep -Rsn --include='*.py' "$ROUTE" . | sed 's|^\./||' | head -n 20 || true)"
echo "$HITS" | sed -n '1,20p'
echo

OWNER=""
if echo "$HITS" | grep -q '^wsgi_vsp_ui_gateway\.py:'; then
  OWNER="wsgi_vsp_ui_gateway.py"
elif echo "$HITS" | grep -q '^vsp_demo_app\.py:'; then
  OWNER="vsp_demo_app.py"
else
  # fallback: pick first file
  OWNER="$(echo "$HITS" | head -n 1 | cut -d: -f1)"
fi

[ -n "$OWNER" ] || { echo "[ERR] cannot locate owner for $ROUTE"; exit 2; }
[ -f "$OWNER" ] || { echo "[ERR] owner file missing: $OWNER"; exit 2; }
echo "[INFO] OWNER=$OWNER"

cp -f "$OWNER" "${OWNER}.bak_rid_owner_v4b_${TS}"
echo "[BACKUP] ${OWNER}.bak_rid_owner_v4b_${TS}"

echo "== [1] patch owner handler to pick latest RID WITH details (V4B) =="
python3 - "$OWNER" "$ROUTE" <<'PY'
from pathlib import Path
import re, textwrap, py_compile, sys

owner = Path(sys.argv[1])
route = sys.argv[2]
s = owner.read_text(encoding="utf-8", errors="replace")

idx = s.find(route)
if idx == -1:
    raise SystemExit(f"[ERR] route string not found in {owner}: {route}")

lines = s.splitlines(True)

# find line index containing route
pos=0; li=0
for i, ln in enumerate(lines):
    if pos <= idx < pos + len(ln):
        li=i; break
    pos += len(ln)

# find nearest decorator block above (any '@')
dec_start=None; dec_end=None
j=li
while j>=0 and (li-j) <= 250:
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

# find def after decorator
def_line=None
k=dec_end+1
while k < len(lines) and k <= dec_end+800:
    if re.match(r'^\s*def\s+[A-Za-z_][A-Za-z0-9_]*\s*\(.*\)\s*:\s*$', lines[k].rstrip("\n")):
        def_line=k
        break
    k+=1
if def_line is None:
    ctx="".join(lines[max(0,li-10):min(len(lines),li+18)])
    raise SystemExit("[ERR] cannot locate def after decorator. Context:\n"+ctx)

mname = re.match(r'^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', lines[def_line])
func_name = mname.group(1) if mname else "api_vsp_rid_latest_gate_root"

start_pos = sum(len(x) for x in lines[:def_line])
tail = s[start_pos:]
m_end = re.search(r'\n(?=@\w|\ndef\s+)', tail)
end_pos = start_pos + (m_end.start() if m_end else len(tail))

MARK="VSP_P0_RID_LATEST_PICK_ANY_DETAILS_V4B_OWNER"

new_func = textwrap.dedent(f"""
def {func_name}():
    # {MARK}
    import os, glob, time, json

    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]

    # ignore common non-run folders
    _SKIP_NAMES = set([
        "kics","bandit","trivy","grype","semgrep","gitleaks","codeql",
        "reports","out","out_ci","tmp","cache"
    ])

    def _looks_like_rid(name: str) -> bool:
        if not name or name.startswith("."):
            return False
        if name in _SKIP_NAMES:
            return False
        if name.startswith(("VSP_CI_","RUN_","RUN-","VSP_")):
            return True
        return False

    def _is_run_dir(rid: str, run_dir: str) -> bool:
        if not os.path.isdir(run_dir):
            return False
        if not _looks_like_rid(rid):
            # allow if it has gate/manifest (some runs not following name conv)
            if os.path.isfile(os.path.join(run_dir, "run_gate_summary.json")) or os.path.isfile(os.path.join(run_dir, "run_manifest.json")):
                return True
            return False
        return True

    def csv_has_2_lines(path: str) -> bool:
        try:
            if not os.path.isfile(path) or os.path.getsize(path) < 120:
                return False
            n=0
            with open(path,"r",encoding="utf-8",errors="ignore") as f:
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
            j=json.load(open(path,"r",encoding="utf-8",errors="ignore"))
            for run in (j.get("runs") or []):
                if (run.get("results") or []):
                    return True
            return False
        except Exception:
            return False

    def has_any_details(run_dir: str) -> str:
        fu=os.path.join(run_dir,"findings_unified.json")
        try:
            if os.path.isfile(fu) and os.path.getsize(fu) > 500:
                return "findings_unified.json"
        except Exception:
            pass

        csvp=os.path.join(run_dir,"reports","findings_unified.csv")
        if csv_has_2_lines(csvp):
            return "reports/findings_unified.csv"

        sarifp=os.path.join(run_dir,"reports","findings_unified.sarif")
        if sarif_has_results(sarifp):
            return "reports/findings_unified.sarif"

        # raw tool outputs
        pats=[
            "semgrep/**/*.json","grype/**/*.json","trivy/**/*.json","kics/**/*.json",
            "bandit/**/*.json","gitleaks/**/*.json","codeql/**/*.sarif",
            "**/*semgrep*.json","**/*grype*.json","**/*trivy*.json","**/*kics*.json",
            "**/*bandit*.json","**/*gitleaks*.json","**/*codeql*.sarif",
        ]
        for pat in pats:
            for f in glob.glob(os.path.join(run_dir,pat), recursive=True):
                try:
                    if os.path.getsize(f) > 800:
                        rel=os.path.relpath(f, run_dir).replace("\\\\","/")
                        if rel == "reports/findings_unified.sarif":
                            continue
                        return rel
                except Exception:
                    continue
        return ""

    def pick_latest_with_details(max_scan=450):
        best=None  # (mtime, rid, root, why)
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands=[]
            for rid in os.listdir(root):
                run_dir=os.path.join(root,rid)
                if not _is_run_dir(rid, run_dir):
                    continue
                try:
                    mtime=int(os.path.getmtime(run_dir))
                except Exception:
                    mtime=0
                cands.append((mtime,rid,run_dir))
            cands.sort(reverse=True)
            for mtime,rid,run_dir in cands[:max_scan]:
                why=has_any_details(run_dir)
                if why:
                    cand=(mtime,rid,root,why)
                    if best is None or cand[0] > best[0]:
                        best=cand
                    break
        return best

    def pick_latest_existing():
        best=None
        for root in roots:
            if not os.path.isdir(root):
                continue
            cands=[]
            for rid in os.listdir(root):
                run_dir=os.path.join(root,rid)
                if not _is_run_dir(rid, run_dir):
                    continue
                try:
                    cands.append((int(os.path.getmtime(run_dir)), rid, root))
                except Exception:
                    cands.append((0, rid, root))
            cands.sort(reverse=True)
            if cands:
                if best is None or cands[0][0] > best[0]:
                    best=cands[0]
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
        "reason": "no_runs_found",
        "why": "",
        "ts": int(time.time()),
    }}), 200
""").lstrip("\n")

s2 = s[:start_pos] + new_func + s[end_pos:]
owner.write_text(s2, encoding="utf-8")
py_compile.compile(str(owner), doraise=True)
print("[OK] patched:", owner, "func=", func_name, "mark=", MARK)
PY

echo "== [2] restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [3] verify rid_latest_gate_root (expect reason/why + rid change) =="
curl -sS "$BASE$ROUTE"; echo
