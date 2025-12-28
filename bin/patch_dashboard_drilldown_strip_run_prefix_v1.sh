#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_striprun_${TS}" && echo "[BACKUP] $F.bak_striprun_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Patch inside DRILL_ART_V2 block: after rid extraction, normalize rid (strip RUN_/RID:)
pat = r"(const rid\s*=\s*\(title[^\n]*\);\s*)"
if re.search(pat, s):
    s2 = re.sub(pat, r"""\1
      let _rid = rid;
      if(_rid){ _rid = String(_rid).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,''); }
      const rid2 = _rid;
""", s, count=1)
    # replace later uses of rid with rid2 only inside the fetch line (best effort)
    s2 = s2.replace("encodeURIComponent(rid)", "encodeURIComponent(rid2 || rid)")
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected rid strip (RUN_/RID:) for drilldown artifacts")
else:
    print("[WARN] rid extraction line not found; nothing patched")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_drilldown_strip_run_prefix_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
