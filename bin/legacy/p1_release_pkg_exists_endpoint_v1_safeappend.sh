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
cp -f "$APP" "${APP}.bak_relpkgexists_${TS}"
echo "[BACKUP] ${APP}.bak_relpkgexists_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_PKG_EXISTS_ENDPOINT_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P1_RELEASE_PKG_EXISTS_ENDPOINT_V1 =====================
try:
    import os, time
    from pathlib import Path

    @app.get("/api/vsp/release_pkg_exists")
    def vsp_release_pkg_exists_v1():
        """
        Safe verifier for release package existence.
        Only allows relative paths under out_ci/releases/.
        """
        rel = (request.args.get("path") or "").strip()
        # normalize
        rel = rel.lstrip("/")

        allow_prefix = "out_ci/releases/"
        ok = True
        exists = False
        size = 0
        abs_path = ""

        if not rel or not rel.startswith(allow_prefix) or ".." in rel or "\\\\" in rel:
            return jsonify({"ok": False, "err": "bad path", "exists": False}), 400

        root = Path("/home/test/Data/SECURITY_BUNDLE")
        ap = (root / rel).resolve()
        abs_path = str(ap)

        # enforce within releases dir
        releases_dir = (root / "out_ci" / "releases").resolve()
        if not str(ap).startswith(str(releases_dir)):
            return jsonify({"ok": False, "err": "not allowed", "exists": False}), 403

        if ap.exists() and ap.is_file():
            exists = True
            try:
                size = ap.stat().st_size
            except Exception:
                size = 0

        return jsonify({
            "ok": ok,
            "exists": exists,
            "size": size,
            "path": rel,
            "abs": abs_path,
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        })
except Exception as _e:
    # do not break app import if something is odd
    pass
# ===================== /VSP_P1_RELEASE_PKG_EXISTS_ENDPOINT_V1 =====================
''')

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

python3 -m py_compile "$APP"

systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify endpoint =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("release_pkg"))' > /tmp/_relpkg.txt
REL="$(cat /tmp/_relpkg.txt)"
curl -fsS "$BASE/api/vsp/release_pkg_exists?path=$REL" | python3 -m json.tool
echo "[DONE] release_pkg_exists endpoint ready."
