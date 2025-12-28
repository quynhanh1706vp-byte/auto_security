#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

# 1) Patch ALL JS that contains the drilldown symbol call
FILES="$(grep -RIl --include='*.js' 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2' static/js || true)"
[ -n "$FILES" ] || { echo "[ERR] no JS contains VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 under static/js"; exit 2; }

for F in $FILES; do
  echo "== PATCH DRILLDOWN: $F =="
  cp -f "$F" "$F.bak_p0_v6_${TS}"
  echo "[BACKUP] $F.bak_p0_v6_${TS}"

  TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

# (A) Make EVERY callsite safe (cannot throw "is not a function")
pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP_DASH][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('
s2, n = re.subn(pat, repl, s)

# (B) Also ensure window symbol is callable early (best-effort)
MARK = "/* P0_DRILLDOWN_STUB_V6 */"
if MARK not in s2:
    header = MARK + r'''
(function(){
  try{
    if (typeof window === "undefined") return;
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.info("[VSP_DASH][P0] drilldown window stub called"); }catch(_){}
        return {open(){},show(){},close(){},destroy(){}};
      };
    }
  }catch(_){}
})();
'''
    s2 = header + "\n" + s2

p.write_text(s2, encoding="utf-8")
print("[OK] callsites_replaced=", n, "file=", p)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

# 2) Cache-bust dashboard script tags so browser MUST reload (avoid 304)
TPLS="$(grep -RIl 'static/js/vsp_dashboard_.*\.js' templates 2>/dev/null || true)"
if [ -n "$TPLS" ]; then
  for T in $TPLS; do
    cp -f "$T" "$T.bak_p0_v6_${TS}"
    echo "[BACKUP] $T.bak_p0_v6_${TS}"
    TARGET_TPL="$T" TS="$TS" python3 - <<'PY'
import os, re
from pathlib import Path

t = Path(os.environ["TARGET_TPL"])
TS = os.environ["TS"]
s = t.read_text(encoding="utf-8", errors="ignore")

def bump(m):
    url = m.group(1)
    if "?" in url:
        # already has query; keep, but update v= if present
        url2 = re.sub(r"([?&]v=)[0-9_]+", r"\1"+TS, url)
        if url2 == url:
            # add v= if missing
            sep = "&" if "?" in url else "?"
            url2 = url + sep + "v=" + TS
        return 'src="' + url2 + '"'
    else:
        return 'src="' + url + '?v=' + TS + '"'

s2 = re.sub(r'src="(/static/js/vsp_dashboard_[^"]+\.js(?:\?[^"]*)?)"', bump, s)
t.write_text(s2, encoding="utf-8")
print("[OK] cachebusted dashboard js in", t)
PY
  done
else
  echo "[WARN] no templates contain vsp_dashboard_*.js src"
fi

echo "[DONE] P0 drilldown search+patch + cachebust v6"
