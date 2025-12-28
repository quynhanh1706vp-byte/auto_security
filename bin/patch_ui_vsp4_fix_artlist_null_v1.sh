#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_ui_4tabs_commercial_v1.js"
TPL="templates/vsp_4tabs_commercial_v1.html"
[ -f "$JSF" ] || { echo "[ERR] missing $JSF"; exit 1; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JSF" "$JSF.bak_fix_artlist_${TS}"
cp -f "$TPL" "$TPL.bak_fix_artlist_${TS}"
echo "[BACKUP] $JSF.bak_fix_artlist_${TS}"
echo "[BACKUP] $TPL.bak_fix_artlist_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

# --- 1) Template: ensure #art-list exists (compat) ---
tpl = Path("templates/vsp_4tabs_commercial_v1.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

if 'id="art-list"' not in t:
    # inject hidden compat div near artifacts JSON box (safe)
    anchor = 'id="ds-artjson"'
    i = t.find(anchor)
    if i == -1:
        # fallback: append near end of Data Source section
        insert = '\n<div id="art-list" class="vsp-mono" style="display:none"></div>\n'
        t = t.replace("</section>", insert + "</section>", 1)
        print("[OK] inserted hidden #art-list (fallback)")
    else:
        # insert after artifacts json div line
        t = t.replace(
            '      <div id="ds-artjson" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>',
            '      <div id="ds-artjson" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>\n'
            '      <div id="art-list" class="vsp-mono" style="display:none"></div>',
            1
        )
        print("[OK] inserted hidden #art-list (compat)")
else:
    print("[SKIP] template already has #art-list")

tpl.write_text(t, encoding="utf-8")

# --- 2) JS: harden renderArtifacts() against missing nodes ---
js = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
j = js.read_text(encoding="utf-8", errors="ignore")

TAG = "/* === VSP_UI_FIX_ARTLIST_NULL_V1 === */"
if TAG in j:
    print("[SKIP] JS already fixed")
    raise SystemExit(0)

# Replace only inside renderArtifacts block: guard #art-list and #pill-art
def patch_render_artifacts(src: str) -> str:
    # locate renderArtifacts function
    m = re.search(r'async function renderArtifacts\(rid\)\{([\s\S]*?)\n\s*\}\n', src)
    if not m:
        print("[WARN] cannot locate renderArtifacts() to patch precisely; applying simple guards")
        src = src.replace('$("#art-list").textContent =', 'const __al=$("#art-list"); if(__al) __al.textContent =')
        src = src.replace('$("#pill-art").textContent =', 'const __pa=$("#pill-art"); if(__pa) __pa.textContent =')
        return TAG + "\n" + src

    body = m.group(1)

    # inject safe element gets at top of renderArtifacts try block (after items computed)
    # We'll rewrite the two assignments with guards
    body2 = body
    body2 = re.sub(r'(\#\("pill-art"\)\.textContent\s*=\s*[^;]+;)',
                   r'const __pa = $("#pill-art"); if(__pa) __pa.textContent = String(items.length);',
                   body2)

    body2 = re.sub(r'(\#\("art-list"\)\.textContent\s*=\s*[^;]+;)',
                   r'const __al = $("#art-list"); if(__al) __al.textContent = items.slice(0,300).map(x=>{'
                   r'\n        if (typeof x === "string") return x;'
                   r'\n        return x.path || x.name || JSON.stringify(x);'
                   r'\n      }).join("\\n");',
                   body2)

    # If patterns didn't match (because original uses $("#art-list").textContent directly), do a simpler replace:
    body2 = body2.replace('$("#pill-art").textContent = String(items.length);',
                          'const __pa = $("#pill-art"); if(__pa) __pa.textContent = String(items.length);')
    body2 = body2.replace('$("#art-list").textContent = items.slice(0,300).map(x=>{',
                          'const __al=$("#art-list"); if(__al) __al.textContent = items.slice(0,300).map(x=>{')
    body2 = body2.replace('}).join("\\n");', '}).join("\\n");')  # keep

    # Patch error branch too (if it writes #art-list)
    body2 = body2.replace('$("#art-list").textContent = String(e);',
                          'const __al=$("#art-list"); if(__al) __al.textContent = String(e);')

    new_func = 'async function renderArtifacts(rid){' + body2 + '\n  }\n'
    src2 = src[:m.start()] + new_func + src[m.end():]
    return TAG + "\n" + src2

j2 = patch_render_artifacts(j)
js.write_text(j2, encoding="utf-8")
print("[OK] JS patched (null-guard)")
PY

python3 -m py_compile vsp_demo_app.py >/dev/null
rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== SMOKE =="
curl -sS -o /dev/null -w "GET /vsp4 HTTP=%{http_code}\n" http://127.0.0.1:8910/vsp4
echo "[OK] open: http://127.0.0.1:8910/vsp4#runs"
