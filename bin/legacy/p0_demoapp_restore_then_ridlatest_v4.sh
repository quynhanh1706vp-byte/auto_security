#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_before_restore_v4_${TS}"
echo "[BACKUP] ${APP}.bak_before_restore_v4_${TS}"

echo "== restore latest compiling backup of vsp_demo_app.py =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

app = Path("vsp_demo_app.py")
baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok_compile(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

good = None
for p in baks:
    if ok_compile(p):
        good = p
        break

if not good:
    print("[ERR] cannot find any compiling backup for vsp_demo_app.py")
    print("  candidates:", len(baks))
    sys.exit(2)

app.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored from:", good.name)
PY

echo "== inject rid_latest alias safely (add_url_rule; insert before __main__) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_LATEST_ALIAS_SAFE_V4"
if marker in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# detect Flask app var
m = re.search(r'^\s*(app|application)\s*=\s*Flask\s*\(', s, flags=re.M)
appvar = m.group(1) if m else "app"

block = f"""

# ===================== {marker} =====================
# Provide /api/vsp/rid_latest + /api/vsp/latest_rid as aliases of /api/vsp/rid_latest_gate_root
# so JS callers won't get rid=null.
def _vsp_register_rid_latest_alias_v4(_app):
    try:
        from flask import jsonify as _jsonify, request as _request
    except Exception:
        return

    def _handler():
        try:
            import json as _json
            import urllib.request as _ur
            base = (_request.url_root or "").rstrip("/")
            url = base + "/api/vsp/rid_latest_gate_root"
            with _ur.urlopen(url, timeout=2.5) as r:
                raw = r.read() or b"{{}}"
            data = _json.loads(raw.decode("utf-8", "replace"))
            if isinstance(data, dict) and data.get("rid"):
                return _jsonify(data)
            return _jsonify({{"ok": False, "rid": None, "gate_root": None, "degraded": True, "served_by": __file__}})
        except Exception as e:
            return _jsonify({{"ok": False, "rid": None, "gate_root": None, "degraded": True, "err": str(e), "served_by": __file__}})

    try:
        _app.add_url_rule("/api/vsp/rid_latest", "vsp_rid_latest_alias_v4", _handler, methods=["GET"])
    except Exception:
        pass
    try:
        _app.add_url_rule("/api/vsp/latest_rid", "vsp_latest_rid_alias_v4", _handler, methods=["GET"])
    except Exception:
        pass

try:
    _vsp_register_rid_latest_alias_v4({appvar})
except Exception:
    pass
# ===================== /{marker} =====================

"""

# insert before __main__ if present; else append
mm = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if mm:
    s2 = s[:mm.start()] + block + s[mm.start():]
else:
    s2 = s + block

p.write_text(s2, encoding="utf-8")
print("[OK] injected marker; appvar=", appvar, "insert_before_main=", bool(mm))
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke rid_latest (must include rid now) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 260; echo
echo "== smoke rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 260; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
