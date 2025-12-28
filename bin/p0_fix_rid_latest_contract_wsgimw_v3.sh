#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_ridlatest_wsgimw_v3_${TS}"
echo "[BACKUP] ${WSGI}.bak_ridlatest_wsgimw_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_WSGI_MW_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# ===================== VSP_P0_RID_LATEST_WSGI_MW_V3 =====================
# Boot-safe: do NOT use @app.route here because `app` may be a middleware object.
# Gunicorn entrypoint is wsgi_vsp_ui_gateway:application. Wrap that WSGI callable.
# Contract: /api/vsp/rid_latest MUST always return JSON (never HTML/empty).

def _vsp__rid_latest_pick_fs_v3():
    try:
        import os, time
        from pathlib import Path
        base = Path(__file__).resolve().parent
        root = base.parent
        candidates = [
            root / "out",
            root / "out_ci",
            base / "out",
            base / "out_ci",
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        ]
        best = None  # (mtime, rid)
        for d in candidates:
            if not d.exists() or not d.is_dir():
                continue
            for sub in d.iterdir():
                if not sub.is_dir():
                    continue
                rid = sub.name
                if not (rid.startswith("VSP_") or rid.startswith("RUN_") or ("VSP_CI_" in rid)):
                    continue
                ok = False
                for rel in ("run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"):
                    if (sub / rel).exists():
                        ok = True; break
                if not ok and ((sub/"reports").exists() or (sub/"findings_unified.json").exists() or (sub/"reports/findings_unified.json").exists()):
                    ok = True
                if not ok:
                    continue
                mt = sub.stat().st_mtime
                if (best is None) or (mt > best[0]):
                    best = (mt, rid)
        return best[1] if best else ""
    except Exception:
        return ""

def _vsp__rid_latest_json_wsgi_mw_v3(_app):
    import json, time
    def _mw(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
        except Exception:
            path = ""
        if path == "/api/vsp/rid_latest":
            rid = _vsp__rid_latest_pick_fs_v3()
            out = {"ok": bool(rid), "rid": rid, "via": "wsgi_mw_v3", "ts": int(time.time())}
            body = json.dumps(out, ensure_ascii=False).encode("utf-8")
            start_response("200 OK", [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("Content-Length", str(len(body))),
            ])
            return [body]
        return _app(environ, start_response)
    return _mw

try:
    # ensure we wrap the exported callable used by gunicorn: wsgi_vsp_ui_gateway:application
    application = _vsp__rid_latest_json_wsgi_mw_v3(application)
    print("[VSP_P0_RID_LATEST_WSGI_MW_V3] installed on application")
except Exception as _e:
    try:
        print("[VSP_P0_RID_LATEST_WSGI_MW_V3] install failed:", repr(_e))
    except Exception:
        pass
# =================== end VSP_P0_RID_LATEST_WSGI_MW_V3 ===================
'''.strip("\n") + "\n"

s = s + "\n\n" + block
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

echo "== restart $SVC =="
systemctl restart "$SVC" || true
sleep 0.7
systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] $SVC active" || { echo "[ERR] $SVC not active"; systemctl --no-pager status "$SVC" -n 60 || true; exit 2; }

echo "== verify rid_latest =="
curl -fsS "$BASE/api/vsp/rid_latest"; echo
