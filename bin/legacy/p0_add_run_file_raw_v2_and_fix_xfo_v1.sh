#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rawv2_xfo_${TS}"
echo "[BACKUP] ${WSGI}.bak_rawv2_xfo_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re, textwrap
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

changed=0

# --- 1) Add RAW v2 endpoint (safe allowlist) ---
if "/api/vsp/run_file_raw_v2" not in s:
    # insert near 'application = ...' line (stable in your wsgi)
    m = re.search(r'(?m)^\s*application\s*=\s*.*$', s)
    ins = (s.find("\n", m.end()) + 1) if m else len(s)

    route = textwrap.dedent(r"""
    # --- VSP_P0_RUN_FILE_RAW_V2 ---
    @application.route("/api/vsp/run_file_raw_v2", methods=["GET"])
    def api_vsp_run_file_raw_v2():
        import mimetypes, time
        from pathlib import Path
        from flask import request, jsonify, send_file

        rid = (request.args.get("rid") or "").strip()
        path = (request.args.get("path") or "").strip()
        download = (request.args.get("download") or "").strip() in ("1","true","yes")

        if not rid or not path:
            return jsonify({"ok": False, "err": "missing rid/path", "rid": rid, "path": path}), 200

        roots = [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out",
        ]

        run_dir = None
        for rt in roots:
            cand = Path(rt) / rid
            if cand.exists() and cand.is_dir():
                run_dir = cand
                break
        if not run_dir:
            return jsonify({"ok": False, "err": "run_dir not found", "rid": rid, "roots": roots}), 200

        base = run_dir.resolve()
        target = (base / path).resolve()

        # traversal guard
        if not str(target).startswith(str(base) + "/"):
            return jsonify({"ok": False, "err": "path traversal blocked"}), 403

        # allow: reports/ or report/ OR a few root artifacts
        allow_prefix = (str(base / "reports"), str(base / "report"))
        allow_root = {
            str(base / "run_gate_summary.json"),
            str(base / "run_gate.json"),
            str(base / "findings_unified.json"),
            str(base / "verdict_4t.json"),
            str(base / "SUMMARY.txt"),
            str(base / "run_manifest.json"),
            str(base / "reports" / "findings_unified.json"),
            str(base / "reports" / "findings_unified.csv"),
            str(base / "reports" / "findings_unified.sarif"),
        }

        if not (str(target).startswith(allow_prefix) or str(target) in allow_root):
            return jsonify({"ok": False, "err": "not allowed", "path": path}), 403

        if not target.exists() or not target.is_file():
            return jsonify({"ok": False, "err": "not found", "path": path}), 404

        mt, _ = mimetypes.guess_type(str(target))
        if not mt:
            ext = target.suffix.lower()
            mt = {
                ".sarif": "application/sarif+json",
                ".zip": "application/zip",
                ".pdf": "application/pdf",
                ".html": "text/html",
                ".json": "application/json",
                ".csv": "text/csv",
                ".log": "text/plain",
                ".txt": "text/plain",
            }.get(ext, "application/octet-stream")

        resp = send_file(str(target), mimetype=mt, as_attachment=download, download_name=target.name)
        # helpful debug headers
        resp.headers["X-VSP-RID"] = rid
        resp.headers["X-VSP-PATH"] = path
        resp.headers["X-VSP-RAW"] = "v2"
        return resp
    # --- /VSP_P0_RUN_FILE_RAW_V2 ---
    """)
    s = s[:ins] + "\n" + route + "\n" + s[ins:]
    changed += 1

# --- 2) Patch X-Frame-Options logic (make it conditional for v2) ---
# We search broadly for any place that sets X-Frame-Options to DENY and patch that statement.
# Works for: resp.headers['X-Frame-Options']='DENY'  OR  resp.headers.setdefault('X-Frame-Options','DENY')
patched_xfo = 0

# Pattern A: assignment
patA = re.compile(r'(?m)^(?P<ind>\s*)(?P<obj>[a-zA-Z_][a-zA-Z0-9_]*)\.headers\[\s*[\'"]X-Frame-Options[\'"]\s*\]\s*=\s*[\'"]DENY[\'"]\s*$')
mA = patA.search(s)
if mA:
    ind=mA.group("ind"); obj=mA.group("obj")
    repl = (
        ind + "try:\n"
        + ind + "    from flask import request as _req\n"
        + ind + "    _p = (_req.path or \"\")\n"
        + ind + "except Exception:\n"
        + ind + "    _p = \"\"\n"
        + ind + f"{obj}.headers[\"X-Frame-Options\"] = \"SAMEORIGIN\" if _p.startswith(\"/api/vsp/run_file_raw_v2\") else \"DENY\""
    )
    s = s[:mA.start()] + repl + s[mA.end():]
    patched_xfo = 1

# Pattern B: setdefault
if not patched_xfo:
    patB = re.compile(r'(?m)^(?P<ind>\s*)(?P<obj>[a-zA-Z_][a-zA-Z0-9_]*)\.headers\.setdefault\(\s*[\'"]X-Frame-Options[\'"]\s*,\s*[\'"]DENY[\'"]\s*\)\s*$')
    mB = patB.search(s)
    if mB:
        ind=mB.group("ind"); obj=mB.group("obj")
        repl = (
            ind + "try:\n"
            + ind + "    from flask import request as _req\n"
            + ind + "    _p = (_req.path or \"\")\n"
            + ind + "except Exception:\n"
            + ind + "    _p = \"\"\n"
            + ind + f"{obj}.headers[\"X-Frame-Options\"] = \"SAMEORIGIN\" if _p.startswith(\"/api/vsp/run_file_raw_v2\") else \"DENY\""
        )
        s = s[:mB.start()] + repl + s[mB.end():]
        patched_xfo = 1

if patched_xfo:
    changed += 1
else:
    # leave file as-is (still safe); user can still use new-tab Open if needed
    pass

p.write_text(s, encoding="utf-8")
print("[OK] changed=", changed, "patched_xfo=", bool(patched_xfo))
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== smoke RAW v2 headers (XFO should be SAMEORIGIN for v2 if patched) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -i -sS "$BASE/api/vsp/run_file_raw_v2?rid=$RID&path=run_gate_summary.json" | head -n 25 || true
