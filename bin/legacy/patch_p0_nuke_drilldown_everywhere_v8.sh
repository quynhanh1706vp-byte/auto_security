#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

# Find ALL occurrences (js + html) excluding backups
mapfile -t FILES < <(
  grep -RIl \
    --exclude='*.bak_*' --exclude='*.bak' --exclude-dir='out*' --exclude-dir='out_ci*' \
    --include='*.js' --include='*.html' \
    'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2' \
    static templates 2>/dev/null || true
)

echo "== HIT FILES =="
printf '%s\n' "${FILES[@]:-}" || true
[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no occurrences found under static/templates"; exit 2; }

for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "$F.bak_p0_v8_${TS}"
  echo "[BACKUP] $F.bak_p0_v8_${TS}"

  python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

f = Path(sys.argv[1])
s = f.read_text(encoding="utf-8", errors="ignore")
orig = s

# Nuclear-safe callsite replacement (never throws)
pat = re.compile(r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(")
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('
s, n = pat.subn(repl, s)

# Add tiny stub header for JS (best-effort, harmless)
if f.suffix == ".js" and "P0_DRILLDOWN_NUKE_V8" not in s:
    header = """/* P0_DRILLDOWN_NUKE_V8 */
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
"""
    s = header + "\n" + s

if s != orig:
    f.write_text(s, encoding="utf-8")
    print("[OK] patched", f, "callsites=", n)
else:
    print("[OK] no change", f, "callsites=", n)
PY

  if [[ "$F" == *.js ]]; then
    node --check "$F" >/dev/null && echo "[OK] node --check $F"
  fi
done

# Cache-bust ALL /static/js/*.js src in templates to TS (force reload)
mapfile -t TPLS < <(grep -RIl 'src="/static/js/.*\.js' templates 2>/dev/null || true)
for T in "${TPLS[@]:-}"; do
  [ -f "$T" ] || continue
  cp -f "$T" "$T.bak_p0_v8_${TS}"
  echo "[BACKUP] $T.bak_p0_v8_${TS}"

  python3 - "$T" "$TS" <<'PY'
import sys, re
from pathlib import Path

t = Path(sys.argv[1]); TS = sys.argv[2]
s = t.read_text(encoding="utf-8", errors="ignore")

def bump(m):
    url = m.group(1)
    if "?" in url:
        url2 = re.sub(r"([?&]v=)[0-9_]+", r"\1"+TS, url)
        if url2 == url:
            sep = "&"
            url2 = url + sep + "v=" + TS
        return f'src="{url2}"'
    return f'src="{url}?v={TS}"'

s2 = re.sub(r'src="(/static/js/[^"]+\.js(?:\?[^"]*)?)"', bump, s)
t.write_text(s2, encoding="utf-8")
print("[OK] cachebusted", t)
PY
done

echo "== REMAIN raw callsites (must be 0) =="
grep -RIn --exclude='*.bak_*' --include='*.js' --include='*.html' \
  'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(' static templates || echo "[OK] none"

echo "[DONE] V8"
