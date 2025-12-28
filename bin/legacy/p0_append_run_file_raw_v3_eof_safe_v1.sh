#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rawv3_eof_${TS}"
echo "[BACKUP] ${WSGI}.bak_rawv3_eof_${TS}"

python3 - "$WSGI" <<'PY'
import sys, textwrap
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_RUN_FILE_RAW_V3_EOF_SAFE_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(f"""

# --- {marker} ---
def _vsp_api_run_file_raw_v3():
    import mimetypes
    from pathlib import Path
    from flask import request, jsonify, send_file

    rid = (request.args.get("rid") or "").strip()

    # accept path=... OR p=... (more robust)
    path = (request.args.get("path") or request.args.get("p") or "").strip()

    download = (request.args.get("download") or "").strip() in ("1","true","yes")

    if not rid or not path:
        return jsonify({{
            "ok": False,
            "err": "missing rid/path",
            "rid": rid,
            "path": path,
            "qs": request.query_string.decode("utf-8","replace")
        }}), 200

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
        return jsonify({{"ok": False, "err": "run_dir not found", "rid": rid, "roots": roots}}), 200

    base = run_dir.resolve()
    target = (base / path).resolve()

    # traversal guard
    if not str(target).startswith(str(base) + "/"):
        return jsonify({{"ok": False, "err": "path traversal blocked", "rid": rid, "path": path}}), 403

    allow_prefix = (str(base / "reports"), str(base / "report"))
    allow_root = {{
        str(base / "run_gate_summary.json"),
        str(base / "run_gate.json"),
        str(base / "findings_unified.json"),
        str(base / "verdict_4t.json"),
        str(base / "SUMMARY.txt"),
        str(base / "run_manifest.json"),
        str(base / "reports" / "findings_unified.json"),
        str(base / "reports" / "findings_unified.csv"),
        str(base / "reports" / "findings_unified.sarif"),
    }}

    if not (str(target).startswith(allow_prefix) or str(target) in allow_root):
        return jsonify({{"ok": False, "err": "not allowed", "rid": rid, "path": path}}), 403

    if not target.exists() or not target.is_file():
        return jsonify({{"ok": False, "err": "not found", "rid": rid, "path": path}}), 404

    mt, _ = mimetypes.guess_type(str(target))
    if not mt:
        ext = target.suffix.lower()
        mt = {{
            ".sarif": "application/sarif+json",
            ".zip": "application/zip",
            ".pdf": "application/pdf",
            ".html": "text/html",
            ".json": "application/json",
            ".csv": "text/csv",
            ".log": "text/plain",
            ".txt": "text/plain",
        }}.get(ext, "application/octet-stream")

    resp = send_file(str(target), mimetype=mt, as_attachment=download, download_name=target.name)
    resp.headers["X-VSP-RAW"] = "v3"
    resp.headers["X-VSP-RID"] = rid
    resp.headers["X-VSP-PATH"] = path
    return resp

# register new unique route (no conflict with buggy v2)
try:
    application.add_url_rule("/api/vsp/run_file_raw_v3", "api_vsp_run_file_raw_v3", _vsp_api_run_file_raw_v3, methods=["GET"])
except Exception:
    pass
# --- /{marker} ---
""")

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended raw v3 at EOF")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== smoke raw v3 =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -i -sS "$BASE/api/vsp/run_file_raw_v3?rid=$RID&path=run_gate_summary.json" | head -n 25
