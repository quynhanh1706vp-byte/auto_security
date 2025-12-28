#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# 1) Patch templates that actually contain legacy "Tool strip"
mapfile -t TPLS < <(grep -RIl --exclude='*.bak_*' "Tool strip" templates 2>/dev/null || true)

if [ "${#TPLS[@]}" -gt 0 ]; then
  echo "[INFO] templates with legacy Tool strip: ${#TPLS[@]}"
  for TPL in "${TPLS[@]}"; do
    [ -f "$TPL" ] || continue
    cp -f "$TPL" "${TPL}.bak_hide_legacy_${TS}"
    echo "[BACKUP] ${TPL}.bak_hide_legacy_${TS}"

    python3 - "$TPL" <<'PY'
import sys, re
from pathlib import Path

tpl = Path(sys.argv[1])
s = tpl.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_LEGACY_STRIP_WRAPPED_V3B"
if marker in s:
    print("[OK] already wrapped:", tpl)
    raise SystemExit(0)

# Wrap block starting at "Tool strip" label (best-effort)
m = re.search(r'(?is)(<[^>]*>\s*Tool\s*strip.*?</[^>]*>)', s)
if not m:
    print("[WARN] no Tool strip label in:", tpl)
    tpl.write_text(s + f"\n<!-- {marker}: no Tool strip found -->\n", encoding="utf-8")
    raise SystemExit(0)

start = m.start()
# find an end boundary after label (tabs/buttons or hr)
tail = s[m.end():]
cut = None
for needle in [r'id="vsp_tabs"', r'class="vsp-tabs"', r'>Dashboard<', r'>Runs\s*&\s*Reports<', r'class="tab"', r'<hr']:
    mm = re.search(needle, tail, flags=re.I)
    if mm:
        cut = m.end() + mm.start()
        break
if cut is None:
    cut = min(len(s), m.end() + 1200)

legacy_block = s[start:cut]
s2 = s[:start] + f"\n<!-- {marker} -->\n<div id=\"vsp_tool_strip_legacy\">\n" + legacy_block + "\n</div>\n" + s[cut:]
tpl.write_text(s2, encoding="utf-8")
print("[OK] wrapped legacy strip:", tpl)
PY
  done
else
  echo "[WARN] no template contains 'Tool strip' (maybe legacy already removed)."
fi

# 2) Patch GateStory JS: hide ONLY #vsp_tool_strip_legacy (safe)
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_hide_legacy_${TS}"
echo "[BACKUP] ${JS}.bak_hide_legacy_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_HIDE_LEGACY_STRIP_BY_ID_V3B"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

append = r"""
/* VSP_P1_HIDE_LEGACY_STRIP_BY_ID_V3B */
(()=> {
  try{
    if (window.__vsp_hide_legacy_by_id_v3b) return;
    window.__vsp_hide_legacy_by_id_v3b = true;

    const hide = ()=>{
      const el = document.getElementById('vsp_tool_strip_legacy');
      if (el) { el.style.display='none'; el.setAttribute('data-hidden','1'); }
    };

    setTimeout(hide, 50);
    setTimeout(hide, 250);
    setTimeout(hide, 900);
    setInterval(hide, 2500);

    console.log("[GateStoryV1] V3B hide legacy by id installed");
  }catch(e){
    console.warn("[GateStoryV1] V3B hide legacy failed:", e);
  }
})();
"""
p.write_text(s + "\n" + append + "\n", encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 2; }

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R). Legacy strip should be gone; Tool truth/new strip remains."
