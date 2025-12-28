#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_vsp4slash_drill_${TS}" && echo "[BACKUP] $F.bak_vsp4slash_drill_${TS}"

mkdir -p static/js

# (1) write drilldown stub that guarantees function
cat > static/js/vsp_drilldown_stub_safe_v1.js <<'JS'
/* VSP_DRILLDOWN_STUB_SAFE_V1: guarantee drilldown symbol is a function */
(function(){
  'use strict';
  function stub(){
    try{ console.info("[VSP][DD] stub invoked"); }catch(_){}
    return { open:function(){}, show:function(){}, close:function(){}, destroy:function(){} };
  }
  try{
    // keep real impl if provided later
    if (typeof window.__vsp_dd_real !== "function") window.__vsp_dd_real = null;
    Object.defineProperty(window, "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2", {
      configurable: false,
      enumerable: true,
      get: function(){ return (typeof window.__vsp_dd_real === "function") ? window.__vsp_dd_real : stub; },
      set: function(v){
        if (typeof v === "function") {
          window.__vsp_dd_real = v;
          try{ console.info("[VSP][DD] accepted real impl"); }catch(_){}
        } else {
          try{ console.warn("[VSP][DD] blocked overwrite (non-function)", v); }catch(_){}
        }
      }
    });
  }catch(e){
    // fallback if defineProperty fails
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = stub;
    }
  }
})();
JS

node --check static/js/vsp_drilldown_stub_safe_v1.js >/dev/null && echo "[OK] node --check drilldown stub"

# (2) patch vsp_demo_app.py:
#   - redirect /vsp4/ -> /vsp4
#   - inject drilldown stub into /vsp4 HTML head (same injector you already have)
python3 - <<'PY'
from pathlib import Path
import re, time

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...)")
appvar=m.group(1)

stamp = str(int(time.time()))

# (a) add /vsp4/ -> /vsp4 redirect (before_request) if missing
if "VSP_VSP4_SLASH_REDIRECT_V1" not in s:
    s += f"""

# ================================
# VSP_VSP4_SLASH_REDIRECT_V1
# ================================
@{appvar}.before_request
def __vsp_redirect_vsp4_slash_v1():
  try:
    if request.path == "/vsp4/":
      return _vsp_redirect("/vsp4", code=301) if "_vsp_redirect" in globals() and _vsp_redirect else redirect("/vsp4", code=301)
  except Exception:
    pass
  return None
"""

# (b) extend existing injector V3 to also inject drilldown stub into <head>
# find our V3 injector function body
if "VSP_VSP4_INJECT_AFTER_REQUEST_V3" in s and "vsp_drilldown_stub_safe_v1.js" not in s:
    # insert a new block right before loader block inside _vsp__inject_tags_v3
    pat = r"(def _vsp__inject_tags_v3\(html: str\) -> str:\s*[\s\S]*?# loader\+features before </body>)"
    mm = re.search(pat, s)
    if mm:
        # safer: do targeted insertion before the loader block comment
        insert = (
            "    # drilldown stub into <head> (must be function)\n"
            f"    if 'vsp_drilldown_stub_safe_v1.js' not in html:\n"
            f"      tag2 = '<script src=\"/static/js/vsp_drilldown_stub_safe_v1.js?v={stamp}\"></script>'\n"
            "      mm2 = _vsp_re.search(r'<head[^>]*>', html, flags=_vsp_re.I)\n"
            "      if mm2:\n"
            "        j = mm2.end()\n"
            "        html = html[:j] + '\\n  ' + tag2 + '\\n' + html[j:]\n"
            "      else:\n"
            "        html = tag2 + '\\n' + html\n\n"
        )
        # place it just before the loader comment
        s = s.replace("# loader+features before </body>", insert + "# loader+features before </body>", 1)

p.write_text(s, encoding="utf-8")
print("[OK] patched", p, "appvar=", appvar)
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK: vsp_demo_app.py"

echo "== restart 8910 (NO restore) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_no_restore_v1.sh

echo "== verify routes =="
curl -sSI http://127.0.0.1:8910/vsp4/ | head -n 8 || true
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_drilldown_stub_safe_v1.js" || echo "[WARN] drilldown stub not injected (will still run if cached)"
echo "[NEXT] mở URL này (đúng): http://127.0.0.1:8910/vsp4/#dashboard"
