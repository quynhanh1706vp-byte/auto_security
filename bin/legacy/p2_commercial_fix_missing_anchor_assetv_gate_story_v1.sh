#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

python3 - <<'PY'
from pathlib import Path
import re, time, sys, py_compile

# ---------- 1) Templates: add #vsp-dashboard-main + unify ?v= ----------
TPL = Path("templates")
MARKA = "VSP_P2_COMM_ANCHOR_ASSETV_V1"
asset_pat = re.compile(r'(\.(?:js|css))\?v=\d+')

def patch_template(p: Path) -> bool:
    s = p.read_text(encoding="utf-8", errors="ignore")
    orig = s
    if MARKA not in s:
        # unify ?v=digits -> ?v={{ asset_v|default('') }}
        s = asset_pat.sub(r"\1?v={{ asset_v|default('') }}", s)

        # ensure #vsp-dashboard-main exists on dashboard-ish templates
        looks_dashboard = ("vsp_dashboard" in s) or ("VSP • Dashboard" in s) or ("/vsp5" in s) or ("vsp_dashboard_luxe_v1.js" in s)
        if looks_dashboard and ('id="vsp-dashboard-main"' not in s):
            # inject right after <body...>
            s = re.sub(r'(<body[^>]*>)',
                       r'\1\n<!-- '+MARKA+' -->\n<div id="vsp-dashboard-main"></div>\n',
                       s, count=1, flags=re.IGNORECASE)

        if s != orig:
            bak = p.with_suffix(p.suffix + f".bak_p2_comm_{time.strftime('%Y%m%d_%H%M%S')}")
            bak.write_text(orig, encoding="utf-8")
            p.write_text(s, encoding="utf-8")
            return True
    return False

patched_tpl = 0
if TPL.exists():
    for p in TPL.rglob("*.html"):
        if patch_template(p):
            patched_tpl += 1
print(f"[OK] templates patched={patched_tpl}")

# ---------- 2) Gate story: normalize wrapper ok/meta/findings -> {meta,findings} ----------
JS = Path("static/js/vsp_dashboard_gate_story_v1.js")
MARKG = "VSP_P2_COMM_GATE_STORY_UNWRAP_V1"

if JS.exists():
    s = JS.read_text(encoding="utf-8", errors="ignore")
    if MARKG not in s:
        # Insert unwrap just before mismatch check line (first occurrence)
        needle = "const keys = Object.keys(fRaw||{});"
        idx = s.find(needle)
        if idx < 0:
            # fallback: older variants use Object.keys(...)
            m = re.search(r"Object\.keys\(fRaw\|\|\{\}\)", s)
            idx = m.start() if m else -1

        if idx >= 0:
            unwrap = f"""
/* {MARKG} */
try {{
  if (fRaw && fRaw.ok === true && Array.isArray(fRaw.findings) && !('meta' in fRaw && 'findings' in fRaw && !('ok' in fRaw))) {{
    fRaw = {{ meta: (fRaw.meta||{{}}), findings: (fRaw.findings||[]) }};
  }}
}} catch(e) {{}}

"""
            s2 = s[:idx] + unwrap + s[idx:]
            bak = JS.with_suffix(".js" + f".bak_p2_comm_{time.strftime('%Y%m%d_%H%M%S')}")
            bak.write_text(s, encoding="utf-8")
            JS.write_text(s2, encoding="utf-8")
            print("[OK] patched gate_story unwrap")
        else:
            print("[WARN] gate_story: cannot locate mismatch check to inject unwrap (skip)")
    else:
        print("[OK] gate_story already unwrapped")
else:
    print("[WARN] gate_story js not found -> skip")

# ---------- 3) quick syntax checks ----------
# node --check handled outside; just ensure templates folder still readable
print("[DONE]")
PY

# node check
if command -v node >/dev/null 2>&1; then
  for f in static/js/vsp_dashboard_luxe_v1.js static/js/vsp_dashboard_gate_story_v1.js; do
    [ -f "$f" ] || continue
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 2; }
  done
fi

# restart service best-effort
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  echo "[OK] restart attempted: $SVC"
fi

echo
echo "[NEXT] Verify (commercial check):"
echo "  1) Ctrl+Shift+R /vsp5 -> no 'missing #vsp-dashboard-main' + dashboard not stuck LOADING"
echo "  2) /vsp5 asset ?v should match other tabs (or become ?v={{asset_v}} everywhere)"
echo "  3) no 'Findings payload mismatch' banner"
