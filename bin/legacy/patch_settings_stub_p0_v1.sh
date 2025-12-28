#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
TPL="templates/vsp_settings_v1.html"
MARK="VSP_SETTINGS_STUB_P0_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_${MARK}_${TS}"
echo "[BACKUP] $APP.bak_${MARK}_${TS}"
mkdir -p templates

cat > "$TPL" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>VSP Settings</title>
<style>body{margin:0;background:#070d18;color:#dbe7ff;font-family:system-ui} .wrap{max-width:1200px;margin:0 auto;padding:18px}
.card{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:14px;margin:12px 0}
a{color:#9fe2ff;text-decoration:none}</style></head>
<body><div class="wrap">
<h2>Settings</h2>
<div class="card">P0 stub (commercial): show tool config + paths later.</div>
<div class="card"><a href="/vsp4">← Back to Dashboard</a></div>
</div></body></html>
HTML

python3 - <<'PY'
from pathlib import Path
import re
MARK="VSP_SETTINGS_STUB_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] already:", MARK)
else:
    block = r'''
# === VSP_SETTINGS_STUB_P0_V1 ===
@app.get("/settings")
def vsp_settings_page():
    return render_template("vsp_settings_v1.html")
# === /VSP_SETTINGS_STUB_P0_V1 ===
'''.strip()+"\n"
    m=re.search(r'^\s*if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', s, flags=re.M)
    if m: s = s[:m.start()] + block + "\n" + s[m.start():]
    else: s = s + "\n\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] injected:", MARK)
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then: curl -I http://127.0.0.1:8910/settings | head"
