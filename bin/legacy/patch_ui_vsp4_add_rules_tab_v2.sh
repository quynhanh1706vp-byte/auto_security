#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# auto-detect: pick the template that contains BOTH "Runs & Reports" and "Data Source"
T="$(grep -RIl --exclude='*.bak_*' -e 'Runs & Reports' templates | head -n1 || true)"
[ -n "$T" ] || { echo "[ERR] cannot find vsp4 template in templates/"; exit 2; }
grep -q 'Data Source' "$T" || { echo "[ERR] detected template missing 'Data Source': $T"; exit 3; }

# idempotent
grep -q 'data-tab="rules"' "$T" && { echo "[OK] rules tab already present in $T"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_rules_${TS}"
echo "[BACKUP] $T.bak_rules_${TS}"
echo "[T] $T"

python3 - <<'PY'
from pathlib import Path
import re

t = Path(open("/dev/stdin").read().strip()) if False else None
PY
python3 - <<PY
from pathlib import Path
import re, sys

T = Path("$T")
s = T.read_text(encoding="utf-8", errors="replace")

# 1) Insert sidebar/menu item right AFTER the Data Source entry (button or a)
# Support both <a>..Data Source..</a> and <button>..Data Source..</button>
def insert_after_datasource(html):
    pat = re.compile(r'((?:<a|<button)[^>]*>(?:\\s|&nbsp;)*Data Source(?:\\s|&nbsp;)*.*?(?:</a>|</button>))', re.I|re.S)
    m = pat.search(html)
    if not m:
        return html, False
    block = """
<!-- VSP_RULE_OVERRIDES_TAB_V2 -->
<a class="vsp-nav-item vsp-tab" href="#rules" data-tab="rules" id="tab-rules">Rule Overrides</a>
"""
    return html[:m.end()] + "\n" + block + "\n" + html[m.end():], True

s2, ok = insert_after_datasource(s)
if not ok:
    # fallback: append to sidebar container if present
    s2 = re.sub(r'(<nav[^>]*class="[^"]*vsp[^"]*"[^>]*>)', r'\\1\\n<a class="vsp-nav-item vsp-tab" href="#rules" data-tab="rules" id="tab-rules">Rule Overrides</a>\\n', s, flags=re.I, count=1)
s = s2

# 2) Add panel section for rules (append before </main> or </body>)
panel = r"""
<!-- VSP_RULE_OVERRIDES_PANEL_V2 BEGIN -->
<section class="vsp-panel" data-panel="rules" id="panel-rules" style="display:none">
  <div class="vsp-card">
    <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap">
      <div>
        <h3 style="margin:0">Rule Overrides</h3>
        <div style="opacity:.75;font-size:12px">Load/Save overrides JSON (FORCE_BIND_V1)</div>
      </div>
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <button class="vsp-btn" id="btn-rules-reload">Reload</button>
        <button class="vsp-btn" id="btn-rules-save">Save</button>
      </div>
    </div>
  </div>
  <div class="vsp-card" style="margin-top:12px">
    <textarea id="rules-json" spellcheck="false" style="width:100%;min-height:420px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace;font-size:12px;line-height:1.35;padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.25);color:inherit"></textarea>
    <div id="rules-msg" style="margin-top:10px;font-size:12px;opacity:.85"></div>
  </div>
</section>
<!-- VSP_RULE_OVERRIDES_PANEL_V2 END -->
"""

if "panel-rules" not in s:
    # try after datasource panel if exists
    s3 = re.sub(r'(<section[^>]+data-panel="datasource"[^>]*>.*?</section>)', r'\\1\\n' + panel, s, flags=re.I|re.S, count=1)
    if s3 == s:
        s3 = re.sub(r'(</main>)', panel + r'\\n\\1', s, flags=re.I, count=1)
    if s3 == s:
        s3 = re.sub(r'(</body>)', panel + r'\\n\\1', s, flags=re.I, count=1)
    s = s3

# 3) Ensure JS included
if "vsp_rule_overrides_tab_v1.js" not in s:
    s = re.sub(r'(</body>)', '\\n<script src="/static/js/vsp_rule_overrides_tab_v1.js"></script>\\n\\1', s, flags=re.I, count=1)

T.write_text(s, encoding="utf-8")
print("[OK] patched template:", T)
PY

echo "[DONE] patched $T"
