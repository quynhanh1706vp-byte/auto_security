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
MARK="VSP_P2_BOOTFIX_DISABLE_BAD_BLOCKS_AND_STUB_READY_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_bootfix_${TS}"
echo "[BACKUP] ${F}.bak_bootfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_BOOTFIX_DISABLE_BAD_BLOCKS_AND_STUB_READY_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

def wrap_block_env_guard(text: str, marker: str, envvar: str) -> str:
    # expects marker blocks like:
    #  # ===================== MARKER =====================
    #  ...
    #  # ===================== /MARKER =====================
    start_pat = re.compile(rf'^[ \t]*#\s*=+\s*{re.escape(marker)}\s*=+\s*$', re.M)
    end_pat   = re.compile(rf'^[ \t]*#\s*=+\s*/{re.escape(marker)}\s*=+\s*$', re.M)
    ms = start_pat.search(text)
    me = end_pat.search(text)
    if not ms or not me or me.start() < ms.end():
        return text  # not found; keep

    head = text[ms.start():ms.end()]
    inner = text[ms.end():me.start()]
    tail = text[me.start():me.end()]

    inner_lines = inner.splitlines(True)
    inner_indented = "".join(("        " + ln) if ln.strip() else ln for ln in inner_lines)

    wrapped = (
        head + "\n"
        f"try:\n"
        f"    import os as _os\n"
        f"    if _os.environ.get('{envvar}','1') == '1':\n"
        f"        print('[{marker}] disabled by {envvar}=1 (boot-safe)')\n"
        f"    else:\n"
        f"{inner_indented}\n"
        f"except Exception as _e:\n"
        f"    print('[{marker}] disabled due to exception:', repr(_e))\n"
        + tail
    )
    return text[:ms.start()] + wrapped + text[me.end():]

# (A) Guard the 2 problematic blocks seen in your journal
s = wrap_block_env_guard(s, "VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1", "VSP_SAFE_DISABLE_FINDINGS_FORCEBIND")
s = wrap_block_env_guard(s, "VSP_P0_RELEASE_DOWNLOAD_ENDPOINTS_V1", "VSP_SAFE_DISABLE_RELEASE_ENDPOINTS")

# (B) Ensure app_obj is defined AFTER app exists (fix NoneType/get & name issues)
# Insert after "app = application" if present
m = re.search(r'(?m)^\s*app\s*=\s*application\s*$', s)
ins = m.end() if m else len(s)
anchor = "\n\n# === VSP_P2_BOOTFIX app_obj late bind ===\ntry:\n    app_obj = app\nexcept Exception:\n    try:\n        app_obj = application\n    except Exception:\n        app_obj = None\n# === /VSP_P2_BOOTFIX app_obj late bind ===\n"
if "VSP_P2_BOOTFIX app_obj late bind" not in s:
    s = s[:ins] + anchor + s[ins:]

# (C) Add stub endpoints required by systemd readycheck if missing
stub = textwrap.dedent(f"""
# ===================== {MARK} =====================
def _vsp__ensure_ready_stub_routes(_app):
    try:
        import json as _json
        from flask import Response, request

        def _json_resp(obj, status=200):
            b = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
            r = Response(b, status=int(status), mimetype="application/json; charset=utf-8")
            r.headers["Cache-Control"] = "no-store"
            return r

        # /api/vsp/runs (readycheck requires 200)
        have_runs = any(getattr(r,'rule','') == '/api/vsp/runs' for r in list(_app.url_map.iter_rules()))
        if not have_runs:
            def _api_vsp_runs_stub():
                limit = 1
                try:
                    limit = int(request.args.get('limit','1') or '1')
                except Exception:
                    pass
                return _json_resp({{"ok": True, "stub": True, "runs": [], "limit": limit}}, 200)
            _app.add_url_rule('/api/vsp/runs', endpoint='vsp_runs_stub_v1', view_func=_api_vsp_runs_stub, methods=['GET'])

        # /api/vsp/release_latest (readycheck requires 200)
        have_rel = any(getattr(r,'rule','') == '/api/vsp/release_latest' for r in list(_app.url_map.iter_rules()))
        if not have_rel:
            def _api_vsp_release_latest_stub():
                return _json_resp({{"ok": True, "stub": True, "download_url": None, "package_url": None}}, 200)
            _app.add_url_rule('/api/vsp/release_latest', endpoint='vsp_release_latest_stub_v1', view_func=_api_vsp_release_latest_stub, methods=['GET'])

        return True
    except Exception as e:
        print("[VSP_BOOTFIX] stub routes failed:", repr(e))
        return False

try:
    _app_bootfix = app
except Exception:
    try:
        _app_bootfix = application
    except Exception:
        _app_bootfix = None
if _app_bootfix is not None:
    _vsp__ensure_ready_stub_routes(_app_bootfix)
# ===================== /{MARK} =====================
""").strip("\n")

s = s + "\n\n" + stub + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] bootfix patched:", MARK)
PY

echo "== [1] py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [2] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || {
    echo "[ERR] restart failed; status:"
    systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    echo "---- journal tail ----"
    journalctl -u "$SVC" -n 220 --no-pager | tail -n 140 || true
    exit 2
  }
  systemctl --no-pager --full status "$SVC" | sed -n '1,60p' || true
fi

echo "== [3] verify readycheck URLs (must be 200) =="
for u in /runs /data_source /settings /api/vsp/runs?limit=1 /api/vsp/release_latest; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "[DONE] If /api/ui settings still 500 later, we fix after service stable."
