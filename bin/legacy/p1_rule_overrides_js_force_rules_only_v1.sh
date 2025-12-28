#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_tab_overrides_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rulesonly_${TS}"
echo "[OK] backup: ${JS}.bak_rulesonly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_tab_overrides_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_JS_FORCE_RULES_ONLY_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Inject helper near top (after first console.log or header)
helper = r'''
/* ===== VSP_P1_RULE_OVERRIDES_JS_FORCE_RULES_ONLY_V1 =====
   Force editor to display/save {schema:"rules_v1", rules:[...]} regardless of API shape:
   - {rules:[...]} or {items:[...]} or {data:{rules|items:[...]}}.
*/
function __vspRuleOvrPickRules(obj){
  try{
    const src = (obj && typeof obj === "object") ? (obj.data && typeof obj.data==="object" ? obj.data : obj) : {};
    if (Array.isArray(src.rules)) return src.rules.filter(x=>x && typeof x==="object");
    if (Array.isArray(src.items)) return src.items.filter(x=>x && typeof x==="object");
  }catch(e){}
  return [];
}
function __vspRuleOvrNormalizeForEditor(obj){
  const rules = __vspRuleOvrPickRules(obj);
  return { schema: "rules_v1", rules: rules };
}
function __vspRuleOvrNormalizeForSave(obj){
  // accept pasted JSON in multiple shapes
  const src = (obj && typeof obj === "object") ? obj : {};
  let rules = [];
  if (Array.isArray(src.rules)) rules = src.rules;
  else if (Array.isArray(src.items)) rules = src.items;
  else if (src.data && typeof src.data==="object"){
    if (Array.isArray(src.data.rules)) rules = src.data.rules;
    else if (Array.isArray(src.data.items)) rules = src.data.items;
  }
  rules = (rules||[]).filter(x=>x && typeof x==="object");
  return { schema: "rules_v1", rules: rules };
}
'''

# place helper after first occurrence of "use strict" or first console.log or at top
ins_pos = 0
m = re.search(r'(?m)^\s*(?:console\.log\(|"use strict"|\'use strict\')', s)
if m:
    # insert after that line
    line_end = s.find("\n", m.start())
    if line_end != -1:
        ins_pos = line_end + 1

s = s[:ins_pos] + helper + "\n" + s[ins_pos:]

# 2) Patch editorHandleLoad: set textarea to normalized {schema,rules}
def patch_load(txt: str) -> str:
    # find editorHandleLoad body
    m = re.search(r'async function editorHandleLoad\(\)\s*\{', txt)
    if not m: 
        return txt
    start = m.end()
    # find end of function by naive brace counting
    i = start
    depth = 1
    while i < len(txt) and depth > 0:
        if txt[i] == '{': depth += 1
        elif txt[i] == '}': depth -= 1
        i += 1
    body = txt[start:i-1]
    # replace any "textarea.value = JSON.stringify(cfg" line to normalize cfg before stringify
    body2 = re.sub(
        r'(?m)^\s*textarea\.value\s*=\s*JSON\.stringify\(\s*cfg\s*,\s*null\s*,\s*2\s*\)\s*;\s*$',
        '    cfg = __vspRuleOvrNormalizeForEditor(cfg);\n    textarea.value = JSON.stringify(cfg, null, 2);\n',
        body
    )
    # if not found, also try to hook right before setting textarea.value the first time
    if body2 == body:
        body2 = re.sub(
            r'(?m)^\s*textarea\.value\s*=\s*JSON\.stringify\(\s*([a-zA-Z0-9_$]+)\s*,\s*null\s*,\s*2\s*\)\s*;\s*$',
            r'    \1 = __vspRuleOvrNormalizeForEditor(\1);\n    textarea.value = JSON.stringify(\1, null, 2);\n',
            body,
            count=1
        )
    return txt[:start] + body2 + txt[i-1:]

s2 = patch_load(s)

# 3) Patch editorHandleSave: normalize input JSON to {schema,rules} before POST
def patch_save(txt: str) -> str:
    m = re.search(r'async function editorHandleSave\(\)\s*\{', txt)
    if not m: 
        return txt
    start = m.end()
    i = start
    depth = 1
    while i < len(txt) and depth > 0:
        if txt[i] == '{': depth += 1
        elif txt[i] == '}': depth -= 1
        i += 1
    body = txt[start:i-1]

    # find parse point "var obj = JSON.parse(bodyText)" or similar
    # We'll inject normalization after parse.
    body_new = body
    body_new2 = re.sub(
        r'(?m)^(\s*)(var|let|const)\s+obj\s*=\s*JSON\.parse\(\s*bodyText\s*\)\s*;\s*$',
        r'\1\2 obj = JSON.parse(bodyText);\n\1obj = __vspRuleOvrNormalizeForSave(obj);\n',
        body_new
    )
    body_new = body_new2

    # also if fetch uses bodyText directly, replace with JSON.stringify(obj)
    body_new = re.sub(
        r'(?m)^(\s*body:\s*)bodyText(\s*,?\s*)$',
        r'\1JSON.stringify(obj)\2',
        body_new
    )

    # if it uses JSON.stringify(cfg) already, ensure cfg normalized
    body_new = re.sub(
        r'(?m)^(\s*)(var|let|const)\s+body\s*=\s*JSON\.stringify\(\s*([a-zA-Z0-9_$]+)\s*\)\s*;\s*$',
        r'\1\2 body = JSON.stringify(__vspRuleOvrNormalizeForSave(\3));\n',
        body_new
    )

    return txt[:start] + body_new + txt[i-1:]

s3 = patch_save(s2)

p.write_text(s3, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[DONE] Ctrl+Shift+R: http://127.0.0.1:8910/rule_overrides"
