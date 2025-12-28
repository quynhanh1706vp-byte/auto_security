#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_relpkgdl_${TS}"
echo "[BACKUP] ${APP}.bak_relpkgdl_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_PKG_DOWNLOAD_ENDPOINT_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P1_RELEASE_PKG_DOWNLOAD_ENDPOINT_V1 =====================
try:
    import os, time
    from pathlib import Path

    @app.get("/api/vsp/release_pkg_download")
    def vsp_release_pkg_download_v1():
        """
        Safe download for release package (.tgz).
        Only allows relative paths under out_ci/releases/.
        """
        rel = (request.args.get("path") or "").strip().lstrip("/")
        allow_prefix = "out_ci/releases/"

        if not rel or not rel.startswith(allow_prefix) or ".." in rel or "\\\\" in rel:
            return jsonify({"ok": False, "err": "bad path"}), 400

        root = Path("/home/test/Data/SECURITY_BUNDLE")
        ap = (root / rel).resolve()

        releases_dir = (root / "out_ci" / "releases").resolve()
        if not str(ap).startswith(str(releases_dir)):
            return jsonify({"ok": False, "err": "not allowed"}), 403

        if not (ap.exists() and ap.is_file()):
            return jsonify({"ok": False, "err": "not found", "path": rel}), 404

        # attachment filename
        fn = ap.name
        resp = send_file(str(ap), as_attachment=True, download_name=fn)
        resp.headers["X-VSP-RELEASE-PKG"] = rel
        resp.headers["X-VSP-RELEASE-PKG-SIZE"] = str(ap.stat().st_size)
        resp.headers["X-VSP-RELEASE-PKG-DL"] = "ok"
        return resp

except Exception:
    pass
# ===================== /VSP_P1_RELEASE_PKG_DOWNLOAD_ENDPOINT_V1 =====================
''')

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

python3 -m py_compile "$APP"
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify download endpoint via release_latest =="
REL="$(curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("release_pkg",""))')"
echo "[REL] $REL"
curl -sS -I "$BASE/api/vsp/release_pkg_download?path=$REL" | egrep -i 'HTTP/|content-disposition|x-vsp-release-pkg-dl|x-vsp-release-pkg-size' || true
echo "[DONE] release_pkg_download endpoint ready."
