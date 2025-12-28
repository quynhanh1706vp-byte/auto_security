#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ridpick_v3c_${TS}"
echo "[BACKUP] ${F}.bak_ridpick_v3c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK_HELP = "VSP_P0_RID_PICK_ANY_DETAILS_HELPER_V3C"
MARK_INJECT = "VSP_P0_RID_LATEST_PICK_ANY_DETAILS_V3C"

if MARK_HELP not in s:
    helper = textwrap.dedent(r"""
    # ===================== VSP_P0_RID_PICK_ANY_DETAILS_HELPER_V3C =====================
    import os as _os
    import glob as _glob

    def _vsp__csv_has_2_lines(path: str) -> bool:
        try:
            if not _os.path.isfile(path) or _os.path.getsize(path) < 120:
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

    def _vsp__sarif_has_results(path: str) -> bool:
        try:
            if not _os.path.isfile(path) or _os.path.getsize(path) < 200:
                return False
            import json as _json
            j = _json.load(open(path, "r", encoding="utf-8", errors="ignore"))
            for run in (j.get("runs") or []):
                if (run.get("results") or []):
                    return True
            return False
        except Exception:
            return False

    def _vsp__has_any_details(run_dir: str) -> str:
        # 1) unified json
        fu = _os.path.join(run_dir, "findings_unified.json")
        try:
            if _os.path.isfile(fu) and _os.path.getsize(fu) > 500:
                return "findings_unified.json"
        except Exception:
            pass

        # 2) reports csv/sarif
        csvp = _os.path.join(run_dir, "reports", "findings_unified.csv")
        if _vsp__csv_has_2_lines(csvp):
            return "reports/findings_unified.csv"

        sarifp = _os.path.join(run_dir, "reports", "findings_unified.sarif")
        if _vsp__sarif_has_results(sarifp):
            return "reports/findings_unified.sarif"

        # 3) raw tool outputs (fast patterns)
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
            for f in _glob.glob(_os.path.join(run_dir, pat), recursive=True):
                try:
                    if _os.path.getsize(f) > 800:
                        rel = _os.path.relpath(f, run_dir)
                        # skip the empty unified sarif to avoid false-positive
                        if rel.replace("\\","/") == "reports/findings_unified.sarif":
                            continue
                        return rel.replace("\\","/")
                except Exception:
                    continue

        return ""

    def _vsp__pick_latest_rid_with_details(roots, max_scan=200):
        best = None  # (mtime, rid, root, why)
        for root in roots:
            try:
                if not _os.path.isdir(root):
                    continue
                # list subdirs and sort by mtime desc, scan top N only
                cands = []
                for name in _os.listdir(root):
                    if not name or name.startswith("."):
                        continue
                    run_dir = _os.path.join(root, name)
                    if not _os.path.isdir(run_dir):
                        continue
                    try:
                        mtime = int(_os.path.getmtime(run_dir))
                    except Exception:
                        mtime = 0
                    cands.append((mtime, name, run_dir))
                cands.sort(reverse=True)
                for mtime, rid, run_dir in cands[:max_scan]:
                    why = _vsp__has_any_details(run_dir)
                    if why:
                        cand = (mtime, rid, root, why)
                        if best is None or cand[0] > best[0]:
                            best = cand
                        break
            except Exception:
                continue
        if best:
            return {"ok": True, "rid": best[1], "root": best[2], "why": best[3]}
        return {"ok": False, "rid": "", "root": "", "why": ""}
    # ===================== /VSP_P0_RID_PICK_ANY_DETAILS_HELPER_V3C =====================
    """).strip("\n") + "\n"

    m = re.search(r'^(import .+\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "\n" + helper + "\n" + s[m.end():]
    else:
        s = helper + "\n" + s

# Find rid_latest_gate_root route occurrence
idx = s.find("/api/vsp/rid_latest_gate_root")
if idx == -1:
    raise SystemExit("[ERR] cannot find '/api/vsp/rid_latest_gate_root' in vsp_demo_app.py")

mdef = re.search(r'\ndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', s[idx:], flags=re.M)
if not mdef:
    raise SystemExit("[ERR] cannot find function def after rid_latest_gate_root route")

def_pos = idx + mdef.start() + 1
line_end = s.find("\n", def_pos)
if line_end == -1:
    raise SystemExit("[ERR] malformed def line")

# Insert new early-return (above previous V2B if present)
inject = textwrap.dedent(r"""
    # VSP_P0_RID_LATEST_PICK_ANY_DETAILS_V3C: prefer latest RID that has real findings details (raw tool outputs)
    try:
        roots = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]
        pick = _vsp__pick_latest_rid_with_details(roots, max_scan=200)
        if pick.get("ok") and pick.get("rid"):
            rid = pick["rid"]
            return jsonify({
                "ok": True,
                "rid": rid,
                "gate_root": "gate_root_" + rid,
                "roots": roots,
                "reason": "latest_with_details",
                "why": pick.get("why",""),
                "ts": int(time.time()),
            })
    except Exception:
        pass
""").strip("\n") + "\n"

# Avoid double insert
near = s[line_end: line_end+1800]
if MARK_INJECT in near:
    print("[SKIP] already injected:", MARK_INJECT)
else:
    s = s[:line_end+1] + inject + s[line_end+1:]
    print("[OK] injected:", MARK_INJECT)

p.write_text(s, encoding="utf-8")
print("[OK] wrote file")
PY

python3 -m py_compile vsp_demo_app.py
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify rid_latest_gate_root now =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
