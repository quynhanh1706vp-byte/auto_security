#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
import re, inspect
from pathlib import Path

from vsp_demo_app import app

# locate /vsp4 handler
ep = None
fn = None
for r in app.url_map.iter_rules():
    if r.rule == "/vsp4":
        ep = r.endpoint
        fn = app.view_functions[ep]
        break

if not fn:
    raise SystemExit("[ERR] cannot locate /vsp4 route in vsp_demo_app.app.url_map")

src = inspect.getsource(fn)
# find render_template("...") inside handler
m = re.search(r'render_template\(\s*[\'"]([^\'"]+)[\'"]', src)
if not m:
    print("[INFO] /vsp4 handler source:\n", src)
    raise SystemExit("[ERR] cannot find render_template(...) inside /vsp4 handler")

tpl = m.group(1)
tp = Path("templates")/tpl
if not tp.exists():
    raise SystemExit(f"[ERR] template not found: {tp}")

s = tp.read_text(encoding="utf-8", errors="replace")

if 'data-tab="rules"' in s or 'panel-rules' in s:
    print("[OK] rules tab already present:", tp)
    raise SystemExit(0)

# insert sidebar link after Data Source (best-effort)
# try insert after an anchor/button that contains "Data Source"
pat = re.compile(r'((?:<a|<button)[^>]*>[^<]*Data Source[^<]*(?:</a>|</button>))', re.I|re.S)
m2 = pat.search(s)
link = '\n<!-- VSP_RULE_OVERRIDES_TAB_V1 -->\n<a class="vsp-nav-item vsp-tab" href="#rules" data-tab="rules" id="tab-rules">Rule Overrides</a>\n'
if m2:
    s = s[:m2.end()] + link + s[m2.end():]
else:
    # fallback: just append near first nav block
    s = re.sub(r'(<nav[^>]*>)', r'\1' + link, s, flags=re.I, count=1)

panel = r"""
<!-- VSP_RULE_OVERRIDES_PANEL_V1 BEGIN -->
<section class="vsp-panel" data-panel="rules" id="panel-rules" style="display:none">
  <div class="vsp-card">
    <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap">
      <div>
        <h3 style="margin:0">Rule Overrides</h3>
        <div style="opacity:.75;font-size:12px">Load/Save overrides JSON</div>
      </div>
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <button class="vsp-btn" id="btn-rules-reload">Reload</button>
        <button class="vsp-btn" id="btn-rules-save">Save</button>
      </div>
    </div>
  </div>
  <div class="vsp-card" style="margin-top:12px">
    <textarea id="rules-json" spellcheck="false"
      style="width:100%;min-height:420px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace;
      font-size:12px;line-height:1.35;padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,.08);
      background:rgba(0,0,0,.25);color:inherit"></textarea>
    <div id="rules-msg" style="margin-top:10px;font-size:12px;opacity:.85"></div>
  </div>
</section>
<!-- VSP_RULE_OVERRIDES_PANEL_V1 END -->
"""

# place panel before </main> or </body>
if "panel-rules" not in s:
    s2 = re.sub(r'(</main>)', panel + r'\n\1', s, flags=re.I, count=1)
    if s2 == s:
        s2 = re.sub(r'(</body>)', panel + r'\n\1', s, flags=re.I, count=1)
    s = s2

# ensure JS included
if "vsp_rule_overrides_tab_v1.js" not in s:
    s = re.sub(r'(</body>)', r'\n<script src="/static/js/vsp_rule_overrides_tab_v1.js"></script>\n\1', s, flags=re.I, count=1)

bak = tp.with_suffix(tp.suffix + ".bak_rules_5tabs")
bak.write_text(tp.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
tp.write_text(s, encoding="utf-8")
print("[OK] patched template:", tp)
print("[BACKUP]", bak)
PY
