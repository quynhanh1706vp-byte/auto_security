#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_report_ctxrename_${TS}" && echo "[BACKUP] $APP.bak_report_ctxrename_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# In vsp_report_cio_v1: before render_template_string(tpl, **ctx), insert rename guard
needle = "html = render_template_string(tpl, **ctx)"
if needle not in s:
    raise SystemExit("[ERR] cannot find render_template_string line")

if "VSP_REPORT_CTX_RENAME_V1" in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

s2 = s.replace(
    needle,
    "/*VSP_REPORT_CTX_RENAME_V1*/\n        # avoid Flask arg-name collision: ctx['source'] conflicts with render_template_string(source,...)\n        if isinstance(ctx, dict) and 'source' in ctx:\n            ctx['source_id'] = ctx.get('source')\n            ctx.pop('source', None)\n\n        " + needle,
    1
)

p.write_text(s2, encoding="utf-8")
print("[OK] inserted ctx['source'] -> ctx['source_id'] rename")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_ctx_source_rename_v1"
