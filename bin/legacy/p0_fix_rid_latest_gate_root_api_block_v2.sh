#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rid_api_v2_${TS}"
echo "[BACKUP] ${W}.bak_rid_api_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

START = "# ===================== VSP_P0_RID_LATEST_GATE_ROOT_API_V1 ====================="
END   = "# ===================== /VSP_P0_RID_LATEST_GATE_ROOT_API_V1 ====================="

i = s.find(START)
j = s.find(END)
if i == -1 or j == -1 or j <= i:
    raise SystemExit("[ERR] cannot find RID_LATEST_GATE_ROOT_API_V1 block markers")

j2 = j + len(END)

block = textwrap.dedent(r"""
# ===================== VSP_P0_RID_LATEST_GATE_ROOT_API_V2_REASON_V1 =====================
# WSGI intercept for /api/vsp/rid_latest_gate_root that always picks the latest run WITH details.
try:
    import json as _json
    import os as _os
    import glob as _glob
    import time as _time

    _VSP_RID_ROOTS = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]

    _VSP_SKIP = set(["kics","bandit","trivy","grype","semgrep","gitleaks","codeql","reports","out","out_ci","tmp","cache"])

    def _vsp_csv_has_2_lines(path: str) -> bool:
        try:
            if (not _os.path.isfile(path)) or _os.path.getsize(path) < 120:
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

    def _vsp_sarif_has_results(path: str) -> bool:
        try:
            if (not _os.path.isfile(path)) or _os.path.getsize(path) < 200:
                return False
            j = _json.load(open(path, "r", encoding="utf-8", errors="ignore"))
            for run in (j.get("runs") or []):
                if (run.get("results") or []):
                    return True
            return False
        except Exception:
            return False

    def _vsp_looks_like_rid(name: str) -> bool:
        if not name or name.startswith("."):
            return False
        if name in _VSP_SKIP:
            return False
        return name.startswith(("VSP_CI_","RUN_","RUN-","VSP_"))

    def _vsp_is_run_dir(rid: str, run_dir: str) -> bool:
        if not _os.path.isdir(run_dir):
            return False
        if _vsp_looks_like_rid(rid):
            return True
        # accept weird names if they contain run artifacts
        if _os.path.isfile(_os.path.join(run_dir, "run_gate_summary.json")) or _os.path.isfile(_os.path.join(run_dir, "run_manifest.json")):
            return True
        return False

    def _vsp_has_details(run_dir: str) -> str:
        fu = _os.path.join(run_dir, "findings_unified.json")
        try:
            if _os.path.isfile(fu) and _os.path.getsize(fu) > 500:
                return "findings_unified.json"
        except Exception:
            pass

        csvp = _os.path.join(run_dir, "reports", "findings_unified.csv")
        if _vsp_csv_has_2_lines(csvp):
            return "reports/findings_unified.csv"

        sarifp = _os.path.join(run_dir, "reports", "findings_unified.sarif")
        if _vsp_sarif_has_results(sarifp):
            return "reports/findings_unified.sarif"

        pats = [
            "semgrep/**/*.json","grype/**/*.json","trivy/**/*.json","kics/**/*.json",
            "bandit/**/*.json","gitleaks/**/*.json","codeql/**/*.sarif",
            "**/*semgrep*.json","**/*grype*.json","**/*trivy*.json",
            "**/*kics*.json","**/*bandit*.json","**/*gitleaks*.json","**/*codeql*.sarif",
        ]
        for pat in pats:
            for f in _glob.glob(_os.path.join(run_dir, pat), recursive=True):
                try:
                    if _os.path.getsize(f) > 800:
                        rel = _os.path.relpath(f, run_dir).replace("\\","/")
                        if rel == "reports/findings_unified.sarif":
                            continue
                        return rel
                except Exception:
                    continue
        return ""

    def _vsp_pick_latest_with_details(max_scan: int = 500):
        best = None  # (mtime, rid, root, why)
        for root in _VSP_RID_ROOTS:
            if not _os.path.isdir(root):
                continue
            cands = []
            for rid in _os.listdir(root):
                run_dir = _os.path.join(root, rid)
                if not _vsp_is_run_dir(rid, run_dir):
                    continue
                try:
                    mtime = int(_os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0
                cands.append((mtime, rid, run_dir))
            cands.sort(reverse=True)
            for mtime, rid, run_dir in cands[:max_scan]:
                why = _vsp_has_details(run_dir)
                if why:
                    cand = (mtime, rid, root, why)
                    if best is None or cand[0] > best[0]:
                        best = cand
                    break
        return best

    def _vsp_pick_latest_existing():
        best = None  # (mtime, rid, root)
        for root in _VSP_RID_ROOTS:
            if not _os.path.isdir(root):
                continue
            cands = []
            for rid in _os.listdir(root):
                run_dir = _os.path.join(root, rid)
                if not _vsp_is_run_dir(rid, run_dir):
                    continue
                try:
                    cands.append((int(_os.path.getmtime(run_dir)), rid, root))
                except Exception:
                    cands.append((0, rid, root))
            cands.sort(reverse=True)
            if cands and (best is None or cands[0][0] > best[0]):
                best = cands[0]
        return best

    def _vsp_rid_latest_payload():
        best = _vsp_pick_latest_with_details()
        if best:
            _, rid, _root, why = best
            return {
                "ok": True,
                "rid": rid,
                "gate_root": "gate_root_" + rid,
                "roots": _VSP_RID_ROOTS,
                "reason": "latest_with_details",
                "why": why,
                "ts": int(_time.time()),
            }
        fb = _vsp_pick_latest_existing()
        if fb:
            _, rid, _root = fb
            return {
                "ok": True,
                "rid": rid,
                "gate_root": "gate_root_" + rid,
                "roots": _VSP_RID_ROOTS,
                "reason": "latest_existing_fallback_no_details",
                "why": "",
                "ts": int(_time.time()),
            }
        return {
            "ok": False,
            "rid": "",
            "gate_root": "",
            "roots": _VSP_RID_ROOTS,
            "reason": "no_runs_found",
            "why": "",
            "ts": int(_time.time()),
        }

    def _vsp_wsgi_json(start_response, payload, code="200 OK"):
        body = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(code, headers)
        return [body]

    def _wrap(_app):
        def _mw(environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path in ("/api/vsp/rid_latest_gate_root", "/api/vsp/rid_latest_gate_root.json"):
                payload = _vsp_rid_latest_payload()
                return _vsp_wsgi_json(start_response, payload, "200 OK")
            return _app(environ, start_response)
        return _mw

    # wrap whichever callable exists
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap(application)

    print("[VSP_P0_RID_LATEST_GATE_ROOT_API_V2] enabled")
except Exception as _e:
    print("[VSP_P0_RID_LATEST_GATE_ROOT_API_V2] ERROR:", _e)
# ===================== /VSP_P0_RID_LATEST_GATE_ROOT_API_V2_REASON_V1 =====================
""").strip("\n") + "\n\n"

# Replace whole V1 block (including markers) with new block (and keep END marker in place by replacing entire region)
s2 = s[:i] + block + s[j2:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] replaced RID_LATEST_GATE_ROOT_API_V1 block with V2")
PY

systemctl restart "${SVC}" 2>/dev/null || true

echo "== verify rid_latest_gate_root (expect reason/why + rid != 133204) =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
