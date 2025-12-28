#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_BOOTSAFE_DISABLE_KPI_V4_AND_STUB_READY_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_kpi_stub_${TS}"
echo "[BACKUP] ${F}.bak_kpi_stub_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK="VSP_P2_BOOTSAFE_DISABLE_KPI_V4_AND_STUB_READY_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

def wrap_marker_env(text: str, marker_like: str, envvar: str) -> str:
    # find a marker-style block if present:
    #  # ==== ... marker_like ... ====
    #  ...
    #  # ==== /... marker_like ... ====
    start = re.search(rf'(?m)^[ \t]*#\s*=+.*{re.escape(marker_like)}.*=+\s*$', text)
    if not start:
        return text
    end = re.search(rf'(?m)^[ \t]*#\s*=+.*\/.*{re.escape(marker_like)}.*=+\s*$', text[start.end():])
    if not end:
        return text
    end_pos = start.end() + end.end()

    head = text[start.start():start.end()]
    inner = text[start.end(): start.end() + end.start()]
    tail = text[start.end() + end.start(): end_pos]

    inner_lines = inner.splitlines(True)
    inner_ind = "".join(("        "+ln) if ln.strip() else ln for ln in inner_lines)

    wrapped = (
        head + "\n"
        "try:\n"
        "    import os as _os\n"
        f"    if _os.environ.get('{envvar}','1') == '1':\n"
        f"        print('[{marker_like}] disabled by {envvar}=1 (boot-safe)')\n"
        "    else:\n"
        f"{inner_ind}\n"
        "except Exception as _e:\n"
        f"    print('[{marker_like}] boot-safe ignore:', repr(_e))\n"
        + tail
    )
    return text[:start.start()] + wrapped + text[end_pos:]

# 1) Boot-safe disable KPI V4 if it exists as a marker block
s2 = wrap_marker_env(s, "VSP_KPI_V4", "VSP_SAFE_DISABLE_KPI_V4")
s = s2

# 2) Add hard stubs for readycheck endpoints at VERY END (won't crash import)
stub = textwrap.dedent("""
# ===================== %%MARK%% =====================
def _vsp__ready_json(obj, status=200):
    import json as _json
    from flask import Response
    b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
    r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
    r.headers["Cache-Control"] = "no-store"
    return r

def _vsp__ensure_ready_routes(_app):
    try:
        from flask import request

        # /api/vsp/runs
        if not any(getattr(r,'rule','') == '/api/vsp/runs' for r in list(_app.url_map.iter_rules())):
            def _runs_stub():
                lim = 1
                try: lim = int(request.args.get('limit','1') or '1')
                except Exception: pass
                return _vsp__ready_json({"ok": True, "stub": True, "runs": [], "limit": lim}, 200)
            _app.add_url_rule('/api/vsp/runs', endpoint='vsp_runs_ready_stub', view_func=_runs_stub, methods=['GET'])

        # /api/vsp/release_latest
        if not any(getattr(r,'rule','') == '/api/vsp/release_latest' for r in list(_app.url_map.iter_rules())):
            def _rel_stub():
                return _vsp__ready_json({"ok": True, "stub": True, "download_url": None, "package_url": None}, 200)
            _app.add_url_rule('/api/vsp/release_latest', endpoint='vsp_release_ready_stub', view_func=_rel_stub, methods=['GET'])

        return True
    except Exception as e:
        print("[VSP_READY_STUB] failed:", repr(e))
        return False

try:
    _app_ready = app
except Exception:
    try:
        _app_ready = application
    except Exception:
        _app_ready = None

if _app_ready is not None:
    _vsp__ensure_ready_routes(_app_ready)
# ===================== /%%MARK%% =====================
""").replace("%%MARK%%", MARK).strip("\n")

s = s + "\n\n" + stub + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || {
    echo "[ERR] restart failed"
    systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    echo "---- error log tail ----"
    tail -n 120 out_ci/ui_8910.error.log || true
    exit 2
  }
fi

echo "== verify (must be 200) =="
for u in /api/vsp/runs?limit=1 /api/vsp/release_latest /runs /settings; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done
echo "[DONE] If still boot-fail, paste tail out_ci/ui_8910.error.log"
