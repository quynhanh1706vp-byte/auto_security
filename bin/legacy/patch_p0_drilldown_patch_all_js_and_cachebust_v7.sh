#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

python3 - <<'PY'
import re
from pathlib import Path

TS = Path(".").resolve().name  # not used, but keep runtime simple

# ---------- Patch ALL static/js/*.js ----------
root = Path("static/js")
pat_call = re.compile(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(")
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('

stub_header = r'''/* P0_DRILLDOWN_PATCH_ALL_V7 */
(function(){
  try{
    if (typeof window === "undefined") return;
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.info("[VSP][P0] drilldown window stub called"); }catch(_){}
        return {open(){},show(){},close(){},destroy(){}};
      };
    }
  }catch(_){}
})();
'''

changed_files = []
for f in sorted(root.rglob("*.js")):
    s = f.read_text(encoding="utf-8", errors="ignore")
    orig = s
    n = len(pat_call.findall(s))
    if n:
        # replace callsites (nuclear)
        s, nn = pat_call.subn(repl, s)
        # ensure header only once
        if "P0_DRILLDOWN_PATCH_ALL_V7" not in s:
            s = stub_header + "\n" + s
        if s != orig:
            f.write_text(s, encoding="utf-8")
            changed_files.append((str(f), nn))

print("[OK] js_files_patched =", len(changed_files))
for f, nn in changed_files[:30]:
    print(" -", f, "callsites=", nn)
if len(changed_files) > 30:
    print(" - ... more:", len(changed_files)-30)

# ---------- Cache-bust ALL /static/js/*.js in templates ----------
tpl_root = Path("templates")
tpl_changed = 0
if tpl_root.exists():
    for t in sorted(tpl_root.rglob("*.html")):
        s = t.read_text(encoding="utf-8", errors="ignore")
        orig = s

        def bump(m):
            url = m.group(1)
            q = m.group(2) or ""
            if "v=" in q:
                q2 = re.sub(r"([?&]v=)[0-9_]+", r"\1" + Path.cwd().name, q)  # simple unique
                return f'src="{url}{q2}"'
            if q:
                return f'src="{url}{q}&v={Path.cwd().name}"'
            return f'src="{url}?v={Path.cwd().name}"'

        s = re.sub(r'src="(/static/js/[^"]+\.js)(\?[^"]*)?"', bump, s)
        if s != orig:
            t.write_text(s, encoding="utf-8")
            tpl_changed += 1

print("[OK] templates_cachebusted =", tpl_changed)
PY

# quick sanity: list any remaining raw callsites
echo "== REMAIN raw callsites (should be 0) =="
grep -RIn --include='*.js' 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(' static/js || echo "[OK] none"

echo "[DONE] V7 all-js patch + template cachebust"
