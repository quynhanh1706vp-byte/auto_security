#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_releaseapi_${TS}"
echo "[BACKUP] ${W}.bak_releaseapi_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_API_RELEASE_LATEST_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

mw = textwrap.dedent(r"""
# ===================== VSP_P0_API_RELEASE_LATEST_V1 =====================
# Provide stable endpoint: GET /api/vsp/release_latest
try:
  import json as _json
  from pathlib import Path as _Path
  from werkzeug.wrappers import Response as _Resp

  class _VSPReleaseLatestMW:
    def __init__(self, app):
      self.app = app

    def __call__(self, environ, start_response):
      try:
        if (environ.get("REQUEST_METHOD","GET") or "GET").upper() != "GET":
          return self.app(environ, start_response)

        if (environ.get("PATH_INFO","") or "") != "/api/vsp/release_latest":
          return self.app(environ, start_response)

        f = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/release_latest.json")
        if f.is_file():
          txt = f.read_text(encoding="utf-8", errors="replace").strip()
          try:
            j = _json.loads(txt) if txt else {}
          except Exception:
            j = {"ok": False, "err": "bad_release_latest_json", "_path": str(f)}
          if "ok" not in j: j["ok"] = True
          resp = _Resp(_json.dumps(j, ensure_ascii=False).encode("utf-8"),
                       content_type="application/json; charset=utf-8", status=200)
        else:
          resp = _Resp(_json.dumps({"ok": False, "err": "missing_release_latest_json", "_path": str(f)}).encode("utf-8"),
                       content_type="application/json; charset=utf-8", status=200)
        resp.headers["Cache-Control"] = "no-store"
        return resp(environ, start_response)
      except Exception:
        return self.app(environ, start_response)

  if "application" in globals() and callable(globals().get("application")):
    application = _VSPReleaseLatestMW(application)
except Exception:
  pass
# ===================== /VSP_P0_API_RELEASE_LATEST_V1 =====================
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + mw, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== probe =="
curl -sS "$BASE/api/vsp/release_latest" | head -c 220; echo
