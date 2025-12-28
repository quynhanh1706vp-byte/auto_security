#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head

files=(
  "templates/vsp_data_source_2025.html"
  "templates/vsp_settings_2025.html"
  "templates/vsp_rule_overrides_2025.html"
)

echo "== [1] Backup templates =="
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_nonvsp5fix_${TS}"
  echo "[BACKUP] ${f}.bak_nonvsp5fix_${TS}"
done

echo "== [2] Patch: remove luxe script from non-/vsp5 tabs + fix broken quotes/escapes =="
python3 - <<'PY'
from pathlib import Path
import re, time

targets = [
  Path("templates/vsp_data_source_2025.html"),
  Path("templates/vsp_settings_2025.html"),
  Path("templates/vsp_rule_overrides_2025.html"),
]

def patch(s: str) -> tuple[str,int]:
    changes=0

    # 1) Remove any block that mentions vsp_dashboard_luxe_v1.js (even if wrapped by Jinja/raw)
    before=s
    # remove Jinja-wrapped block
    s = re.sub(
        r'(?s)\{\%\s*if\s+request\.path\s*==\s*"/vsp5"\s*\%\}\s*.*?vsp_dashboard_luxe_v1\.js.*?\{\%\s*endif\s*\%\}\s*',
        '',
        s
    )
    if s!=before: changes+=1

    # remove any remaining single script tag with luxe
    before=s
    s = re.sub(r'(?im)^\s*<script[^>]*vsp_dashboard_luxe_v1\.js[^>]*>\s*</script>\s*$', '', s)
    if s!=before: changes+=1

    # also remove raw leftover jinja lines if they exist alone
    before=s
    s = re.sub(r'(?im)^\s*\{\%\s*if\s+request\.path\s*==\s*"/vsp5"\s*\%\}\s*$', '', s)
    s = re.sub(r'(?im)^\s*\{\%\s*endif\s*\%\}\s*$', '', s)
    if s!=before: changes+=1

    # 2) Fix escaped quotes in ids: id=\"x\" => id="x"
    before=s
    s = s.replace('\\"', '"')
    if s!=before: changes+=1

    # 3) Fix broken <script src=...> quoting
    #    src=/static/js/foo.js"  -> src="/static/js/foo.js"
    before=s
    s = re.sub(r'(<script\s+[^>]*src)=/static/js/([^"\s>]+)"', r'\1="/static/js/\2"', s)
    s = re.sub(r'(<script\s+[^>]*src)=/static/js/([^"\s>]+)(?=[\s>])', r'\1="/static/js/\2"', s)
    if s!=before: changes+=1

    # 4) Ensure any <script src=/static/js/...> becomes quoted (generic)
    before=s
    s = re.sub(r'(<script\s+[^>]*src)=(/static/js/[^"\s>]+)', r'\1="\2"', s)
    if s!=before: changes+=1

    # clean double quotes like src=""//static...
    before=s
    s = s.replace('src=""', 'src="')
    if s!=before: changes+=1

    return s, changes

for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    s2, ch = patch(s)
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] {p}: changes={ch}")
PY

echo
echo "== [3] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo
echo "== [4] Verify: /data_source must NOT contain luxe + must have valid script tags =="
if curl -fsS --max-time 3 "$BASE/data_source" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 1; then
  echo "[ERR] still found luxe in /data_source"
  exit 4
else
  echo "[OK] no luxe in /data_source"
fi

# check the previously broken lazy script tag now quoted
if curl -fsS --max-time 3 "$BASE/data_source" | grep -n 'vsp_data_source_lazy_v1\.js' | head -n 1; then
  echo "[OK] data_source_lazy present"
else
  echo "[WARN] data_source_lazy tag not found"
fi

echo
echo "[DONE] Now Ctrl+Shift+R on /data_source, /settings, /rule_overrides."
