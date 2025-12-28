#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_api_stub_${TS}"
echo "[OK] backup: ${APP}.bak_api_stub_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# endpoints we want to guarantee exist (return ok even if empty)
targets = [
  "/api/vsp/top_cwe_exposure_v1",
  "/api/vsp/critical_high_by_tool_v1",
  "/api/vsp/top_risk_findings_v1",
  "/api/vsp/tool_buckets_v1",
]

missing = [t for t in targets if t not in s]
if not missing:
    print("[OK] no missing endpoints; skip")
    raise SystemExit(0)

stub = "\n\n# ===== VSP_DASHBOARD_STUBS_V1 (commercial: never hang loading) =====\n"
stub += "from flask import request, jsonify\n\n"
stub += "def _vsp_norm_sev_dict(d=None):\n"
stub += "    d = d if isinstance(d, dict) else {}\n"
stub += "    for k in ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE']:\n"
stub += "        d.setdefault(k, 0)\n"
stub += "    return d\n\n"

for ep in missing:
    fn = "vsp_stub_" + ep.strip("/").replace("/","_")
    stub += f"@app.get('{ep}')\n"
    stub += f"def {fn}():\n"
    stub += "    rid = (request.args.get('rid') or '').strip()\n"
    stub += "    # Return empty-but-valid payload (UI must not hang)\n"
    if "critical_high_by_tool" in ep:
        stub += "    return jsonify(ok=True, rid=rid, items=[], sev=_vsp_norm_sev_dict({}))\n\n"
    elif "top_cwe_exposure" in ep:
        stub += "    return jsonify(ok=True, rid=rid, items=[])\n\n"
    elif "top_risk_findings" in ep:
        stub += "    return jsonify(ok=True, rid=rid, items=[], total=0)\n\n"
    elif "tool_buckets" in ep:
        stub += "    return jsonify(ok=True, rid=rid, buckets=[])\n\n"
    else:
        stub += "    return jsonify(ok=True, rid=rid)\n\n"

stub += "# ===== /VSP_DASHBOARD_STUBS_V1 =====\n"

# append near end of file
s2 = s + stub
p.write_text(s2, encoding="utf-8")
print("[OK] appended stubs for:", ", ".join(missing))
PY

python3 -m py_compile vsp_demo_app.py

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
else
  echo "[WARN] no systemctl; restart manually"
fi
