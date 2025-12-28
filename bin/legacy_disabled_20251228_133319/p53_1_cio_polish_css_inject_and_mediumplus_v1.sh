#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p53_1_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need grep; need python3; need sed; need awk; need curl; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p53_1_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

# 1) Fix Medium* -> Medium+
grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' 'Medium\*' static/js > "$EVID/medium_star_hits.txt" 2>/dev/null || true
if [ -s "$EVID/medium_star_hits.txt" ]; then
  while IFS=: read -r f ln rest; do
    [ -f "$f" ] || continue
    cp -f "$f" "$f.bak_p53_1_${TS}"
    sed -i 's/Medium\*/Medium+/g' "$f"
  done < <(cut -d: -f1-2 "$EVID/medium_star_hits.txt" | uniq)
  echo "[OK] patched Medium* -> Medium+"
else
  echo "[OK] no Medium* found"
fi

# 2) Write a small global polish CSS
CSS="static/css/vsp_polish_p53_v1.css"
mkdir -p static/css
cp -f "$CSS" "$CSS.bak_p53_1_${TS}" 2>/dev/null || true
cat > "$CSS" <<'CSS'
/* VSP P53 polish (safe overlay) */
:root{
  --vsp-radius: 14px;
  --vsp-gap: 14px;
}
html, body{
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
body{
  line-height: 1.45;
}
a, button{
  transition: transform .08s ease, filter .12s ease, opacity .12s ease;
}
button:active{
  transform: translateY(0.5px);
}
.vsp-card, .card, .panel, .box, .kpi-card{
  border-radius: var(--vsp-radius) !important;
}
table{
  border-collapse: separate;
  border-spacing: 0;
}
thead th{
  position: sticky;
  top: 0;
  z-index: 1;
}
input, select, textarea{
  border-radius: 10px !important;
}
CSS
echo "[OK] wrote $CSS"

# 3) Inject CSS via common JS loaded on all tabs (best effort)
inject_js=""
for cand in static/js/vsp_bundle_tabs5_v1.js static/js/vsp_bundle_tabs5_v2.js static/js/vsp_bundle_tabs5.js; do
  if [ -f "$cand" ]; then inject_js="$cand"; break; fi
done
if [ -n "$inject_js" ]; then
  cp -f "$inject_js" "$inject_js.bak_p53_1_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("$inject_js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P53_1_CSS_INJECT_V1"
if MARK in s:
    print("[OK] already injected")
else:
    ins = f"""// {MARK}
(function(){{
  try {{
    if (window.__vspP53Css) return;
    window.__vspP53Css = 1;
    var id="vsp_p53_css";
    if (!document.getElementById(id)) {{
      var l=document.createElement("link");
      l.id=id; l.rel="stylesheet";
      l.href="/static/css/vsp_polish_p53_v1.css?v="+Date.now();
      (document.head||document.documentElement).appendChild(l);
    }}
  }} catch(e) {{}}
}})();
"""
    s = ins + "\n" + s
    p.write_text(s, encoding="utf-8")
    print("[OK] injected into", p)
PY
  echo "[OK] injected CSS loader into $inject_js"
else
  echo "[WARN] could not find common bundle JS to inject CSS"
fi

sudo systemctl restart "$SVC" || true
sleep 1.1
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 8 "$BASE/vsp5" || true)"
echo "vsp5_http=$code" | tee "$EVID/health.txt" >/dev/null

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P53.1 APPLIED"
