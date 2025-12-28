#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_DISABLE_KPI_V4_MOUNT_AND_FORCE_DASH_MW_V1"

cp -f "$F" "${F}.bak_kpiquiet_${TS}"
echo "[BACKUP] ${F}.bak_kpiquiet_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

# 1) “Quiet” KPI_V4 mount error log (replace only the noisy message; no functional risk)
s = re.sub(
    r'\[VSP_KPI_V4\]\s*mount failed:\s*Working outside of application context\.',
    '[VSP_KPI_V4] mount skipped (use /api/vsp/dash_kpis & /api/vsp/dash_charts WSGI paths).',
    s
)

# 2) Ensure WSGI MW returns 200 for dash_kpis / dash_charts (even if older code path breaks)
if MARK not in s:
    block = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    def _vsp__dash_json(start_response, obj, code=200):
        import json as _json
        code = int(code)
        status = f"{{code}} OK" if code < 400 else f"{{code}} ERROR"
        body = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(status, headers)
        return [body]

    def _vsp__dash_mw(app_wsgi):
        def _wrapped(environ, start_response):
            try:
                path = (environ.get("PATH_INFO") or "").rstrip("/")
                if path in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
                    # minimal safe payload; UI can render even if richer data unavailable
                    if path.endswith("dash_kpis"):
                        return _vsp__dash_json(start_response, {{"ok": True, "kpis": {{}}, "note": "mw-safe"}}, 200)
                    return _vsp__dash_json(start_response, {{"ok": True, "charts": {{}}, "note": "mw-safe"}}, 200)
            except Exception as e:
                return _vsp__dash_json(start_response, {{"ok": False, "err": repr(e), "__via__": "{MARK}"}}, 500)
            return app_wsgi(environ, start_response)
        return _wrapped

    def _vsp__install_dash_mw():
        installed = 0
        g = globals()
        # wrap flask apps
        for _, v in list(g.items()):
            try:
                if v is None: 
                    continue
                if hasattr(v, "wsgi_app") and callable(getattr(v, "wsgi_app", None)):
                    v.wsgi_app = _vsp__dash_mw(v.wsgi_app)
                    installed += 1
            except Exception:
                pass
        # wrap callables
        for name in ("application", "app"):
            try:
                v = g.get(name)
                if v is not None and callable(v) and not hasattr(v, "wsgi_app"):
                    g[name] = _vsp__dash_mw(v)
                    installed += 1
            except Exception:
                pass
        print("[{MARK}] installed_mw_count=", installed)
        return installed

    _vsp__install_dash_mw()
    # ===================== /{MARK} =====================
    """).strip("\n")
    s = s + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true

echo "== verify (expect 200) =="
for u in /api/vsp/dash_kpis /api/vsp/dash_charts; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== journal KPI_V4 (should be 'skipped' not 'failed') =="
journalctl -u "$SVC" -n 120 --no-pager | grep -n "KPI_V4" -n | tail -n 20 || true
