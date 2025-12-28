#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfile_compat_${TS}"
echo "[BACKUP] ${F}.bak_runfile_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUN_FILE_COMPAT_TO_RUN_FILE2_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We assume run_file2 helpers exist (_rf2_find_run_dir, _rf2_pick, _VSP_RF2_ALLOWED, _rf2_safe_rid)
# Add a before_request that intercepts /api/vsp/run_file and serves using the run_file2 logic.
inject = r'''
# =========================
# VSP_RUN_FILE_COMPAT_TO_RUN_FILE2_P0_V1
# Make legacy /api/vsp/run_file work by serving via run_file2 whitelist logic.
# This avoids 400 from old handler and makes UI clickable immediately.
# =========================
try:
    from flask import request as _rq_compat, send_file as _sf_compat, Response as _R_compat
except Exception:
    _rq_compat = None  # type: ignore

try:
    _app_compat = app  # noqa: F821
except Exception:
    _app_compat = None

if _app_compat is not None and getattr(_app_compat, "before_request", None) is not None:
    @_app_compat.before_request
    def _vsp_compat_run_file_to_run_file2():
        try:
            if not _rq_compat:
                return None
            if _rq_compat.path != "/api/vsp/run_file":
                return None

            rid = (_rq_compat.args.get("rid","") or "").strip()
            name = (_rq_compat.args.get("name","") or _rq_compat.args.get("path","") or _rq_compat.args.get("n","") or "").strip()

            # Use run_file2 validators if present
            if " _rf2_safe_rid" and callable(globals().get("_rf2_safe_rid")):
                if not globals()["_rf2_safe_rid"](rid):
                    return _R_compat('{"ok":false,"err":"bad rid"}', status=400, mimetype="application/json")
            else:
                # fallback
                import re as _re
                if not rid or not _re.fullmatch(r"[A-Za-z0-9_.:-]{6,160}", rid):
                    return _R_compat('{"ok":false,"err":"bad rid"}', status=400, mimetype="application/json")

            allowed = globals().get("_VSP_RF2_ALLOWED") or globals().get("_VSP_RUNFILE_ALLOWED") or {}
            if name not in allowed:
                return _R_compat('{"ok":false,"err":"not allowed"}', status=404, mimetype="application/json")

            find_dir = globals().get("_rf2_find_run_dir") or globals().get("_vsp__find_run_dir")
            pick_file = globals().get("_rf2_pick") or globals().get("_vsp__pick_file")
            if not callable(find_dir) or not callable(pick_file):
                return _R_compat('{"ok":false,"err":"compat helpers missing"}', status=500, mimetype="application/json")

            run_dir = find_dir(rid)
            if not run_dir:
                return _R_compat('{"ok":false,"err":"run not found"}', status=404, mimetype="application/json")

            fp = pick_file(run_dir, name)
            if not fp:
                return _R_compat('{"ok":false,"err":"file not found"}', status=404, mimetype="application/json")

            import mimetypes as _mt
            ctype,_ = _mt.guess_type(str(fp))
            ctype = ctype or ("text/html" if str(fp).endswith(".html") else "application/octet-stream")
            as_attach = not (str(fp).endswith(".html") or str(fp).endswith(".json"))
            return _sf_compat(fp, mimetype=ctype, as_attachment=as_attach, download_name=fp.name)
        except Exception:
            # let original handler run if something unexpected happens
            return None
# =========================
# END VSP_RUN_FILE_COMPAT_TO_RUN_FILE2_P0_V1
# =========================
'''
p.write_text(s.rstrip()+"\n"+inject+"\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== verify legacy /api/vsp/run_file now works (should be 200) =="
RID="RUN_VSP_KICS_TEST_20251211_161546"
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=${RID}&name=reports/findings_unified.json" | sed -n '1,12p'
