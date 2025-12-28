#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path
import re

td = Path("templates")
cands = []
for fp in td.glob("*.html"):
    t = fp.read_text(encoding="utf-8", errors="ignore")
    if "Data Source" in t and "vsp-pane-datasource" not in t:
        cands.append(fp)

if not cands:
    print("[OK] no template needs patch (or cannot locate).")
    raise SystemExit(0)

fp = cands[0]
t = fp.read_text(encoding="utf-8", errors="ignore")

TS = __import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")
bak = fp.with_suffix(fp.suffix + f".bak_datasource_{TS}")
bak.write_text(t, encoding="utf-8")
print("[BACKUP]", bak)

PANE = r'''
<!-- === VSP_DATASOURCE_PANE_V1 === -->
<section id="vsp-pane-datasource" class="vsp-pane" style="display:none;">
  <div style="padding:14px 16px;">
    <div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
      <div style="font-weight:700; letter-spacing:.2px;">Data Source</div>
      <div style="opacity:.7; font-size:12px;">Preview unified findings per run (commercial)</div>
    </div>

    <div style="margin-top:12px; display:grid; grid-template-columns: 1.2fr .7fr .7fr 1.2fr auto; gap:10px; align-items:end;">
      <div>
        <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Run ID</div>
        <input id="vsp-ds-rid" class="vsp-input" placeholder="RUN_VSP_CI_YYYYmmdd_HHMMSS" style="width:100%;">
      </div>
      <div>
        <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Tool</div>
        <input id="vsp-ds-tool" class="vsp-input" placeholder="e.g. SEMGREP" style="width:100%;">
      </div>
      <div>
        <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Severity</div>
        <input id="vsp-ds-sev" class="vsp-input" placeholder="CRITICAL/HIGH/..." style="width:100%;">
      </div>
      <div>
        <div style="font-size:12px; opacity:.75; margin-bottom:6px;">Search</div>
        <input id="vsp-ds-q" class="vsp-input" placeholder="rule/file/title..." style="width:100%;">
      </div>
      <div style="display:flex; gap:8px;">
        <button id="vsp-ds-load" class="vsp-btn">Load</button>
        <button id="vsp-ds-next" class="vsp-btn vsp-btn-ghost">Next</button>
      </div>
    </div>

    <div id="vsp-ds-meta" style="margin-top:10px; font-size:12px; opacity:.8;"></div>

    <div style="margin-top:10px; border:1px solid rgba(255,255,255,.08); border-radius:12px; overflow:hidden;">
      <div style="overflow:auto; max-height: 55vh;">
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <thead style="position:sticky; top:0; background:rgba(2,6,23,.92);">
            <tr>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">Tool</th>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">Severity</th>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">Title</th>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">File</th>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">Line</th>
              <th style="text-align:left; padding:10px; border-bottom:1px solid rgba(255,255,255,.08);">Rule</th>
            </tr>
          </thead>
          <tbody id="vsp-ds-tbody"></tbody>
        </table>
      </div>
    </div>
  </div>
</section>
<!-- === /VSP_DATASOURCE_PANE_V1 === -->
'''

# chèn pane trước </main> hoặc trước footer nếu có
if "</main>" in t:
    t = t.replace("</main>", PANE + "\n</main>", 1)
else:
    t = t + "\n" + PANE + "\n"

# include JS trước </body>
JS = '<script src="/static/js/vsp_datasource_tab_v1.js"></script>\n'
if "vsp_datasource_tab_v1.js" not in t:
    t = t.replace("</body>", JS + "</body>", 1)

fp.write_text(t, encoding="utf-8")
print("[OK] patched template:", fp)
PY

echo "[DONE] restart 8910 + hard refresh"
