#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== COMMERCIAL BUNDLE-ONLY FIX (P0 v2) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

APP="vsp_demo_app.py"
BUNDLE="static/js/vsp_bundle_commercial_v1.js"
LOADER="static/js/vsp_ui_loader_route_v1.js"
ROUTER="static/js/vsp_tabs_hash_router_v1.js"

[ -f "$BUNDLE" ] || { echo "[ERR] missing bundle: $BUNDLE"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# (1) Detect template used by /vsp4 and patch it to load ONLY the bundle
TPL="$(python3 - <<'PY'
import re
from pathlib import Path
txt = Path("vsp_demo_app.py").read_text(encoding="utf-8", errors="replace")

m = re.search(r'@app\.route\(\s*[\'"]\/vsp4[\'"][^)]*\)\s*[\s\S]*?render_template\(\s*[\'"]([^\'"]+)[\'"]', txt)
if not m:
  m = re.search(r'route\(\s*[\'"]\/vsp4[\'"][^)]*\)\s*[\s\S]*?render_template\(\s*[\'"]([^\'"]+)[\'"]', txt)
print(m.group(1) if m else "")
PY
)"

if [ -z "${TPL:-}" ]; then
  echo "[ERR] cannot detect template for /vsp4 in $APP"
  echo "grep -n \"vsp4\\|render_template\" -n $APP | head -n 50"
  exit 3
fi

TP="templates/$TPL"
[ -f "$TP" ] || { echo "[ERR] template not found: $TP"; exit 4; }
echo "[OK] /vsp4 template = $TP"

python3 - <<'PY'
from pathlib import Path
import re, datetime

tp = Path(r"""templates/""" + r"""'"$TPL"'" """.strip("'"))
txt = tp.read_text(encoding="utf-8", errors="replace")
TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

bak = tp.with_suffix(tp.suffix + f".bak_bundle_only_{TS}")
bak.write_text(txt, encoding="utf-8")

bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v1.js?v={{ asset_v }}"></script>'

# Remove ANY script tag that loads /static/js/vsp_*.js (except the bundle)
script_re = re.compile(r'(?is)\s*<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>\s*')

removed = 0
def repl(m):
  global removed
  src = (m.group(1) or "").strip()
  if "vsp_bundle_commercial_v1.js" in src:
    removed += 1
    return "\n"
  if "/static/js/vsp_" in src or "static/js/vsp_" in src:
    removed += 1
    return "\n"
  return m.group(0)

new = script_re.sub(repl, txt)

# Ensure exactly one bundle tag
new = re.sub(r'(?is)\s*<script\b[^>]*vsp_bundle_commercial_v1\.js[^>]*>\s*</script\s*>\s*', "\n", new)
if re.search(r"(?is)</body\s*>", new):
  new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
else:
  new += "\n" + bundle_tag + "\n"

tp.write_text(new, encoding="utf-8")
print(f"[OK] patched {tp.as_posix()} removed_script_tags={removed} -> bundle-only")
PY

# (2) Hard-disable loader/router files (replace with stubs) to prevent duplicate init
stub() {
  local F="$1"; local NAME="$2"
  if [ -f "$F" ]; then
    cp -f "$F" "$F.bak_stub_${TS}"
    cat > "$F" <<EOF
/* ${NAME} STUB (COMMERCIAL BUNDLE-ONLY) */
(function(){
  'use strict';
  try{
    if (window && window.__VSP_BUNDLE_COMMERCIAL_V1){
      // commercial: NO dynamic route loading / standalone router
      return;
    }
  }catch(_){}
  // non-commercial fallback: do nothing (safe)
})();
EOF
    echo "[OK] stubbed $F"
  fi
}

stub "$LOADER" "VSP_UI_LOADER_ROUTE"
stub "$ROUTER" "VSP_TABS_HASH_ROUTER"

# (3) Stop spam log inside bundle: "drilldown real impl accepted" only once
python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

if "__VSP_DD_ACCEPTED_ONCE" in s:
  print("[OK] bundle already has dd log guard (skip)")
  raise SystemExit(0)

needle = "drilldown real impl accepted"
if needle not in s:
  print("[WARN] cannot find log text in bundle (skip log guard)")
  raise SystemExit(0)

bak = p.with_suffix(p.suffix + f".bak_ddlog_{TS}")
bak.write_text(s, encoding="utf-8")

# wrap any console.log that contains the needle
def guard_line(line: str) -> str:
  if "console.log" in line and needle in line:
    return "try{ if(!window.__VSP_DD_ACCEPTED_ONCE){ window.__VSP_DD_ACCEPTED_ONCE=1; " + line.strip() + " } }catch(_){ }\n"
  return line

lines = s.splitlines(True)
out = [guard_line(l) for l in lines]
p.write_text("".join(out), encoding="utf-8")
print("[OK] guarded drilldown accepted log (once)")
PY

echo "== node --check bundle =="
node --check "$BUNDLE" && echo "[OK] bundle JS syntax OK"

echo "== DONE =="
echo "[NEXT] restart 8910, hard refresh Ctrl+Shift+R, open /vsp4#dashboard and /vsp4#runs"
echo "[EXPECT] console spam stops; scripts loaded should be 1 (bundle-only)"
