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

MARK="VSP_P1_RUNFILEALLOW_GUARD_ALWAYS200_V1G"
p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

# detect flask app var: app = Flask(...) or application = Flask(...)
m = re.search(r'^(?P<var>app|application)\s*=\s*Flask\([^\n]*\)\s*$', s, re.M)
if not m:
    raise SystemExit("[ERR] cannot find Flask app init line: app=Flask(...)")

var = m.group("var")

block = textwrap.dedent("""
# ===================== {MARK} =====================
# UI-safety: never 404 for run_file_allow due to missing params; return JSON 200 instead.
try:
    from flask import request as _vsp_req, jsonify as _vsp_jsonify
except Exception:
    _vsp_req = None
    _vsp_jsonify = None

@{var}.before_request
def _vsp_runfileallow_guard_v1g():
    if _vsp_req is None or _vsp_jsonify is None:
        return None
    try:
        path = (_vsp_req.path or "")
        # cover both /api/vsp/run_file_allow and alias like /api/vsp/run_file_allow (and any /api/*/run_file_allow)
        if not path.startswith("/api/"):
            return None
        if path.endswith("/run_file_allow") or path.endswith("/run_file_allow/"):
            rid = (_vsp_req.args.get("rid","") or "").strip()
            fpath = _vsp_req.args.get("path", None)
            # IMPORTANT: always-200 JSON (commercial UI stability)
            if not rid:
                return _vsp_jsonify(ok=False, err="missing rid", where="run_file_allow_guard"), 200
            if fpath is None or str(fpath).strip() == "":
                return _vsp_jsonify(ok=False, rid=rid, err="missing path", where="run_file_allow_guard"), 200
        return None
    except Exception as e:
        # never throw; never 500
        return _vsp_jsonify(ok=False, err="guard_exc:"+type(e).__name__, where="run_file_allow_guard"), 200
# ===================== /{MARK} =====================
""").format(MARK=MARK, var=var)

# insert right after flask app init line
ins_at = m.end()
s2 = s[:ins_at] + "\n\n" + block + "\n" + s[ins_at:]

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] inserted", MARK, "after", var, "= Flask(...)")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [VERIFY] missing path should be 200 (not 404) =="
RID="${RID_TEST:-VSP_CI_RUN_20251219_092640}"
curl -fsS -i "$BASE/api/vsp/run_file_allow?rid=$RID" | sed -n '1,25p'
echo
echo "== [VERIFY] missing rid should be 200 (not 404) =="
curl -fsS -i "$BASE/api/vsp/run_file_allow" | sed -n '1,25p'
