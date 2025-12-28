#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_raw_iframe_${TS}"
echo "[BACKUP] ${WSGI}.bak_raw_iframe_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_RUN_FILE_RAW_V1_IFRAME_SAMEORIGIN"

changed=0

# 1) Add after_request exception for raw endpoint
if marker not in s:
    # find an existing after_request hook; if none, create one near application assignment
    ins = None
    m = re.search(r'(?m)^\s*application\s*=\s*app\s*$', s)
    if not m:
        m = re.search(r'(?m)^\s*application\s*=\s*.*$', s)
    if m:
        ins = s.find("\n", m.end())
        if ins < 0: ins = m.end()
        ins += 1
    else:
        ins = len(s)

    hook = textwrap.dedent(f"""
    # --- {marker} ---
    @application.after_request
    def _vsp_iframe_sameorigin_for_raw(resp):
        try:
            from flask import request
            p = request.path or ""
            if p.startswith("/api/vsp/run_file_raw_v1"):
                # allow iframe embedding for SAME ORIGIN only (commercial-safe)
                resp.headers["X-Frame-Options"] = "SAMEORIGIN"
        except Exception:
            pass
        return resp
    # --- /{marker} ---
    """)
    s = s[:ins] + "\n" + hook + "\n" + s[ins:]
    changed += 1

# 2) Add run_file_raw_v1 route if missing
if re.search(r'\/api\/vsp\/run_file_raw_v1', s) is None:
    # insert near other api routes
    m = re.search(r'(?m)^\s*application\s*=\s*app\s*$', s)
    if not m:
        m = re.search(r'(?m)^\s*application\s*=\s*.*$', s)
    ins = s.find("\n", m.end()) + 1 if m else len(s)

    route = textwrap.dedent(r"""
    @application.route("/api/vsp/run_file_raw_v1", methods=["GET"])
    def api_vsp_run_file_raw_v1():
        import mimetypes
        from pathlib import Path
        from flask import request, jsonify, send_file

        rid = (request.args.get("rid") or "").strip()
        path = (request.args.get("path") or "").strip()
        download = (request.args.get("download") or "").strip() in ("1","true","yes")

        if not rid or not path:
            return jsonify({"ok": False, "err": "missing rid/path"}), 200

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
            return jsonify({"ok": False, "err": "run_dir not found", "rid": rid}), 200

        base = run_dir.resolve()
        target = (base / path).resolve()

        # traversal guard
        if str(target).find(str(base)) != 0:
            return jsonify({"ok": False, "err": "path traversal blocked"}), 403

        # whitelist: reports/ or report/ or selected root files
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
            return jsonify({"ok": False, "err": "not allowed"}), 403

        if not target.exists() or not target.is_file():
            return jsonify({"ok": False, "err": "not found"}), 404

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

        return send_file(str(target), mimetype=mt, as_attachment=download, download_name=target.name)
    """)
    s = s[:ins] + "\n" + route + "\n" + s[ins:]
    changed += 1

p.write_text(s, encoding="utf-8")
print("[OK] changed=", changed)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== smoke raw (headers) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -i -sS "$BASE/api/vsp/run_file_raw_v1?rid=$RID&path=run_gate_summary.json" | head -n 18
