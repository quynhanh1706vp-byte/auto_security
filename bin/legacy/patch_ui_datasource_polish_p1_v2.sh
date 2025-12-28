#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ds_polish_${TS}" && echo "[BACKUP] $F.bak_ds_polish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# quick patch: replace tool input -> select + populate options from API counts.by_tool
s = re.sub(r'<input id="ds-tool"[^>]*?>',
           r'<select id="ds-tool" class="vsp-input" style="min-width:180px"><option value="">TOOL (all)</option></select>',
           s, flags=re.I)

# add helper populateToolOptions just before load()
if "function populateToolOptions" not in s:
    s = s.replace("  async function load(page){",
                  "  function populateToolOptions(byTool){\n"
                  "    const sel = document.querySelector('#ds-tool');\n"
                  "    if(!sel) return;\n"
                  "    const cur = sel.value || '';\n"
                  "    const keys = Object.keys(byTool||{}).sort((a,b)=>String(a).localeCompare(String(b)));\n"
                  "    sel.innerHTML = '<option value=\"\">TOOL (all)</option>' + keys.map(k=>`<option value=\"${k}\">${k} (${byTool[k]})</option>`).join('');\n"
                  "    if(cur) sel.value = cur;\n"
                  "  }\n\n"
                  "  async function load(page){")

# adjust read tool value from select
s = s.replace('const tool = ($("#ds-tool")?.value || "").trim();',
              'const tool = ($("#ds-tool")?.value || "").trim();')

# on success: call populateToolOptions
if "populateToolOptions(j.counts" not in s:
    s = s.replace("    renderTable(j.items || []);",
                  "    renderTable(j.items || []);\n"
                  "    try{ populateToolOptions((j.counts||{}).by_tool||{}); }catch(_){ }\n")

# show sev stats in meta (compact)
s = s.replace('if ($("#ds-meta")) $("#ds-meta").textContent = `RID=${rid} | ${start}-${end}/${total} | src=${src}${warn}`;',
              'const sev = (j.counts||{}).by_sev||{};\n'
              'const sevMini = Object.keys(sev).sort().map(k=>`${k}:${sev[k]}`).join(" ");\n'
              'if ($("#ds-meta")) $("#ds-meta").textContent = `RID=${rid} | ${start}-${end}/${total} | ${sevMini} | src=${src}${warn}`;')

p.write_text(s, encoding="utf-8")
print("[OK] patched datasource polish v2")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh (Ctrl+Shift+R)."
