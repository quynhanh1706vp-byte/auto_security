#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BUNDLE="static/js/vsp_bundle_commercial_v2.js"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI"  "${WSGI}.bak_stopjump_${TS}"
cp -f "$BUNDLE" "${BUNDLE}.bak_stopjump_${TS}"
echo "[BACKUP] ${WSGI}.bak_stopjump_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_stopjump_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

WSGI = Path("wsgi_vsp_ui_gateway.py")
BUNDLE = Path("static/js/vsp_bundle_commercial_v2.js")

# ---------------------------
# (A) Patch bundle: block legacy V6 setIntervals + clear old RID pins
# ---------------------------
s = BUNDLE.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_DASH_STOP_JUMP_SINGLE_RENDERER_V1"
if marker not in s:
    patch = r"""
/* VSP_P0_DASH_STOP_JUMP_SINGLE_RENDERER_V1
 * - Block legacy V6 polling intervals that cause layout flip/jump
 * - Clear old RID pins to avoid snapping back to RUN_*
 */
(()=> {
  try{
    if (window.__vsp_p0_stop_jump_single_renderer_v1) return;
    window.__vsp_p0_stop_jump_single_renderer_v1 = true;

    // Clear RID pins that often force jump back to old RUN_*
    try{
      const keys = ["vsp.rid","VSP_RID","rid","vsp_rid","vsp.rid.pinned","vsp_rid_pinned","vsp:last_rid"];
      keys.forEach(k => { try{ localStorage.removeItem(k); }catch(e){} });
    }catch(e){}

    // Block ONLY legacy V6 interval callbacks (string contains V6C/V6D/V6E markers)
    const _si = window.setInterval;
    window.setInterval = function(fn, t, ...args){
      try{
        const src = String(fn || "");
        if (
          src.includes("legacy disabled (V6") ||
          src.includes("V6C") || src.includes("V6D") || src.includes("V6E")
        ){
          try{ console.debug("[VSP][PATCH] blocked legacy V6 interval"); }catch(e){}
          return 0;
        }
      }catch(e){}
      return _si(fn, t, ...args);
    };
  }catch(e){}
})();
"""
    # prepend patch (safe even if bundle is minified)
    s = patch + "\n" + s
    BUNDLE.write_text(s, encoding="utf-8")
    print("[OK] patched bundle:", marker)
else:
    print("[OK] bundle already patched:", marker)

# quick sanity: ensure we didn't break JS too obviously (best-effort)
# (can't run node here reliably; shell will do it)

# ---------------------------
# (B) Patch WSGI: dedupe gate_story script in /vsp5 html + clean \\n literal
# ---------------------------
w = WSGI.read_text(encoding="utf-8", errors="replace")
w_marker = "VSP_P0_VSP5_DEDUPE_GATE_STORY_V1"
changed = False

# 1) dedupe repeated gate_story script tags (2->1) anywhere in wsgi-produced HTML
pat = r'(?is)(<script[^>]+src="/static/js/vsp_dashboard_gate_story_v1\.js[^"]*"[^>]*>\s*</script>\s*){2,}'
w2 = re.sub(pat, r"\1", w)
if w2 != w:
    w = w2
    changed = True
    print("[OK] dedupe gate_story script tags (2->1)")

# 2) fix accidental literal \\n after </title> (so browser doesn't show "\n" text)
# We only reduce double-slash to single escape sequence inside python string literals.
w2 = w.replace("</title>\\\\n", "</title>\\n")
if w2 != w:
    w = w2
    changed = True
    print("[OK] fixed literal \\\\n -> \\n after </title>")

if changed and w_marker not in w:
    w = w + "\n\n# " + w_marker + "\n"
    WSGI.write_text(w, encoding="utf-8")
    print("[OK] patched wsgi:", w_marker)
else:
    print("[OK] wsgi no change needed")

PY

echo "== node --check (best effort) =="
node --check "$BUNDLE" >/dev/null 2>&1 && echo "[OK] node --check passed" || echo "[WARN] node --check skipped/failed (non-fatal)"

echo "== compile check wsgi =="
python3 -m py_compile "$WSGI"

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify /vsp5: gate_story should appear ONCE =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" || true
echo "== DONE =="
echo "Hard refresh /vsp5 (Ctrl+Shift+R). In Console you should see: [VSP][PATCH] blocked legacy V6 interval (and no more spam legacy disabled V6C/V6D/V6E)."
