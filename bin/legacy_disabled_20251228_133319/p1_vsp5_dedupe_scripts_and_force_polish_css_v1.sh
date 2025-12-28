#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TPL="templates/vsp_dashboard_2025.html"
CSS="static/css/vsp_dashboard_polish_v1.css"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_dedupe_${TS}"
echo "[BACKUP] ${TPL}.bak_dedupe_${TS}"

mkdir -p "$(dirname "$CSS")"
cat > "$CSS" <<'CSS'
/* VSP_DASHBOARD_POLISH_V1 (force-visible) */
:root{
  --vsp-accent: rgba(56,189,248,.85);
  --vsp-accent2: rgba(168,85,247,.70);
}
body{
  background:
    radial-gradient(900px 520px at 20% 18%, rgba(56,189,248,.08), transparent 60%),
    radial-gradient(900px 520px at 82% 12%, rgba(168,85,247,.06), transparent 60%),
    #070e1a !important;
}
.vsp5nav{
  backdrop-filter: blur(10px);
  background: rgba(0,0,0,.30) !important;
  border-bottom: 1px solid rgba(255,255,255,.10) !important;
}
.vsp5nav a{
  border-color: rgba(56,189,248,.22) !important;
  box-shadow: 0 0 0 1px rgba(168,85,247,.10) inset;
}
.vsp5nav a:hover{
  background: rgba(56,189,248,.08) !important;
}
#vsp5_root{
  background-image:
    linear-gradient(to bottom, rgba(255,255,255,.02), transparent 260px);
}
CSS
echo "[OK] wrote $CSS"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

# 1) ensure polish css is linked in <head>
css_link = r'<link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css?v=VSP_POLISH_TS"/>'
if "vsp_dashboard_polish_v1.css" not in s:
    s = re.sub(r'(</title>\s*)', r'\1\n  ' + css_link + '\n', s, count=1, flags=re.I)
else:
    # bump version query if already present
    s = re.sub(r'vsp_dashboard_polish_v1\.css\?v=[0-9A-Za-z_]+', 'vsp_dashboard_polish_v1.css?v=VSP_POLISH_TS', s)

s = s.replace("VSP_POLISH_TS", "1766369999")  # stable cache-bust token (ok)

# 2) dedupe gate_story script includes (keep first, remove the rest)
pat = re.compile(r'<script[^>]+src=["\']/static/js/vsp_dashboard_gate_story_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', re.I)
matches = list(pat.finditer(s))
if len(matches) > 1:
    # keep first, remove others
    first = matches[0].group(0)
    s2 = first + "\n" + pat.sub("", s[matches[0].end():])
    s = s[:matches[0].start()] + s2
    print("[OK] deduped vsp_dashboard_gate_story_v1.js:", len(matches), "-> 1")
else:
    print("[OK] gate_story script count:", len(matches))

# 3) optional: add defer to heavy scripts (safe)
def add_defer(m):
    tag = m.group(0)
    if " defer" in tag.lower():
        return tag
    return tag.replace("<script ", "<script defer ", 1)

s = re.sub(r'<script\s+src=["\']/static/js/[^"\']+["\']\s*></script>', add_defer, s, flags=re.I)

tpl.write_text(s, encoding="utf-8")
print("[OK] patched template:", tpl)
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
