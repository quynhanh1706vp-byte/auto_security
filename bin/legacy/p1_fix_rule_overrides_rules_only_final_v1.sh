#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

J1="static/js/vsp_rule_overrides_tab_v3.js"
J2="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$J1" ] || { echo "[ERR] missing $J1"; exit 2; }
[ -f "$J2" ] || { echo "[ERR] missing $J2"; exit 2; }

cp -f "$J1" "${J1}.bak_rulesfinal_${TS}"
cp -f "$J2" "${J2}.bak_rulesfinal_${TS}"
echo "[OK] backup: ${J1}.bak_rulesfinal_${TS}"
echo "[OK] backup: ${J2}.bak_rulesfinal_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P1_RULE_OVERRIDES_RULES_ONLY_FINAL_V1"

def norm_helper_js():
    return r'''
/* ===== VSP_P1_RULE_OVERRIDES_RULES_ONLY_FINAL_V1 =====
   Normalize any API shape to {schema:"rules_v1", rules:[...]}.
*/
function __vspRO_pickRules(j){
  try{
    if(!j || typeof j!=="object") return [];
    // prefer top-level rules
    if(Array.isArray(j.rules)) return j.rules.filter(x=>x && typeof x==="object");
    // allow top-level items legacy
    if(Array.isArray(j.items)) return j.items.filter(x=>x && typeof x==="object");
    // allow data.* variants
    const d = (j.data && typeof j.data==="object") ? j.data : null;
    if(d){
      if(Array.isArray(d.rules)) return d.rules.filter(x=>x && typeof x==="object");
      if(Array.isArray(d.items)) return d.items.filter(x=>x && typeof x==="object");
    }
  }catch(e){}
  return [];
}
function __vspRO_norm(j){
  return { schema:"rules_v1", rules: __vspRO_pickRules(j) };
}
function __vspRO_normFromText(txt){
  try{
    const obj = JSON.parse(txt || "{}");
    return __vspRO_norm(obj);
  }catch(e){
    return { schema:"rules_v1", rules: [] };
  }
}
'''.strip("\n") + "\n"

# -------- patch vsp_rule_overrides_tab_v3.js ----------
p1=Path("static/js/vsp_rule_overrides_tab_v3.js")
s=p1.read_text(encoding="utf-8", errors="replace")
if MARK not in s:
    # Insert helper near top (after first comment or at beginning)
    ins=0
    m=re.search(r'(?m)^/\*', s)
    if m: ins=m.start()
    s = s[:ins] + norm_helper_js() + s[ins:]

# Fix endpoints: make save point to /api/ui/rule_overrides_v2 (POST)
s = s.replace('save:  "/api/ui/rule_overrides_v2_save_v2",', 'save:  "/api/ui/rule_overrides_v2",')
# Keep apply as-is; if it fails UI can still show rules and save globally.

# Fix textarea render (line you showed): stringify normalized rules instead of j.data
# Replace exact pattern if present:
s = s.replace('ta.value = JSON.stringify((j.data||{"rules":[]}), null, 2);',
              'ta.value = JSON.stringify(__vspRO_norm(j), null, 2);')

# Ensure save uses normalized payload even if obj is weird
# Replace body JSON.stringify(obj||{}) in this file to JSON.stringify(__vspRO_norm(obj||{}))
s = s.replace('body: JSON.stringify(obj||{})',
              'body: JSON.stringify(__vspRO_norm(obj||{}))')

# Add marker at EOF
if MARK not in s:
    s += f"\n/* {MARK} */\n"
p1.write_text(s, encoding="utf-8")
print("[OK] patched", p1)

# -------- patch vsp_bundle_tabs5_v1.js ----------
p2=Path("static/js/vsp_bundle_tabs5_v1.js")
b=p2.read_text(encoding="utf-8", errors="replace")

if MARK not in b:
    # Insert helper once near top (after first big comment or at beginning)
    ins=0
    m=re.search(r'(?m)^/\*', b)
    if m: ins=m.start()
    b = b[:ins] + norm_helper_js() + b[ins:]

# In rule_overrides injector, force textarea to show normalized rules
# 1) ta.value = JSON.stringify(j, null, 2)  -> normalize
b = b.replace('ta.value = JSON.stringify(j, null, 2);',
              'ta.value = JSON.stringify(__vspRO_norm(j), null, 2);')

# 2) ta.value = JSON.stringify(rules, null, 2)  -> if rules variable is array/object, wrap to {schema,rules}
# We only replace the exact line shown by your grep.
b = b.replace('ta.value = JSON.stringify(rules, null, 2);',
              'ta.value = JSON.stringify((Array.isArray(rules)?{schema:"rules_v1",rules:rules}:__vspRO_norm(rules)), null, 2);')

# 3) Ensure POST body uses normalized payload from textarea content
# Common patterns: payload = JSON.parse(ta.value) then body: JSON.stringify(payload)
# We harden by normalizing right before stringify if we can find "body: JSON.stringify(payload)"
b = b.replace('body: JSON.stringify(payload)',
              'body: JSON.stringify(__vspRO_norm(payload))')

# Also if it stringifies raw parsed object directly
b = b.replace('body: JSON.stringify(obj)',
              'body: JSON.stringify(__vspRO_norm(obj))')

if MARK not in b:
    b += f"\n/* {MARK} */\n"
p2.write_text(b, encoding="utf-8")
print("[OK] patched", p2)
PY

echo "== markers =="
curl -fsS "$BASE/static/js/vsp_rule_overrides_tab_v3.js" | grep -n "VSP_P1_RULE_OVERRIDES_RULES_ONLY_FINAL_V1" | head
curl -fsS "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_P1_RULE_OVERRIDES_RULES_ONLY_FINAL_V1" | head

echo "[DONE] Ctrl+Shift+R then click Reload on UI:"
echo "  $BASE/rule_overrides"
