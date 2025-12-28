#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_rule_overrides_tab_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rulesonly_${TS}"
echo "[OK] backup: ${JS}.bak_rulesonly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rule_overrides_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_TABV3_FORCE_RULES_ONLY_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

helper = r'''
/* ===== VSP_P1_RULE_OVERRIDES_TABV3_FORCE_RULES_ONLY_V2 =====
   Normalize ANY response shape -> {schema:"rules_v1", rules:[...]} for editor,
   and normalize ANY pasted shape -> {schema:"rules_v1", rules:[...]} for save.
*/
function __vspRuleOvr_pickRules(obj){
  try{
    const src = (obj && typeof obj === "object") ? ((obj.data && typeof obj.data==="object") ? obj.data : obj) : {};
    if (Array.isArray(src.rules)) return src.rules.filter(x=>x && typeof x==="object");
    if (Array.isArray(src.items)) return src.items.filter(x=>x && typeof x==="object");
    if (src.data && typeof src.data==="object"){
      if (Array.isArray(src.data.rules)) return src.data.rules.filter(x=>x && typeof x==="object");
      if (Array.isArray(src.data.items)) return src.data.items.filter(x=>x && typeof x==="object");
    }
  }catch(e){}
  return [];
}
function __vspRuleOvr_normEditor(obj){
  return { schema: "rules_v1", rules: __vspRuleOvr_pickRules(obj) };
}
function __vspRuleOvr_normSave(obj){
  try{
    const src = (obj && typeof obj==="object") ? obj : {};
    let rules = [];
    if (Array.isArray(src.rules)) rules = src.rules;
    else if (Array.isArray(src.items)) rules = src.items;
    else if (src.data && typeof src.data==="object"){
      if (Array.isArray(src.data.rules)) rules = src.data.rules;
      else if (Array.isArray(src.data.items)) rules = src.data.items;
    }
    rules = (rules||[]).filter(x=>x && typeof x==="object");
    return { schema:"rules_v1", rules: rules };
  }catch(e){
    return { schema:"rules_v1", rules: [] };
  }
}
'''

# insert helper near top (after "use strict" or first comment block)
ins = 0
m = re.search(r'(?m)^\s*(?:["\']use strict["\'];)', s)
if m:
    ins = s.find("\n", m.end())
    if ins != -1: ins += 1
s = s[:ins] + helper + "\n" + s[ins:]

# Patch JSON response assignments near rule_overrides endpoint:
# Replace: <var> = await <...>.json();
# With:    <var> = await <...>.json(); <var> = __vspRuleOvr_normEditor(<var>);
out=[]
last=0
for m in re.finditer(r'(?m)^\s*(const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*await\s+([A-Za-z_$][\w$]*)\.json\(\)\s*;\s*$', s):
    varname = m.group(2)
    # only patch if nearby mentions rule_overrides
    ctx = s[max(0, m.start()-500):min(len(s), m.end()+500)]
    if "rule_overrides" not in ctx:
        continue
    out.append(s[last:m.end()])
    out.append(f"\n{varname} = __vspRuleOvr_normEditor({varname});\n")
    last = m.end()
if out:
    out.append(s[last:])
    s = "".join(out)

# Patch any textarea/editor assignment that stringifies raw object (ensure it stringifies normalized rules)
# Replace JSON.stringify(cfg/null) patterns only if "rule_overrides" nearby
def repl_editor(match):
    pre = match.group(1)
    obj = match.group(2)
    post = match.group(3)
    return f'{pre}JSON.stringify(__vspRuleOvr_normEditor({obj}), null, 2){post}'

s = re.sub(r'(\bvalue\s*=\s*)JSON\.stringify\(\s*([A-Za-z_$][\w$]*)\s*,\s*null\s*,\s*2\s*\)(\s*;)',
           lambda m: repl_editor(m) if "rule_overrides" in s[max(0,m.start()-500):min(len(s),m.end()+500)] else m.group(0),
           s)

# Patch save flow: after JSON.parse(text) => normalize, and ensure body uses JSON.stringify(obj)
# 1) normalize after parse into `obj`
s = re.sub(r'(?m)^(\s*)(const|let|var)\s+obj\s*=\s*JSON\.parse\(\s*([A-Za-z_$][\w$]*)\s*\)\s*;\s*$',
           r'\1\2 obj = JSON.parse(\3);\n\1obj = __vspRuleOvr_normSave(obj);\n',
           s)

# 2) If request uses bodyText, switch to JSON.stringify(obj)
s = re.sub(r'(?m)^(\s*body:\s*)bodyText(\s*,?\s*)$',
           r'\1JSON.stringify(obj)\2',
           s)

# 3) If request uses JSON.stringify(obj) already but obj might be raw, enforce normalize inline
s = re.sub(r'JSON\.stringify\(\s*obj\s*\)',
           r'JSON.stringify(__vspRuleOvr_normSave(obj))',
           s)

# add marker comment at end (for grep)
s += f"\n/* {MARK} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[DONE] Hard refresh: Ctrl+Shift+R => http://127.0.0.1:8910/rule_overrides"
echo "[CHECK] grep marker:"
curl -fsS "http://127.0.0.1:8910/static/js/vsp_rule_overrides_tab_v3.js" | grep -n "VSP_P1_RULE_OVERRIDES_TABV3_FORCE_RULES_ONLY_V2" | head || true
