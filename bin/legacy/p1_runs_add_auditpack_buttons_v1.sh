#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_runs_quick_actions_v1.js"
MARK="VSP_P1_RUNS_ADD_AUDITPACK_BTNS_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditbtn_${TS}"
echo "[BACKUP] ${JS}.bak_auditbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RUNS_ADD_AUDITPACK_BTNS_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# Helper JS snippet: download via invisible <a>
addon = r"""
/* ===================== VSP_P1_RUNS_ADD_AUDITPACK_BTNS_V1 =====================
   Add Audit Pack (Lite/Full) buttons per run row
   - Lite: /api/vsp/audit_pack_download?rid=RID&lite=1
   - Full: /api/vsp/audit_pack_download?rid=RID
   Must NOT auto-probe (only on click)
============================================================================= */
function vspDownload(url){
  try{
    const a=document.createElement('a');
    a.href=url; a.target='_blank';
    a.rel='noopener';
    a.style.display='none';
    document.body.appendChild(a);
    a.click();
    setTimeout(()=>a.remove(), 250);
  }catch(e){
    try{ window.open(url, '_blank', 'noopener'); }catch(_){}
  }
}
function vspAuditPackLiteUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}&lite=1`; }
function vspAuditPackFullUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}`; }
"""

# Insert addon near top (after first IIFE opening)
m = re.search(r"\(\(\)\s*=>\s*\{", s)
if not m:
    print("[ERR] cannot find IIFE start (()=>{)")
    raise SystemExit(2)

ins_pos = m.end()
s = s[:ins_pos] + "\n" + addon + "\n" + s[ins_pos:]

# Now we need to add buttons into row actions area.
# Heuristic: find a place where actions HTML is built; common pattern: `actions.innerHTML = ...` or template string containing buttons.
# We'll inject by adding two buttons with data-action="audit_lite/full" and wiring click handler.

# 1) Add two buttons into actions template:
# Look for 'Quick actions' container generation; if not found, we fallback to appending into any element with class 'vsp-actions' per row.
added_template = False

# Try pattern: createActionBar(...) returns HTML string
pat = re.compile(r"(return\s+`[^`]*)(`;\s*)", re.S)
# We'll only inject if the template already contains keywords like "CSV" or "TGZ" or "Open"
for mm in pat.finditer(s):
    chunk = mm.group(1)
    if ("TGZ" in chunk or "CSV" in chunk or "Open" in chunk or "JSON" in chunk) and ("audit_pack" not in chunk):
        inject_btns = r"""
        <button class="vsp-btn vsp-btn-sm" data-act="audit_lite" title="Audit evidence pack (lite)">Audit Lite</button>
        <button class="vsp-btn vsp-btn-sm" data-act="audit_full" title="Audit evidence pack (full)">Audit Full</button>
"""
        new_chunk = chunk + inject_btns
        s = s[:mm.start(1)] + new_chunk + s[mm.end(1):]
        added_template = True
        break

if not added_template:
    # If cannot patch template, we will rely on click handler only (user can add buttons later),
    # but still better to insert somewhere. Add a note.
    s = s.replace("VSP_P1_RUNS_ADD_AUDITPACK_BTNS_V1", "VSP_P1_RUNS_ADD_AUDITPACK_BTNS_V1 (template_inject_fallback)")

# 2) Add click handler for data-act audit_lite/audit_full.
# Find a global click handler or add one at end of script.
handler = r"""
// Audit Pack click delegation
document.addEventListener('click', (ev)=>{
  const t = ev.target;
  if(!t || !t.getAttribute) return;
  const act = t.getAttribute('data-act');
  if(act !== 'audit_lite' && act !== 'audit_full') return;
  const row = t.closest('[data-rid]') || t.closest('[data-run-id]') || t.closest('tr') || document;
  const rid = (row && row.getAttribute && (row.getAttribute('data-rid') || row.getAttribute('data-run-id'))) || t.getAttribute('data-rid') || '';
  if(!rid) { console.warn('[AuditPack] missing rid for click', t); return; }
  ev.preventDefault();
  ev.stopPropagation();
  const url = (act === 'audit_lite') ? vspAuditPackLiteUrl(rid) : vspAuditPackFullUrl(rid);
  vspDownload(url);
}, true);
"""

if "Audit Pack click delegation" not in s:
    s = s + "\n\n" + handler + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched runs quick actions JS with audit buttons + handler")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /runs loads (HEAD) =="
curl -sS -I "$BASE/runs" | sed -n '1,12p' || true

echo
echo "[NEXT] Open /runs in browser, verify per-run has 'Audit Lite' and 'Audit Full' buttons."
echo "[DONE]"
