#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
TPL="templates/vsp_dashboard_2025.html"
MARK="VSP_TOPNAV_5TABS_P0_V1"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 3; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}"
echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")
MARK="VSP_TOPNAV_5TABS_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

nav = f"""
<!-- {MARK} -->
<div style="position:sticky;top:0;z-index:9999;background:#0b1220;border-bottom:1px solid rgba(255,255,255,.08);">
  <div style="max-width:1280px;margin:0 auto;padding:10px 14px;display:flex;gap:10px;align-items:center;">
    <div style="font-weight:700;letter-spacing:.3px;color:#dbe7ff;">VSP 2025</div>
    <div style="flex:1"></div>
    <a href="/vsp4" style="color:#cfe0ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);">Dashboard</a>
    <a href="/vsp5" style="color:#cfe0ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);">Runs &amp; Reports</a>
    <a href="/vsp5" style="color:#cfe0ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);">Settings</a>
    <a href="/vsp5" style="color:#cfe0ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);">Data Source</a>
    <a href="/vsp5" style="color:#cfe0ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);">Rule Overrides</a>
  </div>
</div>
<!-- /{MARK} -->
""".strip()+"\n"

# inject right after <body ...>
m = re.search(r"<body[^>]*>", s, flags=re.I)
if not m:
    raise SystemExit("[ERR] cannot find <body> tag to inject nav")
s = s[:m.end()] + "\n" + nav + s[m.end():]
tpl.write_text(s, encoding="utf-8")
print("[OK] injected top nav")
PY
echo "[OK] patched $TPL"
