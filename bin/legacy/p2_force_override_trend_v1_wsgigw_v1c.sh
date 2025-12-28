#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# Prefer WSGI gateway (gunicorn entrypoint)
W="wsgi_vsp_ui_gateway.py"
if [ ! -f "$W" ]; then
  # fallback to vsp_demo_app.py if you run app directly
  W="vsp_demo_app.py"
fi
[ -f "$W" ] || { echo "[ERR] cannot find wsgi_vsp_ui_gateway.py or vsp_demo_app.py"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_trend_override_${TS}"
echo "[BACKUP] ${W}.bak_trend_override_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys, textwrap

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TREND_V1_BEFORE_REQUEST_OVERRIDE_V1C"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

patch = textwrap.dedent(f"""
# --- {MARK} (auto-injected) ---
def _vsp_install_trend_v1_override(app):
    \"\"\"Hard override /api/vsp/trend_v1 to avoid ok:false 'not allowed' causing blank dashboard.\"\"\"
    try:
        from flask import request, jsonify
    except Exception:
        return

    if getattr(app, "_vsp_trend_override_installed", False):
        return
    app._vsp_trend_override_installed = True

    import os, json, datetime

    def _list_run_dirs(limit):
        roots = ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/out"]
        roots = [r for r in roots if os.path.isdir(r)]
        dirs = []
        for r in roots:
            try:
                for name in os.listdir(r):
                    if not (name.startswith("VSP_") or name.startswith("RUN_")):
                        continue
                    full = os.path.join(r, name)
                    if os.path.isdir(full):
                        try:
                            mt = os.path.getmtime(full)
                        except Exception:
                            mt = 0
                        dirs.append((mt, name, full))
            except Exception:
                pass
        dirs.sort(key=lambda x: x[0], reverse=True)
        return dirs[: max(limit*3, limit)]

    def _load_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None

    def _total_from_gate(j):
        if not isinstance(j, dict): return None
        for k in ("total", "total_findings", "findings_total", "total_unified"):
            v = j.get(k)
            if isinstance(v, int): return v
        c = j.get("counts") or j.get("severity_counts") or j.get("by_severity")
        if isinstance(c, dict):
            sm = 0
            for vv in c.values():
                if isinstance(vv, int): sm += vv
            return sm
        return None

    @app.before_request
    def _vsp_before_request_trend_override():
        if request.path != "/api/vsp/trend_v1":
            return None

        rid = (request.args.get("rid") or "").strip()
        try:
            limit = int(request.args.get("limit") or 20)
        except Exception:
            limit = 20
        if limit < 5: limit = 5
        if limit > 80: limit = 80

        points = []
        for mt, name, d in _list_run_dirs(limit):
            gate = _load_json(os.path.join(d, "run_gate_summary.json")) or _load_json(os.path.join(d, "reports", "run_gate_summary.json"))
            total = _total_from_gate(gate)
            if total is None:
                fu = _load_json(os.path.join(d, "findings_unified.json")) or _load_json(os.path.join(d, "reports", "findings_unified.json"))
                if isinstance(fu, list):
                    total = len(fu)
                elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
                    total = len(fu.get("findings"))
            if total is None:
                continue
            ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
            label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
            points.append({{"label": label, "run_id": name, "total": int(total), "ts": ts}})
            if len(points) >= limit:
                break

        return jsonify({{
            "ok": True,
            "marker": "{MARK}",
            "rid_requested": rid,
            "limit": limit,
            "points": points
        }})
# Install override if global 'app' exists (gunicorn typically imports this module)
try:
    _vsp_install_trend_v1_override(globals().get("app"))
except Exception:
    pass
# --- end {MARK} ---
""").lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended before_request override into", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

echo
echo "== [RESTART] restart service so patched code is loaded =="
echo "[CMD] sudo systemctl restart $SVC"
echo "      (if you have rights, run it now in the terminal)"
echo

echo "== [SMOKE] (after restart) trend_v1 should return ok:true + marker =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] rid_latest=$RID"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 240; echo
echo "[NOTE] If you still see err:not allowed, it means the service hasn't restarted (old code still running)."
