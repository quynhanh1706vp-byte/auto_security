#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p516_${TS}"
mkdir -p "$OUT"
cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P516_CSP_REPORT_PERSIST_FILE_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the endpoint function we added in P512
m=re.search(r'@app\.route\("/api/ui/csp_report_v1".*?\n(def api_ui_csp_report_v1\(\):[\s\S]*?\n\s*return \{"ok": True\}\s*\n)', s)
if not m:
    raise SystemExit("[ERR] cannot find api_ui_csp_report_v1 endpoint; did P512 apply?")

block=m.group(1)

# Insert file persist just before return {"ok": True}
insert = r'''
    # VSP_P516_CSP_REPORT_PERSIST_FILE_V1
    try:
        log_path = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log"
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci").mkdir(parents=True, exist_ok=True)
        # truncate long fields
        for k in ("document-uri","blocked-uri","violated-directive","original-policy"):
            if k in out and isinstance(out[k], str) and len(out[k]) > 800:
                out[k] = out[k][:800]
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(out, ensure_ascii=False) + "\n")
    except Exception:
        pass
'''

block2=re.sub(r'\n\s*return \{"ok": True\}\s*\n', "\n"+insert+"\n    return {\"ok\": True}\n", block, count=1)

s2=s[:m.start(1)] + block2 + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile $APP"
sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted"
