#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

FILES=(wsgi_vsp_ui_gateway.py vsp_demo_app.py)
TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import time

files = ["wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"]
marker = "VSP_P0_API_RID_LATEST_V1"

block = r'''
# ===================== VSP_P0_API_RID_LATEST_V1 =====================
# Provides /api/vsp/rid_latest so UI can bootstrap RID and stop skeleton loading.
# Commercial: set VSP_RUNS_ROOT or VSP_RUNS_ROOTS (colon/comma separated) to avoid scanning.
try:
    import os, time
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

_VSP_P0_RID_LATEST_CACHE = {"ts": 0.0, "rid": None}

def _vsp_p0_guess_roots_v1():
    roots = []
    env = (os.environ.get("VSP_RUNS_ROOTS") or os.environ.get("VSP_RUNS_ROOT") or "").strip()
    if env:
        for part in env.replace(",", ":").split(":"):
            part = part.strip()
            if part:
                roots.append(part)
    # common defaults (no sudo)
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
        "/home/test/Data/SECURITY_BUNDLE",
        "/home/test/Data",
    ]
    # de-dup keep order
    seen = set()
    out = []
    for r in roots:
        if r in seen: 
            continue
        seen.add(r)
        out.append(r)
    return out

def _vsp_p0_pick_latest_rid_v1():
    # cache 5 seconds to avoid repeated scans
    now = time.time()
    if (now - _VSP_P0_RID_LATEST_CACHE["ts"]) < 5 and _VSP_P0_RID_LATEST_CACHE["rid"]:
        return _VSP_P0_RID_LATEST_CACHE["rid"]

    best = (None, -1.0)  # (rid, mtime)
    roots = _vsp_p0_guess_roots_v1()

    for base in roots:
        try:
            if not os.path.isdir(base):
                continue

            # 1) direct gate_root_* under base
            try:
                for name in os.listdir(base):
                    if not name.startswith("gate_root_"):
                        continue
                    p = os.path.join(base, name)
                    if not os.path.isdir(p):
                        continue
                    mt = os.path.getmtime(p)
                    rid = name[len("gate_root_"):]
                    if mt > best[1] and rid:
                        best = (rid, mt)
            except Exception:
                pass

            # 2) one-level down: base/*/gate_root_*
            try:
                for name in os.listdir(base):
                    p1 = os.path.join(base, name)
                    if not os.path.isdir(p1):
                        continue
                    try:
                        for name2 in os.listdir(p1):
                            if not name2.startswith("gate_root_"):
                                continue
                            p = os.path.join(p1, name2)
                            if not os.path.isdir(p):
                                continue
                            mt = os.path.getmtime(p)
                            rid = name2[len("gate_root_"):]
                            if mt > best[1] and rid:
                                best = (rid, mt)
                    except Exception:
                        pass
            except Exception:
                pass

        except Exception:
            continue

    rid = best[0]
    _VSP_P0_RID_LATEST_CACHE["ts"] = now
    _VSP_P0_RID_LATEST_CACHE["rid"] = rid
    return rid

def vsp_rid_latest_v1():
    # Always 200 JSON
    try:
        rid = None
        if request is not None:
            rid = (request.args.get("rid") or request.args.get("run_id") or "").strip() or None
        if not rid:
            rid = _vsp_p0_pick_latest_rid_v1()
        gate_root = f"gate_root_{rid}" if rid else None
        return jsonify({
            "ok": bool(rid),
            "rid": rid,
            "gate_root": gate_root,
            "degraded": (not bool(rid)),
            "served_by": __file__,
        }), 200
    except Exception as e:
        try:
            return jsonify({"ok": False, "err": str(e), "served_by": __file__}), 200
        except Exception:
            return ("{}", 200, {"Content-Type":"application/json"})

# Register route if possible
try:
    _app = globals().get("app") or globals().get("application")
    if _app and hasattr(_app, "add_url_rule"):
        try:
            _app.add_url_rule("/api/vsp/rid_latest", "vsp_rid_latest_v1", vsp_rid_latest_v1, methods=["GET"])
        except Exception:
            pass
except Exception:
    pass
# ===================== /VSP_P0_API_RID_LATEST_V1 =====================
'''.lstrip("\n")

for fn in files:
    p = Path(fn)
    if not p.exists():
        print("[SKIP] missing:", fn)
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[SKIP] already patched:", fn)
        continue
    bak = p.with_name(p.name + f".bak_ridlatest_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] patched:", fn)
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke rid_latest (must be 200 + ok true) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 280; echo
echo "== smoke vsp5 scripts =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 20
echo "[DONE] Ctrl+Shift+R /vsp5"
