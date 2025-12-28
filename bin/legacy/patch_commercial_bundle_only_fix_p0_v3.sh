#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== COMMERCIAL BUNDLE-ONLY FIX (P0 v3) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

BUNDLE="static/js/vsp_bundle_commercial_v1.js"
LOADER="static/js/vsp_ui_loader_route_v1.js"
ROUTER="static/js/vsp_tabs_hash_router_v1.js"

[ -f "$BUNDLE" ] || { echo "[ERR] missing bundle: $BUNDLE"; exit 2; }

# (0) Ensure bundle has global flag + drilldown alias + log-once guard (idempotent)
python3 - <<'PY'
from pathlib import Path
import datetime, re

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Prologue (idempotent)
if "/* VSP_BUNDLE_COMMERCIAL_V1_PROLOGUE */" not in s:
  pro = []
  pro.append("/* VSP_BUNDLE_COMMERCIAL_V1_PROLOGUE */")
  pro.append(f"/* injected_at: {datetime.datetime.now().isoformat()} */")
  pro.append("(function(){")
  pro.append("  'use strict';")
  pro.append("  try{ window.__VSP_BUNDLE_COMMERCIAL_V1 = true; }catch(_){ }")
  pro.append("  if (!window.VSP_DRILLDOWN) {")
  pro.append("    window.VSP_DRILLDOWN = function(intent){")
  pro.append("      try{")
  pro.append("        if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);")
  pro.append("        if (typeof window.__VSP_DD_ART_CALL__ === 'function') return window.__VSP_DD_ART_CALL__(intent);")
  pro.append("        if (typeof window.__VSP_DRILLDOWN__ === 'function') return window.__VSP_DRILLDOWN__(intent);")
  pro.append("        console.warn('[VSP][DRILLDOWN] no impl', intent);")
  pro.append("        return null;")
  pro.append("      }catch(e){ try{console.warn('[VSP][DRILLDOWN] err', e);}catch(_e){} return null; }")
  pro.append("    };")
  pro.append("  }")
  pro.append("  var alias = function(){ return window.VSP_DRILLDOWN.apply(window, arguments); };")
  pro.append("  try{")
  pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = alias;")
  pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = alias;")
  pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS = alias;")
  pro.append("  }catch(_){ }")
  pro.append("})();\n")
  s = "\n".join(pro) + s
  p.write_text(s, encoding="utf-8")
  print("[OK] prologue+aliases added")
else:
  print("[OK] prologue already present")

# Log spam guard: only keep first occurrence of "drilldown real impl accepted"
needle = "drilldown real impl accepted"
if needle in s and "__VSP_DD_ACCEPTED_ONCE" not in s:
  lines = s.splitlines(True)
  out = []
  for line in lines:
    if "console.log" in line and needle in line:
      out.append("try{ if(!window.__VSP_DD_ACCEPTED_ONCE){ window.__VSP_DD_ACCEPTED_ONCE=1; " + line.strip() + " } }catch(_){ }\n")
    else:
      out.append(line)
  p.write_text("".join(out), encoding="utf-8")
  print("[OK] drilldown accepted log guarded (once)")
else:
  print("[OK] log guard already present or needle not found")
PY

# (1) Stub loader/router to stop duplicate init (safe even if still loaded)
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
})();
EOF
    echo "[OK] stubbed $F"
  else
    echo "[WARN] missing $F (skip)"
  fi
}
stub "$LOADER" "VSP_UI_LOADER_ROUTE"
stub "$ROUTER" "VSP_TABS_HASH_ROUTER"

# (2) Patch ALL top-level templates (contain <html and </body>) -> remove all /static/js/vsp_*.js except bundle; inject bundle tag once
python3 - <<'PY'
from pathlib import Path
import re, datetime

tpl_dir = Path("templates")
if not tpl_dir.exists():
  print("[WARN] templates/ not found -> skip")
  raise SystemExit(0)

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v1.js?v={{ asset_v }}"></script>'

script_re = re.compile(r'(?is)\s*<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>\s*')
def is_vsp_script(src: str) -> bool:
  if "vsp_bundle_commercial_v1.js" in src:
    return False
  return ("/static/js/vsp_" in src) or ("static/js/vsp_" in src)

patched = 0
for tp in sorted(tpl_dir.rglob("*.html")):
  txt = tp.read_text(encoding="utf-8", errors="replace")

  # Only patch top-level documents to avoid double-including bundle via inheritance/partials
  low = txt.lower()
  if ("<html" not in low) or ("</body" not in low):
    continue

  removed = [0]
  def repl(m):
    src = (m.group(1) or "").strip()
    if is_vsp_script(src):
      removed[0] += 1
      return "\n"
    # also remove any existing bundle tag (we will re-inject exactly one)
    if "vsp_bundle_commercial_v1.js" in src:
      removed[0] += 1
      return "\n"
    return m.group(0)

  new = script_re.sub(repl, txt)

  # inject bundle exactly once before </body>
  if re.search(r"(?is)</body\s*>", new):
    new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
  else:
    new += "\n" + bundle_tag + "\n"

  if new != txt:
    bak = tp.with_suffix(tp.suffix + f".bak_bundleonly_{TS}")
    bak.write_text(txt, encoding="utf-8")
    tp.write_text(new, encoding="utf-8")
    print(f"[OK] patched {tp.as_posix()} removed_scripts={removed[0]}")
    patched += 1

print("[DONE] templates_patched=", patched)
PY

echo "== node --check bundle =="
node --check "$BUNDLE" && echo "[OK] bundle JS syntax OK"

echo "== DONE (P0 v3) =="
echo "[NEXT] restart 8910 + hard refresh Ctrl+Shift+R"
