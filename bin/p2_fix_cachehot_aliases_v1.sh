#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_p2_cachehot_alias_${TS}"
echo "[BACKUP] ${WSGI}.bak_p2_cachehot_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_CACHEHOT_ALIASES_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r"""
# ===================== VSP_P2_CACHEHOT_ALIASES_V1 =====================
# Provide harmless aliases to reduce noisy "endpoint NOT FOUND" cachehot logs.
try:
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

def _vsp_p2_try_bind_cachehot_aliases(_app):
    try:
        if not getattr(_app, "add_url_rule", None): 
            return False
        if request is None or jsonify is None:
            return False

        # avoid double-binding if already exists
        existing = set()
        try:
            existing = set(getattr(_app, "view_functions", {}).keys())
        except Exception:
            existing = set()

        # alias 1: /api/vsp/rid_latest_gate_root -> same as /api/vsp/rid_latest
        def _alias_rid_latest_gate_root():
            try:
                vf = _app.view_functions.get("vsp_rid_latest_v1") or _app.view_functions.get("vsp_rid_latest")
                if vf:
                    return vf()
            except Exception:
                pass
            return jsonify({"ok": True, "rid": "", "note": "alias"}), 200

        # alias 2: /api/vsp/runs -> same as existing runs endpoint if present, else safe empty
        def _alias_runs():
            try:
                # find any runs handler
                for k in ("vsp_runs_v1","vsp_api_vsp_runs","api_vsp_runs","vsp_runs"):
                    vf = _app.view_functions.get(k)
                    if vf:
                        return vf()
            except Exception:
                pass
            # safe minimal contract
            lim = 0
            try:
                lim = int((request.args.get("limit") or "0")[:8])
            except Exception:
                lim = 0
            return jsonify({"ok": True, "runs": [], "limit": lim, "__via__": "VSP_P2_CACHEHOT_ALIASES_V1"}), 200

        # bind if route missing
        try:
            rules = [str(r.rule) for r in _app.url_map.iter_rules()]
        except Exception:
            rules = []

        if "/api/vsp/rid_latest_gate_root" not in rules:
            _app.add_url_rule("/api/vsp/rid_latest_gate_root", "vsp_p2_alias_rid_latest_gate_root", _alias_rid_latest_gate_root, methods=["GET"])
        if "/api/vsp/runs" not in rules:
            _app.add_url_rule("/api/vsp/runs", "vsp_p2_alias_runs", _alias_runs, methods=["GET"])

        print("[VSP_P2_CACHEHOT_ALIASES_V1] bound aliases: /api/vsp/rid_latest_gate_root, /api/vsp/runs")
        return True
    except Exception as e:
        print("[VSP_P2_CACHEHOT_ALIASES_V1] bind failed:", repr(e))
        return False

# bind on real flask app if available
try:
    _real = None
    for _cand in (globals().get("app"), globals().get("application")):
        if getattr(_cand, "url_map", None) and getattr(_cand, "add_url_rule", None):
            _real = _cand
            break
    if _real is not None:
        _vsp_p2_try_bind_cachehot_aliases(_real)
except Exception as _e:
    pass
# ===================== /VSP_P2_CACHEHOT_ALIASES_V1 =====================
"""
p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] patched:", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true
systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true

echo
echo "== VERIFY aliases =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 200; echo
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 240; echo
