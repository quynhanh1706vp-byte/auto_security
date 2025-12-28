#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rfallow_guard_${TS}"
echo "[BACKUP] ${APP}.bak_rfallow_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

MARK="VSP_P1_RUNFILEALLOW_GUARD_ALWAYS200_V1H"
p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

# detect app var from first route decorator
m = re.search(r'^\s*@(?P<var>app|application)\.route\s*\(', s, re.M)
if not m:
    # fallback: find any ".route(" usage
    m = re.search(r'@(?P<var>app|application)\.route\s*\(', s)
if not m:
    raise SystemExit("[ERR] cannot find @app.route(...) or @application.route(...) to anchor insertion")

var = m.group("var")
ins_at = m.start()  # insert BEFORE first route decorator

block = textwrap.dedent("""
# ===================== {MARK} =====================
# UI-safety: never 404 for run_file_allow due to missing params; return JSON 200 instead.
try:
    from flask import request as _vsp_req, jsonify as _vsp_jsonify
except Exception:
    _vsp_req = None
    _vsp_jsonify = None

def _vsp_runfileallow_guard_v1h():
    if _vsp_req is None or _vsp_jsonify is None:
        return None
    try:
        path = (_vsp_req.path or "")
        if not path.startswith("/api/"):
            return None
        if path.endswith("/run_file_allow") or path.endswith("/run_file_allow/"):
            rid = (_vsp_req.args.get("rid","") or "").strip()
            fpath = _vsp_req.args.get("path", None)
            if not rid:
                return _vsp_jsonify(ok=False, err="missing rid", where="run_file_allow_guard_v1h"), 200
            if fpath is None or str(fpath).strip() == "":
                return _vsp_jsonify(ok=False, rid=rid, err="missing path", where="run_file_allow_guard_v1h"), 200
        return None
    except Exception as e:
        return _vsp_jsonify(ok=False, err="guard_exc:"+type(e).__name__, where="run_file_allow_guard_v1h"), 200

try:
    {var}.before_request(_vsp_runfileallow_guard_v1h)
except Exception:
    pass
# ===================== /{MARK} =====================
""").format(MARK=MARK, var=var)

s2 = s[:ins_at] + block + "\n\n" + s[ins_at:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] inserted", MARK, "before first", f"@{var}.route(...)")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID_TEST:-VSP_CI_RUN_20251219_092640}"

echo "== [VERIFY] missing path should be 200 (NOT 404) =="
curl -fsS -i "$BASE/api/vsp/run_file_allow?rid=$RID" | sed -n '1,25p'
echo
echo "== [VERIFY] missing rid should be 200 (NOT 404) =="
curl -fsS -i "$BASE/api/vsp/run_file_allow" | sed -n '1,25p'
