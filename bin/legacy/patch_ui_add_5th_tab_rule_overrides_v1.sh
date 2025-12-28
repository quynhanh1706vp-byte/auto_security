#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

# idempotent
grep -q "VSP_RULE_OVERRIDES_TAB_V1" "$T" && { echo "[OK] rule overrides tab already present"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_5tabs_${TS}"
echo "[BACKUP] $T.bak_5tabs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) add tab button/link in tab bar (best effort: after Data Source)
tab_btn = r"""
<!-- VSP_RULE_OVERRIDES_TAB_V1 -->
<a class="vsp-tab" href="#rules" data-tab="rules" id="tab-rules">Rule Overrides</a>
"""

# try to insert after datasource tab button
s2 = re.sub(r'(<a[^>]+data-tab="datasource"[^>]*>.*?</a>)',
            r'\1\n' + tab_btn, s, flags=re.I|re.S, count=1)
if s2 == s:
    # fallback: append into first tab container
    s2 = re.sub(r'(<div[^>]+class="[^"]*(?:vsp-tabs|tabs)[^"]*"[^>]*>)',
                r'\1\n' + tab_btn, s, flags=re.I|re.S, count=1)

s = s2

# 2) add panel container for rules (best effort: after datasource panel)
panel = r"""
<!-- VSP_RULE_OVERRIDES_PANEL_V1 BEGIN -->
<section class="vsp-panel" data-panel="rules" id="panel-rules" style="display:none">
  <div class="vsp-card">
    <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap">
      <div>
        <h3 style="margin:0">Rule Overrides</h3>
        <div style="opacity:.75;font-size:12px">Edit rule overrides used by gate/unify (persisted as JSON)</div>
      </div>
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <button class="vsp-btn" id="btn-rules-reload">Reload</button>
        <button class="vsp-btn" id="btn-rules-save">Save</button>
      </div>
    </div>
  </div>

  <div class="vsp-card" style="margin-top:12px">
    <div style="opacity:.8;font-size:12px;margin-bottom:6px">JSON (edit carefully)</div>
    <textarea id="rules-json" spellcheck="false" style="width:100%;min-height:420px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace;font-size:12px;line-height:1.35;padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.25);color:inherit"></textarea>
    <div id="rules-msg" style="margin-top:10px;font-size:12px;opacity:.85"></div>
  </div>
</section>
<!-- VSP_RULE_OVERRIDES_PANEL_V1 END -->
"""

s2 = re.sub(r'(data-panel="datasource"[^>]*>.*?</section>)',
            r'\1\n' + panel, s, flags=re.I|re.S, count=1)
if s2 == s:
    # fallback: append before </body>
    s2 = re.sub(r'(</body>)', panel + r'\n\1', s, flags=re.I, count=1)
s = s2

# 3) include JS (if template already includes other JS, append near end)
js_tag = r'\n<script src="/static/js/vsp_rule_overrides_tab_v1.js"></script>\n'
if "vsp_rule_overrides_tab_v1.js" not in s:
    s = re.sub(r'(</body>)', js_tag + r'\1', s, flags=re.I, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] 5th tab + panel + js injected")
PY

echo "[DONE] patched $T"
