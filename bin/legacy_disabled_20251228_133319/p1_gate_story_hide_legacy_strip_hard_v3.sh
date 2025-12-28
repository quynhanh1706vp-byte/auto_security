#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# 1) locate template that serves /vsp5 (best-effort)
TPL="$(grep -RIn --exclude='*.bak_*' -m1 "/vsp5" templates 2>/dev/null | cut -d: -f1 || true)"
if [ -z "$TPL" ]; then
  # fallback: template that includes gate story js
  TPL="$(grep -RIn --exclude='*.bak_*' -m1 "vsp_dashboard_gate_story_v1.js" templates 2>/dev/null | cut -d: -f1 || true)"
fi
[ -n "$TPL" ] || { echo "[ERR] cannot locate /vsp5 template under templates/"; exit 2; }
echo "[INFO] template=$TPL"

cp -f "$TPL" "${TPL}.bak_hide_legacy_${TS}"
echo "[BACKUP] ${TPL}.bak_hide_legacy_${TS}"

# 2) wrap legacy strip area with an id (only if found)
python3 - "$TPL" <<'PY'
import sys, re
from pathlib import Path

tpl = Path(sys.argv[1])
s = tpl.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_LEGACY_STRIP_WRAPPED_V3"
if marker in s:
    print("[OK] template already wrapped")
    raise SystemExit(0)

# Heuristic: legacy strip usually contains text "Tool strip" or "Tool strip (8)"
# We'll wrap the block that contains that label line.
pat = re.compile(r'(?is)(.*?)(<[^>]*>\s*Tool\s*strip.*?</[^>]*>\s*)(.*)', re.M)
m = pat.match(s)
if not m:
    # If label isn't present (maybe already removed), just append marker comment and exit
    s2 = s + f"\n<!-- {marker}: no Tool strip label found -->\n"
    tpl.write_text(s2, encoding="utf-8")
    print("[WARN] no Tool strip label found; wrote marker only")
    raise SystemExit(0)

pre, label, post = m.group(1), m.group(2), m.group(3)

# Find a reasonable end for the legacy strip: next occurrence of the tab buttons row or next <hr> or end of gate story card
# We'll wrap from label to before the first tabs container-ish marker if found, else just wrap the next ~1200 chars safely.
cut_idx = None
for needle in [r'id="vsp_tabs"', r'class="vsp-tabs"', r'>Dashboard<', r'>Runs\s*&\s*Reports<', r'class="tab"', r'<hr']:
    mm = re.search(needle, post, flags=re.I)
    if mm:
        cut_idx = mm.start()
        break

if cut_idx is None:
    cut_idx = min(len(post), 1200)

legacy_body = post[:cut_idx]
rest = post[cut_idx:]

wrapped = f'\n<!-- {marker} -->\n<div id="vsp_tool_strip_legacy">\n{label}{legacy_body}\n</div>\n'
s2 = pre + wrapped + rest
tpl.write_text(s2, encoding="utf-8")
print("[OK] wrapped legacy strip with #vsp_tool_strip_legacy")
PY

# 3) patch GateStory JS: hide only the legacy id (safe append)
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_hide_legacy_${TS}"
echo "[BACKUP] ${JS}.bak_hide_legacy_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_HIDE_LEGACY_STRIP_BY_ID_V3"

if marker in s:
    print("[OK] JS already patched")
    raise SystemExit(0)

append = r"""
/* VSP_P1_HIDE_LEGACY_STRIP_BY_ID_V3 */
(()=> {
  try{
    if (window.__vsp_hide_legacy_by_id_v3) return;
    window.__vsp_hide_legacy_by_id_v3 = true;

    const hide = ()=>{
      const el = document.getElementById('vsp_tool_strip_legacy');
      if (el) { el.style.display='none'; el.setAttribute('data-hidden','1'); }
    };

    // run a few times (covers late DOM)
    setTimeout(hide, 50);
    setTimeout(hide, 250);
    setTimeout(hide, 800);
    setInterval(hide, 2500);

    console.log("[GateStoryV1] V3 hide legacy by id installed");
  }catch(e){
    console.warn("[GateStoryV1] V3 hide legacy failed:", e);
  }
})();
"""
p.write_text(s + "\n" + append + "\n", encoding="utf-8")
print("[OK] appended", marker)
PY

# 4) quick syntax check
node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 2; }

echo "[DONE] Restart UI service if needed, then HARD refresh /vsp5 (Ctrl+Shift+R)."
echo "       Legacy strip should be gone; tool-truth/new strip should remain unaffected."
