#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_release_dl_${TS}"
echo "[BACKUP] ${W}.bak_release_dl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1 =====================
# Serve releases/release_latest.json and package downloads safely (only from ui/releases)
try:
    import os, json, re as _re
    from flask import jsonify, send_from_directory, abort, request

    _VSP_UI_ROOT = os.path.dirname(os.path.abspath(__file__))
    _VSP_RELEASE_DIR = os.path.join(_VSP_UI_ROOT, "releases")
    _VSP_RELEASE_LATEST = os.path.join(_VSP_RELEASE_DIR, "release_latest.json")

    def _vsp_safe_filename(name: str) -> bool:
        if not name or "/" in name or "\\" in name or ".." in name:
            return False
        # allow zip/tar.gz/sha256/json only
        return bool(_re.match(r'^[A-Za-z0-9._-]+(\.zip|\.tar\.gz|\.sha256|\.json)$', name))

    @app_obj.get("/api/vsp/release_latest")
    def api_vsp_release_latest_v1():
        # always no-store
        try:
            if not os.path.isfile(_VSP_RELEASE_LATEST):
                return jsonify({"ok": False, "err": "release_latest.json not found"}), 404
            with open(_VSP_RELEASE_LATEST, "r", encoding="utf-8", errors="ignore") as f:
                j = json.load(f)
            pkg_path = (j.get("package_path") or "").strip()
            pkg_name = os.path.basename(pkg_path) if pkg_path else ""
            out = dict(j)
            out["ok"] = True
            out["package_name"] = pkg_name
            if pkg_name and _vsp_safe_filename(pkg_name):
                out["download_url"] = f"/api/vsp/download/{pkg_name}"
                sha_name = pkg_name + ".sha256"
                if os.path.isfile(os.path.join(_VSP_RELEASE_DIR, sha_name)) and _vsp_safe_filename(sha_name):
                    out["sha256_url"] = f"/api/vsp/download/{sha_name}"
            return jsonify(out)
        except Exception as e:
            return jsonify({"ok": False, "err": f"release_latest error: {e}"}), 500

    @app_obj.get("/api/vsp/download/<path:filename>")
    def api_vsp_download_file_v1(filename):
        if not _vsp_safe_filename(filename):
            abort(400)
        fpath = os.path.join(_VSP_RELEASE_DIR, filename)
        if not os.path.isfile(fpath):
            abort(404)
        # attachment download
        return send_from_directory(_VSP_RELEASE_DIR, filename, as_attachment=True)

    print("[VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1] enabled, dir=", _VSP_RELEASE_DIR)
except Exception as _e:
    print("[VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1] ERROR:", _e)
# ===================== /VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1 =====================
''').strip() + "\n\n"

# append near end of file (safe)
s2 = s + "\n\n" + block
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", MARK)
PY

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify /api/vsp/release_latest =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -m json.tool | head -n 80

echo "== verify download_url (HEAD) =="
DL="$(curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("download_url",""))')"
[ -n "$DL" ] || { echo "[ERR] missing download_url"; exit 2; }
curl -fsS -I "$BASE$DL" | sed -n '1,12p'

echo "[DONE] release_latest + download endpoints ready."
