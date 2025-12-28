#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_wsgi_trend_${TS}"
echo "[BACKUP] ${W}.bak_wsgi_trend_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_WSGI_TREND_OVERRIDE_V1E"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

patch = r'''
# --- VSP_P2_WSGI_TREND_OVERRIDE_V1E (auto-injected) ---
# Force override /api/vsp/trend_v1 at WSGI layer (works even if 'application' is not Flask).
def _vsp_install_wsgi_trend_override():
    import json, os, datetime, urllib.parse

    class _VspTrendOverrideMiddleware:
        def __init__(self, app):
            self.app = app

        def _list_run_dirs(self, limit: int):
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

        def _load_json(self, path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return None

        def _total_from_gate(self, j):
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

        def __call__(self, environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path == "/api/vsp/trend_v1":
                qs = urllib.parse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                rid = (qs.get("rid", [""])[0] or "").strip()
                try:
                    limit = int((qs.get("limit", ["20"])[0] or "20"))
                except Exception:
                    limit = 20
                if limit < 5: limit = 5
                if limit > 80: limit = 80

                points = []
                for mt, name, d in self._list_run_dirs(limit):
                    gate = self._load_json(os.path.join(d, "run_gate_summary.json")) or self._load_json(os.path.join(d, "reports", "run_gate_summary.json"))
                    total = self._total_from_gate(gate)
                    if total is None:
                        fu = self._load_json(os.path.join(d, "findings_unified.json")) or self._load_json(os.path.join(d, "reports", "findings_unified.json"))
                        if isinstance(fu, list):
                            total = len(fu)
                        elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
                            total = len(fu.get("findings"))
                    if total is None:
                        continue
                    ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
                    label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
                    points.append({"label": label, "run_id": name, "total": int(total), "ts": ts})
                    if len(points) >= limit:
                        break

                body = json.dumps({
                    "ok": True,
                    "marker": "VSP_P2_WSGI_TREND_OVERRIDE_V1E",
                    "rid_requested": rid,
                    "limit": limit,
                    "points": points
                }, ensure_ascii=False).encode("utf-8")

                start_response("200 OK", [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(body))),
                ])
                return [body]

            return self.app(environ, start_response)

    g = globals()
    app = g.get("application") or g.get("app")
    if app is None:
        return
    # avoid double wrap
    if getattr(app, "_vsp_trend_override_wrapped", False):
        return
    mw = _VspTrendOverrideMiddleware(app)
    mw._vsp_trend_override_wrapped = True
    if g.get("application") is not None:
        g["application"] = mw
    else:
        g["app"] = mw

try:
    _vsp_install_wsgi_trend_override()
except Exception:
    pass
# --- end VSP_P2_WSGI_TREND_OVERRIDE_V1E ---
'''.lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended WSGI middleware override into", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "== [SMOKE] trend_v1 should be ok:true + marker =="
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 320; echo
