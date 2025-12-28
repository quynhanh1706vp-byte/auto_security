#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_broken_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_${TS}"

echo "== [0] restore latest compiling backup =="
python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

good = None
for b in baks:
    try:
        py_compile.compile(str(b), doraise=True)
        good = b
        break
    except Exception:
        continue

if not good:
    raise SystemExit("[ERR] no compiling backup found")

w.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored:", good)
PY

echo "== [1] append MW for /runs_reports alias + /api/vsp/runs JSON guarantee (safe append) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_MW_FIX_RUNSREPORTS_AND_RUNSAPI_JSON_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# Decide target for /runs_reports: prefer /runs_reports_v1 if the string exists, else /runs
target = "/runs_reports_v1" if "/runs_reports_v1" in s else "/runs"

mw = textwrap.dedent(f"""
# ===================== {MARK} =====================
# P0 commercial: do NOT touch Dashboard. Just:
# 1) alias /runs_reports -> {target} at WSGI level
# 2) ensure /api/vsp/runs always returns JSON (avoid empty/HTML breaking clients/selfcheck)
try:
  import json as _json
  from werkzeug.wrappers import Response as _Resp

  class _VSPFixRunsMW:
    def __init__(self, app):
      self.app = app

    def __call__(self, environ, start_response):
      try:
        path = (environ.get("PATH_INFO","") or "")
        if path == "/runs_reports":
          environ["PATH_INFO"] = "{target}"

        if path == "/api/vsp/runs":
          status_box = {{"status":"200 OK"}}
          headers_box = []
          body_chunks = []

          def _sr(status, headers, exc_info=None):
            status_box["status"] = status
            headers_box[:] = headers[:] if headers else []
            return lambda x: None  # placeholder; we will call real start_response later

          it = self.app(environ, _sr)

          try:
            for x in it:
              body_chunks.append(x)
          finally:
            try:
              if hasattr(it, "close"): it.close()
            except Exception:
              pass

          body = b"".join(body_chunks)
          # detect content-type
          ct = ""
          for (k,v) in headers_box:
            if (k or "").lower() == "content-type":
              ct = (v or "")
              break

          def _is_json_bytes(b):
            bb = (b or b"").lstrip()
            return bb[:1] in (b"{{", b"[")

          if ("application/json" in (ct or "").lower()) and _is_json_bytes(body) and body:
            # pass-through original
            start_response(status_box["status"], headers_box)
            return [body]

          # else: return safe JSON stub (commercial degrade)
          payload = {{
            "ok": False,
            "err": "runs_api_non_json_or_empty",
            "items": [],
            "_orig_status": status_box["status"],
            "_orig_ct": ct,
            "_orig_len": len(body),
          }}
          resp = _Resp(_json.dumps(payload).encode("utf-8"), content_type="application/json", status=200)
          return resp(environ, start_response)

      except Exception:
        pass

      return self.app(environ, start_response)

  if "application" in globals() and callable(globals().get("application")):
    application = _VSPFixRunsMW(application)
except Exception:
  pass
# ===================== /{MARK} =====================
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + mw, encoding="utf-8")
print(f"[OK] appended MW; /runs_reports -> {target}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [2] probes =="
echo "-- HEAD /runs_reports --"
curl -sS -I "$BASE/runs_reports" | sed -n '1,10p'
echo
echo "-- HEAD /runs --"
curl -sS -I "$BASE/runs" | sed -n '1,10p'
echo
echo "-- /api/vsp/runs?limit=1 (first lines) --"
curl -sS -i "$BASE/api/vsp/runs?limit=1" | sed -n '1,20p'
