#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need awk; need curl

# 0) Rescue: pick newest backup that compiles
tmp="$(mktemp -d /tmp/vsp_rescue_v3c_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

best=""
for f in $(ls -1t ${APP}.bak_* 2>/dev/null || true); do
  cp -f "$f" "$tmp/app.py"
  if python3 -m py_compile "$tmp/app.py" >/dev/null 2>&1; then
    best="$f"
    break
  fi
done
[ -n "${best:-}" ] || { echo "[ERR] no compiling backup found for ${APP}.bak_*"; exit 2; }

cp -f "$best" "$APP"
echo "[RESTORE] $APP <= $best"

# 1) Append wrapper endpoint /api/vsp/top_findings_v3c (do not touch existing v3)
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_TOPFINDINGS_V3C_WRAPPER_V1"
if MARK in s:
    print("[OK] wrapper already present")
else:
    wrapper = f'''
# ===================== {MARK} =====================
@app.get("/api/vsp/top_findings_v3c")
def api_vsp_top_findings_v3c():
    """
    Commercial-stable wrapper:
    - calls existing api_vsp_top_findings_v3()
    - adds: total, limit_applied, items_truncated
    - enforces items[:limit_applied]
    """
    _lim_s = (request.args.get("limit") or "200").strip()
    limit_applied = int(_lim_s) if _lim_s.isdigit() else 200
    limit_applied = max(1, min(limit_applied, 500))

    resp = api_vsp_top_findings_v3()

    code = None
    if isinstance(resp, tuple) and len(resp) >= 1:
        r0 = resp[0]
        code = resp[1] if len(resp) > 1 else None
        resp = r0

    try:
        j = resp.get_json(silent=True) if hasattr(resp, "get_json") else None
        if not isinstance(j, dict):
            return resp if code is None else (resp, code)

        items = j.get("items") or []
        if not isinstance(items, list):
            items = []
        total = len(items)
        items_truncated = total > limit_applied
        if items_truncated:
            items = items[:limit_applied]

        j["ok"] = bool(j.get("ok", True))
        j["api"] = "top_findings_v3c"
        j["limit_applied"] = limit_applied
        j["total"] = total
        j["items_truncated"] = items_truncated
        j["items"] = items

        out = jsonify(j)
        return out if code is None else (out, code)
    except Exception:
        return resp if code is None else (resp, code)
# =================== /{MARK} ======================
'''
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    if m:
        s = s[:m.start()] + wrapper + "\n" + s[m.start():]
    else:
        s = s + "\n" + wrapper
    p.write_text(s, encoding="utf-8")
    print("[OK] appended wrapper endpoint /api/vsp/top_findings_v3c")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

# 2) Switch UI to call v3c
JS="static/js/vsp_dashboard_luxe_v1.js"
if [ -f "$JS" ]; then
  cp -f "$JS" "${JS}.bak_topv3c_${TS}"
  python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
s=s.replace("/api/vsp/top_findings_v3", "/api/vsp/top_findings_v3c")
s=s.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v3c")
p.write_text(s, encoding="utf-8")
print("[OK] switched UI top_findings -> v3c")
PY
fi

# 3) Restart + probe
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v3c limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"api=",j.get("api"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'

echo "[NEXT] Ctrl+F5 on /vsp5"
