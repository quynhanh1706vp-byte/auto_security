#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_RID_LATEST_GATE_ROOT_API_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_ridlatest_${TS}"
echo "[BACKUP] ${W}.bak_ridlatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_RID_LATEST_GATE_ROOT_API_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# chèn trước export block marker (đã có trong file theo các patch trước)
anchor = "# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
idx = s.find(anchor)
if idx < 0:
    # fallback: chèn gần cuối file
    idx = len(s)

patch = textwrap.dedent(r"""
# ===================== VSP_P0_RID_LATEST_GATE_ROOT_API_V1 =====================
# Hard endpoint for Dashboard: choose latest RID having gate summary (commercial).
try:
    import json, re, os
    from pathlib import Path

    _RID_RE = re.compile(r'^(RUN|VSP_CI)_[0-9]{8}_[0-9]{6}')
    _ROOTS = [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]

    def _pick_latest_gate_root():
        best = None
        best_m = -1.0
        best_hit = None
        best_abs = None

        for root in _ROOTS:
            if not root.exists():
                continue
            for d in root.iterdir():
                if not d.is_dir():
                    continue
                if not _RID_RE.match(d.name):
                    continue

                hits = [
                    d/"reports"/"run_gate_summary.json",
                    d/"run_gate_summary.json",
                    d/"run_gate.json",
                    d/"reports"/"run_gate.json",
                ]
                hit = next((h for h in hits if h.is_file() and h.stat().st_size > 2), None)
                if not hit:
                    continue

                m = hit.stat().st_mtime
                if m > best_m:
                    best_m = m
                    best = d.name
                    best_abs = str(d)
                    try:
                        best_hit = str(hit.relative_to(d))
                    except Exception:
                        best_hit = str(hit)

        return best, best_hit, best_abs

    def _json_resp(start_response, code, obj):
        b = (json.dumps(obj, ensure_ascii=False).encode("utf-8"))
        hdrs = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(b))),
        ]
        start_response(code, hdrs)
        return [b]

    def _wrap(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO", "")
            if path == "/api/vsp/rid_latest_gate_root":
                rid, hit, absdir = _pick_latest_gate_root()
                return _json_resp(start_response, "200 OK", {
                    "ok": True,
                    "rid_latest_gate_root": rid,
                    "hit": hit,
                    "absdir": absdir,
                    "roots": [str(r) for r in _ROOTS],
                })
            return inner(environ, start_response)
        return _wsgi

    # wrap whichever callable exists
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap(application)

    print("[VSP_P0_RID_LATEST_GATE_ROOT_API_V1] enabled")
except Exception as _e:
    print("[VSP_P0_RID_LATEST_GATE_ROOT_API_V1] ERROR:", _e)
# ===================== /VSP_P0_RID_LATEST_GATE_ROOT_API_V1 =====================
""")

s2 = s[:idx] + patch + "\n" + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "== smoke: /api/vsp/rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid_latest_gate_root"),"hit=",j.get("hit"))'

echo "[DONE]"
