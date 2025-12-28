#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

FILES=()
[ -f static/js/vsp_p1_page_boot_v1.js ] && FILES+=(static/js/vsp_p1_page_boot_v1.js)
[ -f static/js/vsp_rid_state_v1.js ] && FILES+=(static/js/vsp_rid_state_v1.js)
[ -f static/js/vsp_dashboard_gate_story_v1.js ] && FILES+=(static/js/vsp_dashboard_gate_story_v1.js)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] cannot find target JS files under static/js"; exit 2; }

for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_gate_root_${TS}"
  echo "[BACKUP] ${f}.bak_gate_root_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

def patch_boot(p: Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    # line 18 in your grep: if (j.rid_latest ...) return String(j.rid_latest);
    # upgrade to prefer gate_root/gate
    s2, n = re.subn(
        r'return\s+String\(\s*j\.rid_latest\s*\)\s*;',
        r'return String(j.rid_latest_gate_root||j.rid_latest_gate||j.rid_latest);',
        s
    )
    # also cover patterns without String()
    s2, n2 = re.subn(
        r'\bj\.rid_latest\b',
        'j.rid_latest_gate_root||j.rid_latest_gate||j.rid_latest',
        s2
    ) if n==0 else (s2,n)
    p.write_text(s2, encoding="utf-8")
    print("[OK] boot patched", p, "n=", n, "n2=", n2 if n==0 else 0)

def patch_rid_state(p: Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    # make LS prefer storing gate_root as latest (still backward compatible)
    # Find const LS_LATEST = 'vsp_rid_latest_v1';
    s2 = s
    s2 = s2.replace("const LS_LATEST   = 'vsp_rid_latest_v1';",
                    "const LS_LATEST   = 'vsp_rid_latest_gate_root_v1';\n  const LS_LATEST_FALLBACK = 'vsp_rid_latest_v1';")
    # if code reads LS_LATEST only, also read fallback
    if "LS_LATEST_FALLBACK" in s2 and "getItem(LS_LATEST_FALLBACK" not in s2:
        s2 = re.sub(
            r'localStorage\.getItem\(\s*LS_LATEST\s*\)',
            r'(localStorage.getItem(LS_LATEST) || localStorage.getItem(LS_LATEST_FALLBACK))',
            s2
        )
    # if it writes LS_LATEST, also mirror write to old key for compatibility
    s2 = re.sub(
        r'localStorage\.setItem\(\s*LS_LATEST\s*,\s*([^)]+)\)',
        r'localStorage.setItem(LS_LATEST, \1); try{ localStorage.setItem("vsp_rid_latest_v1", String(\1)); }catch(e){}',
        s2
    )
    p.write_text(s2, encoding="utf-8")
    print("[OK] rid_state patched", p)

def patch_gate_story(p: Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    # Replace common rid extraction:
    # j.rid_latest -> prefer gate_root
    s2 = re.sub(
        r'\bj\.rid_latest\b',
        'j.rid_latest_gate_root||j.rid_latest_gate||j.rid_latest',
        s
    )
    # If it parses text rid_latest: XXX, keep that, but ensure when it fetches /api/vsp/runs it uses gate_root.
    # Add a marker so we can grep.
    if "VSP_P1_GATE_ROOT_PICK_V1" not in s2:
        s2 = s2.replace("[GateStoryV1]", "[GateStoryV1][VSP_P1_GATE_ROOT_PICK_V1]")
    p.write_text(s2, encoding="utf-8")
    print("[OK] gate_story patched", p)

for fp in ["static/js/vsp_p1_page_boot_v1.js","static/js/vsp_rid_state_v1.js","static/js/vsp_dashboard_gate_story_v1.js"]:
    p=Path(fp)
    if not p.exists(): continue
    if p.name=="vsp_p1_page_boot_v1.js": patch_boot(p)
    elif p.name=="vsp_rid_state_v1.js": patch_rid_state(p)
    elif p.name=="vsp_dashboard_gate_story_v1.js": patch_gate_story(p)
PY

echo "== grep verify =="
grep -RIn --exclude='*.bak_*' 'rid_latest_gate_root|VSP_P1_GATE_ROOT_PICK_V1|vsp_rid_latest_gate_root_v1' static/js | head -n 50 || true

echo
echo "== IMPORTANT: clear old rid cache once =="
echo "Open browser console and run:"
echo "  localStorage.removeItem('vsp_rid_latest_v1');"
echo "  localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "Then hard refresh (Ctrl+F5) /vsp5"
