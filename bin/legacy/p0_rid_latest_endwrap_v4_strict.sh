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
cp -f "$W" "${W}.bak_endwrap_v4_${TS}"
echo "[BACKUP] ${W}.bak_endwrap_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_ENDWRAP_V4_STRICT"
if MARK in s:
    print("[SKIP] already injected:", MARK)
else:
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_RID_LATEST_ENDWRAP_V4_STRICT =====================
    # Outer-most intercept: accept only RID like VSP_CI_* or RUN_* (avoid out_ci/reports/tool dirs)
    try:
        import json as _json
        import os as _os
        import glob as _glob
        import time as _time
        import re as _re

        if globals().get("__vsp_p0_rid_latest_endwrap_v4"):
            pass
        else:
            globals()["__vsp_p0_rid_latest_endwrap_v4"] = True

            _VSP_RID_ROOTS = [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
                "/home/test/Data/SECURITY_BUNDLE/out_ci",
            ]
            _RID_RE = _re.compile(r"^(VSP_CI_|RUN_).+")

            def _csv_has_2_lines(path: str) -> bool:
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

            def _sarif_has_results(path: str) -> bool:
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

            def _is_rid(name: str) -> bool:
                if not name or name.startswith("."):
                    return False
                if name.startswith("gate_root_"):
                    return False
                return bool(_RID_RE.match(name))

            def _has_details(run_dir: str) -> str:
                fu = _os.path.join(run_dir, "findings_unified.json")
                try:
                    if _os.path.isfile(fu) and _os.path.getsize(fu) > 500:
                        return "findings_unified.json"
                except Exception:
                    pass

                csvp = _os.path.join(run_dir, "reports", "findings_unified.csv")
                if _csv_has_2_lines(csvp):
                    return "reports/findings_unified.csv"

                sarifp = _os.path.join(run_dir, "reports", "findings_unified.sarif")
                if _sarif_has_results(sarifp):
                    return "reports/findings_unified.sarif"

                pats = [
                    "semgrep/**/*.json","grype/**/*.json","trivy/**/*.json","kics/**/*.json",
                    "bandit/**/*.json","gitleaks/**/*.json","codeql/**/*.sarif",
                ]
                for pat in pats:
                    for f in _glob.glob(_os.path.join(run_dir, pat), recursive=True):
                        try:
                            if _os.path.getsize(f) > 800:
                                return _os.path.relpath(f, run_dir).replace("\\","/")
                        except Exception:
                            continue
                return ""

            def _pick_latest_with_details(max_scan: int = 800):
                best = None  # (mtime, rid, root, why)
                for root in _VSP_RID_ROOTS:
                    if not _os.path.isdir(root):
                        continue
                    cands = []
                    for rid in _os.listdir(root):
                        if not _is_rid(rid):
                            continue
                        d = _os.path.join(root, rid)
                        if not _os.path.isdir(d):
                            continue
                        try:
                            mtime = int(_os.path.getmtime(d))
                        except Exception:
                            mtime = 0
                        cands.append((mtime, rid, d))
                    cands.sort(reverse=True)
                    for mtime, rid, d in cands[:max_scan]:
                        why = _has_details(d)
                        if why:
                            cand = (mtime, rid, root, why)
                            if best is None or cand[0] > best[0]:
                                best = cand
                            break
                return best

            def _pick_latest_existing():
                best = None
                for root in _VSP_RID_ROOTS:
                    if not _os.path.isdir(root):
                        continue
                    cands = []
                    for rid in _os.listdir(root):
                        if not _is_rid(rid):
                            continue
                        d = _os.path.join(root, rid)
                        if not _os.path.isdir(d):
                            continue
                        try:
                            cands.append((int(_os.path.getmtime(d)), rid, root))
                        except Exception:
                            cands.append((0, rid, root))
                    cands.sort(reverse=True)
                    if cands and (best is None or cands[0][0] > best[0]):
                        best = cands[0]
                return best

            def _payload():
                best = _pick_latest_with_details()
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
                fb = _pick_latest_existing()
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

            def _json_resp(start_response, payload):
                body = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
                hdrs = [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-store"),
                    ("X-VSP-RIDPICK","ENDWRAP_V4"),
                    ("Content-Length", str(len(body))),
                ]
                start_response("200 OK", hdrs)
                return [body]

            def _mw(_app):
                def _wsgi(environ, start_response):
                    path = environ.get("PATH_INFO","") or ""
                    if path in ("/api/vsp/rid_latest_gate_root", "/api/vsp/rid_latest_gate_root.json"):
                        return _json_resp(start_response, _payload())
                    return _app(environ, start_response)
                return _wsgi

            # Make this the outer-most wrapper (EOF)
            if "application" in globals() and callable(globals().get("application")):
                application = _mw(application)
            if "app" in globals() and callable(globals().get("app")):
                app = _mw(app)

            print("[VSP_P0_RID_LATEST_ENDWRAP_V4] enabled")
    except Exception as _e:
        print("[VSP_P0_RID_LATEST_ENDWRAP_V4] ERROR:", _e)
    # ===================== /VSP_P0_RID_LATEST_ENDWRAP_V4_STRICT =====================
    """).strip("\n") + "\n"
    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== verify (must see X-VSP-RIDPICK: ENDWRAP_V4 and rid startswith VSP_CI_/RUN_) =="
curl -isS "$BASE/api/vsp/rid_latest_gate_root" | sed -n '1,40p'
echo
curl -sS "$BASE/api/vsp/rid_latest_gate_root"; echo
