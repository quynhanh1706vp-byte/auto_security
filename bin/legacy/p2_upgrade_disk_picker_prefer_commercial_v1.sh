#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_picker_${TS}"
echo "[OK] backup: ${APP}.bak_picker_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Patch inside VSP_V3_FROM_DISK_OVERRIDE_V2: replace rels list in _vsp_guess_paths_for_rid
pat = re.compile(r'rels\s*=\s*\[\s*(?:.|\n)*?\]\s*', re.M)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot locate rels = [...] in disk override block")

new_rels = """rels = [
        "reports/findings_unified_commercial.json",
        "report/findings_unified_commercial.json",
        "findings_unified_commercial.json",
        "unified/findings_unified.json",
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
        "reports/findings.json",
        "report/findings.json",
    ]
"""

s2 = s[:m.start()] + new_rels + s[m.end():]

# Also expand glob patterns to include commercial + unified/
s2 = s2.replace(
    'patterns = [\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified.json",\n    ]',
    'patterns = [\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified_commercial.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified_commercial.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified_commercial.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/unified/findings_unified.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified.json",\n        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified.json",\n    ]'
)

p.write_text(s2, encoding="utf-8")
print("[OK] patched rels+patterns (prefer commercial/unified)")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.7
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

curl -fsS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=5&offset=0" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("from_path=",j.get("from_path"),"total_findings=",j.get("total_findings"),"sev=",j.get("sev"))'

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"
