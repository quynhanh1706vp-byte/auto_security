#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH VSP4 TEMPLATE -> BUNDLE ONLY (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# (1) Detect template used by /vsp4
TPL="$(python3 - <<'PY'
import re
from pathlib import Path

txt = Path("vsp_demo_app.py").read_text(encoding="utf-8", errors="replace")

# find route '/vsp4' (single/double quotes)
m = re.search(r'@app\.route\(\s*[\'"]\/vsp4[\'"][^)]*\)\s*[\s\S]*?render_template\(\s*[\'"]([^\'"]+)[\'"]', txt)
if not m:
  # fallback: blueprint style: route("/vsp4")
  m = re.search(r'route\(\s*[\'"]\/vsp4[\'"][^)]*\)\s*[\s\S]*?render_template\(\s*[\'"]([^\'"]+)[\'"]', txt)
if m:
  print(m.group(1))
else:
  print("")
PY
)"

if [ -z "${TPL:-}" ]; then
  echo "[ERR] cannot detect template for /vsp4 in $APP"
  echo "[HINT] grep it manually: grep -n \"vsp4\\|render_template\" -n $APP | head"
  exit 3
fi

echo "[OK] /vsp4 template = $TPL"
TP="templates/$TPL"
[ -f "$TP" ] || { echo "[ERR] template file not found: $TP"; exit 4; }

# (2) Patch that template -> keep ONLY bundle tag (remove all /static/js/vsp_*.js except bundle)
python3 - <<'PY'
from pathlib import Path
import re, datetime

tpl_path = Path("templates") / Path(r"""$TPL""")
txt = tpl_path.read_text(encoding="utf-8", errors="replace")

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bak = tpl_path.with_suffix(tpl_path.suffix + f".bak_bundle_only_{TS}")
bak.write_text(txt, encoding="utf-8")

bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v1.js?v={{ asset_v }}"></script>'

# remove script tags that load /static/js/vsp_*.js (except bundle)
script_re = re.compile(r'(?is)\s*<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>\s*')
removed = 0

def repl(m):
  global removed
  src = (m.group(1) or "").strip()
  # remove any vsp_ js except the bundle
  if ("vsp_bundle_commercial_v1.js" not in src) and ("/static/js/vsp_" in src or "static/js/vsp_" in src):
    removed += 1
    return "\n"
  return m.group(0)

new = script_re.sub(repl, txt)

# ensure bundle exists exactly once
new = re.sub(r'(?is)\s*<script\b[^>]*vsp_bundle_commercial_v1\.js[^>]*>\s*</script\s*>\s*', "\n", new)
if re.search(r"(?is)</body\s*>", new):
  new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
else:
  new = new + "\n" + bundle_tag + "\n"

tpl_path.write_text(new, encoding="utf-8")
print(f"[OK] patched {tpl_path.as_posix()} removed_vsp_scripts={removed} + inserted bundle_tag(1x)")
PY

# (3) quick grep to confirm template has no loader route
echo "== VERIFY no vsp_ui_loader_route_v1.js in $TP =="
if grep -n "vsp_ui_loader_route_v1\.js" -n "$TP" >/dev/null 2>&1; then
  echo "[ERR] loader still referenced in template!"
  grep -n "vsp_ui_loader_route_v1\.js" -n "$TP" | head
  exit 5
fi
echo "[OK] loader not referenced in template"

echo "== DONE =="
echo "[NEXT] restart 8910 + rerun selfcheck"
