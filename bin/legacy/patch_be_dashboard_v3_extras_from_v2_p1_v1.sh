#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dash_extras_${TS}" && echo "[BACKUP] $F.bak_dash_extras_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASHBOARD_V3_EXTRAS_FROM_V2_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

m=re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
flask_var = m.group(1) if m else "app"

block = f'''
# === {marker} ===
@{flask_var}.route("/api/vsp/dashboard_v3_extras_v1", methods=["GET"])
def api_vsp_dashboard_v3_extras_v1():
  rid = (request.args.get("rid") or "").strip()
  if not rid:
    # fallback: take latest from runs_index if exists
    try:
      j = api_vsp_runs_index_v3_fs_resolved()
      rid = (j.json.get("items") or [{{}}])[0].get("run_id") or ""
    except Exception:
      rid = ""
  rid = str(rid).strip()

  # call V2 handler directly (same process) for counts
  try:
    # simulate request args for V2: limit=1
    args = request.args.to_dict(flat=True)
    args.pop("rid", None)
    args["limit"]="1"
    # Temporarily patch request.args? (avoid): call function and parse JSON through flask response
    resp = api_vsp_findings_unified_v2(rid)
    # resp may be (response, code)
    if isinstance(resp, tuple):
      resp_obj = resp[0]
    else:
      resp_obj = resp
    data = resp_obj.get_json(silent=True) or {{}}
  except Exception:
    data = {{}}

  counts = (data.get("counts") or {{}})
  by_sev = counts.get("by_sev") or {{}}
  by_tool = counts.get("by_tool") or {{}}
  top_cwe = counts.get("top_cwe") or []
  unknown_count = int(counts.get("unknown_count") or 0)
  total = int(data.get("total") or 0)

  # score heuristic (commercial-ish): 100 - weighted findings / scale
  w = 0
  for k,v in by_sev.items():
    k = str(k or "").upper()
    v = int(v or 0)
    if k == "CRITICAL": w += v*50
    elif k == "HIGH": w += v*30
    elif k == "MEDIUM": w += v*15
    elif k == "LOW": w += v*5
    elif k == "INFO": w += v*1
  score = max(0, int(100 - (w/ max(1, 200))))  # scale factor 200

  # degraded/effective (P1): degraded = unknown_count, effective = total-unknown
  degraded = unknown_count
  effective = max(0, total - unknown_count)

  return jsonify({{
    "ok": True,
    "rid": rid,
    "kpi": {{
      "total": total,
      "effective": effective,
      "degraded": degraded,
      "score": score,
      "by_sev": by_sev,
      "by_tool": by_tool,
      "top_cwe": top_cwe,
      "unknown_count": unknown_count
    }},
    "sources": {{
      "findings_api": "/api/vsp/findings_unified_v2/<rid>",
      "marker": "{marker}"
    }}
  }}), 200
# === /{marker} ===
'''

p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended dashboard extras route on", flask_var)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK => $F"
