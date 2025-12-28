#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "VSP_RUNS_SET_RID_V1" "$F" && { echo "[OK] already patched: VSP_RUNS_SET_RID_V1"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_setrid_${TS}"
echo "[BACKUP] $F.bak_setrid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_tab_resolved_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) inject helpers after mkLink()
helper_marker = "// === VSP_RUNS_SET_RID_V1 ==="
if helper_marker not in s:
    m = re.search(r"function\s+mkLink\s*\(\s*href\s*,\s*label\s*\)\s*\{[\s\S]*?\}\s*", s)
    if not m:
        raise SystemExit("[ERR] cannot find mkLink() to inject helpers")
    insert_at = m.end()
    helpers = r'''
  // === VSP_RUNS_SET_RID_V1 ===
  var VSP_RID_KEY = 'VSP_CURRENT_RID';
  var VSP_RID_RE = /(RUN_)?VSP_CI_\d{8}_\d{6}/;

  function normalizeRidForApi(rid){
    rid = String(rid || '').trim();
    if (!rid) return '';
    // if it's VSP_CI_... without RUN_, prefix it to be consistent
    if (!rid.startsWith('RUN_') && /^VSP_CI_\d{8}_\d{6}$/.test(rid)) return 'RUN_' + rid;
    // keep other forms (already RUN_..., or other request ids)
    return rid;
  }

  function getCurrentRid(){
    try {
      var v = localStorage.getItem(VSP_RID_KEY) || '';
      var m = (v || '').match(VSP_RID_RE);
      return m ? normalizeRidForApi(m[0]) : normalizeRidForApi(v);
    } catch (e) {
      return '';
    }
  }

  function setCurrentRid(rid, opts){
    opts = opts || {};
    rid = normalizeRidForApi(rid);
    if (!rid) return false;

    try { localStorage.setItem(VSP_RID_KEY, rid); } catch (e) {}

    // update sticky label if present
    try {
      var lab = document.getElementById('vsp-rid-label');
      if (lab) lab.textContent = 'RID: ' + rid;
    } catch (e) {}

    // notify other tabs
    try {
      window.dispatchEvent(new CustomEvent('vsp:rid-changed', { detail: { rid: rid } }));
    } catch (e) {}

    // optional: jump to dashboard so user sees KPI for selected run
    if (opts && opts.gotoDashboard) {
      try { location.hash = '#dashboard'; } catch (e) {}
      try { window.dispatchEvent(new Event('hashchange')); } catch (e) {}
    }
    return true;
  }

  function mkUseRidBtn(rid){
    rid = normalizeRidForApi(rid);
    var t = rid ? rid : '';
    return '<button class="vsp-btn vsp-btn-primary" data-vsp-set-rid="' + esc(t) + '" ' +
           'style="padding:8px 10px; border-radius:10px; font-size:12px;">Use RID</button>';
  }

  function wireUseRidButtons(tb){
    if (!tb) return;
    var btns = tb.querySelectorAll('button[data-vsp-set-rid]');
    btns.forEach(function(b){
      b.addEventListener('click', function(ev){
        ev.preventDefault();
        ev.stopPropagation();
        var rid = b.getAttribute('data-vsp-set-rid') || '';
        setCurrentRid(rid, { gotoDashboard: true });
      });
    });
  }
'''
    s = s[:insert_at] + helpers + s[insert_at:]

# 2) add Use RID button into rowActions()
if "mkUseRidBtn(" not in s:
    s = s.replace(
        "return [\n      mkLink(status, 'status_v2'),",
        "return [\n      mkUseRidBtn(rid),\n      mkLink(status, 'status_v2'),"
    )

# 3) highlight selected rid + wire buttons after render
# find applyFilter() block and after tb.innerHTML = ...; add wireUseRidButtons(tb);
if "wireUseRidButtons(tb);" not in s:
    s = re.sub(
        r"(tb\.innerHTML\s*=\s*filtered\.map\([\s\S]*?\)\.join\(''\);\s*)",
        r"\1\n      wireUseRidButtons(tb);\n",
        s,
        count=1
    )

# 4) highlight selected row by comparing rid with current
# add a class/style in row render (simple background tint)
if "VSP_RUNS_ROW_HILITE_V1" not in s:
    s = s.replace(
        "return '' +\n          '<tr style=\"border-bottom:1px solid rgba(255,255,255,.06); font-size:13px;\">' +",
        "var cur = getCurrentRid();\n        var isCur = (normalizeRidForApi(rid) && (normalizeRidForApi(rid) === cur));\n\n        return '' +\n          '<tr style=\"border-bottom:1px solid rgba(255,255,255,.06); font-size:13px; ' + (isCur ? 'background:rgba(56,189,248,.06);' : '') + '\">' +\n          '<!-- VSP_RUNS_ROW_HILITE_V1 -->' +"
    )

p.write_text(s, encoding="utf-8")
print("[OK] patched runs tab: click Use RID -> set VSP_CURRENT_RID + jump dashboard")
PY

echo "[OK] patched $F"
echo "[HINT] restart UI then hard refresh (Ctrl+Shift+R)"
