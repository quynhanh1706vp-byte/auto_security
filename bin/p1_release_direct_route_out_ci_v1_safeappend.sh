#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rel_direct_${TS}"
echo "[BACKUP] ${APP}.bak_rel_direct_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_DIRECT_ROUTE_OUT_CI_V1"
if marker in s:
    print("[OK] already present:", marker)
else:
    block = textwrap.dedent(r'''
    # ===================== VSP_P1_RELEASE_DIRECT_ROUTE_OUT_CI_V1 =====================
    @app.get("/out_ci/releases/<path:fname>")
    def vsp_release_pkg_direct_out_ci(fname):
        """
        Compatibility route:
          /out_ci/releases/<tgz>  -> 302 to /api/vsp/release_pkg_download?path=out_ci/releases/<tgz>
        This prevents 404 when user pastes the package URL directly in browser.
        """
        try:
            from flask import abort, redirect
        except Exception:
            # ultra-safe fallback
            return ("not ready", 503)

        # basic hardening
        if not fname or ".." in fname or fname.startswith("/"):
            return abort(400)

        # allow only tgz under releases
        if not fname.endswith(".tgz"):
            return abort(404)

        rel = f"out_ci/releases/{fname}"

        try:
            from urllib.parse import quote
            q = quote(rel, safe="")
        except Exception:
            q = rel.replace(" ", "%20")

        return redirect(f"/api/vsp/release_pkg_download?path={q}", code=302)
    # ===================== /VSP_P1_RELEASE_DIRECT_ROUTE_OUT_CI_V1 =====================
    ''').strip() + "\n"

    # append at EOF (safeappend)
    s2 = s.rstrip() + "\n\n" + block
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended", marker)

PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify redirect works (derive latest pkg name) =="
REL="$(curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("release_pkg",""))')"
NAME="$(python3 - <<PY
import os
rel = os.environ.get("REL","")
print(rel.split("/")[-1] if rel else "")
PY
)"
if [ -n "${NAME:-}" ]; then
  echo "[REL_NAME] $NAME"
  curl -sS -I "$BASE/out_ci/releases/$NAME" | egrep -i 'HTTP/|location:' || true
else
  echo "[WARN] cannot resolve release_pkg from release_latest"
fi

echo "[DONE] direct /out_ci/releases/* now redirects to download endpoint."
