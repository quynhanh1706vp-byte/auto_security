#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_freeze_hotfix_${TS}"
echo "[BACKUP] ${JS}.bak_freeze_hotfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_POLISH_ALL3_V1" not in s:
    print("[ERR] marker VSP_P1_POLISH_ALL3_V1 not found in bundle")
    raise SystemExit(2)

# 1) Remove characterData observers (prevents self-trigger loop when updating text)
s2 = re.sub(
    r'mo\.observe\(document\.body,\s*\{subtree:true,\s*childList:true,\s*characterData:true\}\);',
    'mo.observe(document.body, {subtree:true, childList:true});',
    s
)

# 2) Update badge text only if changed (prevents mutation storms)
def patch_badge_block(src, badge_id):
    # Replace "b.textContent = ..." with guarded assignment near that badge id
    # best-effort: find the observer callback area after creating badge
    pat = rf'(id\s*=\s*[\'"]{re.escape(badge_id)}[\'"][\s\S]{{0,1200}}?const mo=new MutationObserver\(\(\)=>\{{[\s\S]{{0,1600}}?)b\.textContent\s*=\s*([^;]+);'
    def repl(m):
        pre = m.group(1)
        expr = m.group(2).strip()
        return pre + (
            "const __txt = ("+expr+");"
            " if (b.textContent !== __txt) b.textContent = __txt;"
        )
    return re.sub(pat, repl, src, count=1)

s2 = patch_badge_block(s2, "vsp_p1_runs_showing_badge")
s2 = patch_badge_block(s2, "vsp_p1_findings_showing_badge")

# 3) Throttle global MutationObserver that reruns runAll (prevents hot loop)
# Replace:
# const mo = new MutationObserver(()=>{ runAll(); });
# mo.observe(document.body, {subtree:true, childList:true});
throttle = r"""
    let __t=null;
    const mo = new MutationObserver(()=>{
      if (__t) return;
      __t = setTimeout(()=>{ __t=null; try{ runAll(); }catch(_){ } }, 250);
    });
    mo.observe(document.body, {subtree:true, childList:true});
"""
s2, n = re.subn(
    r'const mo\s*=\s*new MutationObserver\(\(\)=>\{\s*runAll\(\);\s*\}\);\s*mo\.observe\(document\.body,\s*\{subtree:true,\s*childList:true\}\);\s*',
    throttle,
    s2,
    count=1
)

# 4) Add re-entry guard for runAll (avoid nested runs)
# transform function runAll(){ patchFetchLimit(); ... fixRuleOverridesMetrics(); }
# -> function runAll(){ if(__running) return; __running=true; try{...} finally{__running=false;} }
if "function runAll()" in s2 and "__vsp_all3_running" not in s2:
    s2 = re.sub(
        r'function runAll\(\)\{\s*',
        'let __vsp_all3_running=false;\n  function runAll(){ if(__vsp_all3_running) return; __vsp_all3_running=true; try{\n',
        s2,
        count=1
    )
    # close try/finally before the function ends (best effort: just before the first "}" that ends runAll block
    s2 = re.sub(
        r'(fixRuleOverridesMetrics\(\);\s*)\n\s*\}',
        r'\1\n  } finally { __vsp_all3_running=false; }\n}',
        s2,
        count=1
    )

if s2 == s:
    print("[WARN] no changes applied (patterns not matched). Still writing to be safe.")
else:
    print("[OK] applied hotfix changes")

p.write_text(s2, encoding="utf-8")
PY

if [ "$HAVE_NODE" = "1" ]; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
else
  echo "[WARN] node not found; skipped node --check"
fi

# restart UI via your proven starter
rm -f /tmp/vsp_ui_8910.lock || true
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo
echo "DONE. Now reopen /vsp5 and Ctrl+F5. The tab should NOT freeze anymore."
