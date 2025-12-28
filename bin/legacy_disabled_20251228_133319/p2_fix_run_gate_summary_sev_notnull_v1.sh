#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_sevfix_${TS}"
echo "[OK] backup: ${APP}.bak_sevfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# locate the run_gate_summary_v1 handler block by keyword
idx = s.find("run_gate_summary_v1")
if idx < 0:
    print("[ERR] cannot find run_gate_summary_v1 in vsp_demo_app.py")
    sys.exit(2)

# find the function containing it (best-effort)
# search backwards to nearest "def " above
start = s.rfind("\ndef ", 0, idx)
if start < 0:
    start = s.rfind("\n@app.", 0, idx)
    start = s.rfind("\ndef ", 0, start if start>0 else idx)
if start < 0:
    print("[ERR] cannot locate function start")
    sys.exit(2)

# function end: next "\ndef " after start
end = s.find("\ndef ", start+1)
if end < 0:
    end = len(s)

block = s[start:end]

# Already patched?
if "VSP_SEV_NOTNULL_V1" in block:
    print("[OK] already patched")
    sys.exit(0)

# Heuristic: find the final return jsonify(...) and inject just before it
m = re.search(r'(\n\s*return\s+jsonify\([^\n]*\)\s*\n)', block)
if not m:
    # alternative: return flask.jsonify
    m = re.search(r'(\n\s*return\s+flask\.jsonify\([^\n]*\)\s*\n)', block)
if not m:
    print("[ERR] cannot find return jsonify(...) in handler block")
    sys.exit(2)

inject = r"""
    # VSP_SEV_NOTNULL_V1: contractize sev for UI charts
    try:
        _sev = (locals().get("sev") if "sev" in locals() else None)
        _j = locals().get("j") or locals().get("data") or locals().get("out") or None
        if isinstance(_j, dict):
            # pick sev from common schemas
            _sev = _j.get("sev") or _j.get("severity") or _j.get("severity_counts") or _j.get("sev_counts") or _j.get("by_severity") or _sev
            if _sev is None and isinstance(_j.get("summary"), dict):
                sm = _j.get("summary") or {}
                _sev = sm.get("sev") or sm.get("severity") or sm.get("severity_counts") or sm.get("sev_counts") or sm.get("by_severity")
            if not isinstance(_sev, dict):
                _sev = {}
            # fill 6-level normalized keys
            for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
                _sev.setdefault(k, 0)
            _j["sev"] = _sev
            # reflect back into locals commonly used in this function
            if "j" in locals() and isinstance(locals()["j"], dict):
                locals()["j"]["sev"] = _sev
            if "data" in locals() and isinstance(locals()["data"], dict):
                locals()["data"]["sev"] = _sev
    except Exception:
        pass
"""

block2 = block[:m.start(1)] + inject + block[m.start(1):]
s2 = s[:start] + block2 + s[end:]

p.write_text(s2, encoding="utf-8")
print("[OK] patched sev not-null")
PY

python3 -m py_compile vsp_demo_app.py

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
else
  echo "[WARN] no systemctl; restart manually"
fi
