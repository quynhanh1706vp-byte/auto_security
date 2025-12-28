#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
import re
from pathlib import Path

UI = Path(".").resolve()
APP = UI / "vsp_demo_app.py"
tpl_dir = UI / "templates"

s = APP.read_text(encoding="utf-8", errors="replace")

# Try to locate /runs route template name
tpl_name = None
m = re.search(r'@app\.(?:get|route)\(\s*[\'"]/runs[\'"]\s*\).*?\n\s*def\s+[^(]+\([^)]*\):.*?\n\s*return\s+render_template\(\s*[\'"]([^\'"]+)[\'"]', s, re.S)
if m:
    tpl_name = m.group(1)

candidates = []
if tpl_name:
    p = tpl_dir / tpl_name
    if p.is_file():
        candidates.append(p)

# Fallback: find templates mentioning /runs or "Runs & Reports"
if tpl_dir.is_dir():
    for p in tpl_dir.glob("*.html"):
        t = p.read_text(encoding="utf-8", errors="replace")
        if "/api/vsp/runs" in t or "Runs & Reports" in t or 'href="/runs"' in t or "vsp_runs" in p.name:
            candidates.append(p)

# de-dup
seen=set()
cand=[]
for p in candidates:
    if p in seen: continue
    seen.add(p)
    cand.append(p)

if not cand:
    raise SystemExit("[ERR] cannot find runs template under templates/. Please show: ls templates/ | head")

target = cand[0]
html = target.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_EXPORT_ZIP_BTN_P0_V1"
if MARK in html:
    print("[OK] already patched:", target)
    raise SystemExit(0)

# Inject a tiny DOM patcher:
# - scans links containing /api/vsp/run_file?run_id=...
# - for each unique run_id, adds an "Export ZIP" link near that row
snippet = f"""
<script>
/* {MARK} */
(function(){{
  'use strict';
  function getRunIdFromHref(href){{
    try{{
      const u = new URL(href, window.location.origin);
      if (!u.pathname.includes('/api/vsp/run_file')) return null;
      const rid = u.searchParams.get('run_id');
      return rid || null;
    }}catch(e){{ return null; }}
  }}

  function addExportBtnNear(anchor, runId){{
    try{{
      // avoid duplicates
      const row = anchor.closest('tr') || anchor.parentElement;
      if (!row) return;
      if (row.querySelector('a[data-vsp-export-zip="1"]')) return;

      const a = document.createElement('a');
      a.textContent = 'Export ZIP';
      a.href = '/api/vsp/export_zip?run_id=' + encodeURIComponent(runId);
      a.setAttribute('data-vsp-export-zip','1');
      a.style.marginLeft = '8px';
      a.style.textDecoration = 'none';
      a.style.display = 'inline-block';
      a.style.padding = '7px 10px';
      a.style.borderRadius = '10px';
      a.style.fontWeight = '800';
      a.style.border = '1px solid rgba(90,140,255,.35)';
      a.style.background = 'rgba(90,140,255,.16)';
      a.style.color = 'inherit';

      // place right after the anchor
      anchor.insertAdjacentElement('afterend', a);
    }}catch(_e){{}}
  }}

  function patchOnce(){{
    const links = Array.from(document.querySelectorAll('a[href*="/api/vsp/run_file"]'));
    const seen = new Set();
    for (const a of links){{
      const rid = getRunIdFromHref(a.getAttribute('href') || '');
      if (!rid) continue;
      // Add once per row even if multiple file links exist
      const key = rid + '::' + (a.closest('tr') ? a.closest('tr').rowIndex : 'x');
      if (seen.has(key)) continue;
      seen.add(key);
      addExportBtnNear(a, rid);
    }}
  }}

  // run now and also after small delay (in case table loads async)
  patchOnce();
  setTimeout(patchOnce, 600);
  setTimeout(patchOnce, 1400);
}})();
</script>
"""

# Place before </body> if possible, else append
if "</body>" in html:
    html = html.replace("</body>", snippet + "\n</body>", 1)
else:
    html = html.rstrip() + "\n" + snippet + "\n"

target.write_text(html, encoding="utf-8")
print("[OK] patched runs UI:", target)
PY

echo "[DONE] UI patched. Restart 8910 then open /runs."
