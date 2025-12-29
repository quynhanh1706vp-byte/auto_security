#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_tabs5_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p963j_${TS}"
mkdir -p "$OUT"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="/* VSP_P963J_SYNC_LEGACY_KPI */"
if marker in s:
    print("[OK] P963J already applied")
    raise SystemExit(0)

addon = r'''
''' + marker + r'''
;(function(){
  try{
    function norm(t){ return String(t||'').replace(/\s+/g,' ').trim().toUpperCase(); }
    function isNumText(t){ return /^\d+$/.test(String(t||'').trim()); }

    function findNumericTarget(scope){
      if(!scope) return null;
      // prefer common numeric nodes
      var cand = scope.querySelector('.kpi-num,.num,.value,.count,strong,b,span,div');
      if (cand && isNumText(cand.textContent)) return cand;

      // fallback: first node in scope that is purely digits
      var nodes = scope.querySelectorAll('strong,b,span,div');
      for (var i=0;i<nodes.length;i++){
        if (isNumText(nodes[i].textContent)) return nodes[i];
      }
      return null;
    }

    function setByLabel(label, value){
      var L = norm(label);
      var nodes = document.querySelectorAll('div,span,strong,b,h1,h2,h3,h4,h5');
      for (var i=0;i<nodes.length;i++){
        var t = norm(nodes[i].textContent);
        if (t === L || t.startsWith(L+' ') || t.endsWith(' '+L)) {
          var card = nodes[i].closest('.kpi-card,.card,.box,.panel,.stat,.metric') || nodes[i].parentElement;
          if (!card) continue;

          // try sibling next
          var sib = nodes[i].nextElementSibling;
          if (sib && isNumText(sib.textContent)) { sib.textContent = String(value); return true; }

          // else search inside card
          var num = findNumericTarget(card);
          if (num) { num.textContent = String(value); return true; }
        }
      }
      return false;
    }

    function syncLegacyStrip(counts){
      var total = 0;
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){ total += (counts[k]||0); });

      var ok = 0;
      ok += setByLabel('TOTAL', total) ? 1 : 0;
      ok += setByLabel('CRITICAL', counts.CRITICAL||0) ? 1 : 0;
      ok += setByLabel('HIGH', counts.HIGH||0) ? 1 : 0;
      ok += setByLabel('MEDIUM', counts.MEDIUM||0) ? 1 : 0;
      ok += setByLabel('LOW', counts.LOW||0) ? 1 : 0;
      ok += setByLabel('INFO', counts.INFO||0) ? 1 : 0;
      ok += setByLabel('TRACE', counts.TRACE||0) ? 1 : 0;

      return ok;
    }

    function hideZeroLegacyStrip(){
      // try to find a strip that contains labels TOTAL/CRITICAL/HIGH/MEDIUM/LOW/INFO and all numbers are 0
      var text = document.body ? document.body.innerText || '' : '';
      if (!text) return false;

      var containers = document.querySelectorAll('.kpi-strip,.kpi-row,.stats,.metrics,.row,section,div');
      for (var i=0;i<containers.length;i++){
        var c = containers[i];
        var tt = norm(c.textContent);
        if (!(tt.includes('TOTAL') && tt.includes('CRITICAL') && tt.includes('HIGH') && tt.includes('MEDIUM'))) continue;

        // count numeric nodes in this container
        var nums = c.querySelectorAll('strong,b,span,div');
        var seen = 0, zeros = 0;
        for (var j=0;j<nums.length;j++){
          var v = String(nums[j].textContent||'').trim();
          if (!/^\d+$/.test(v)) continue;
          seen += 1;
          if (v === '0') zeros += 1;
        }
        if (seen >= 6 && zeros === seen) {
          c.style.display = 'none';
          console.log('[P963J] hidden legacy KPI strip (all zeros)');
          return true;
        }
      }
      return false;
    }

    // Hook into the existing P963I flow by re-running after KPI v2 fetch has updated the CIO block.
    // If counts exist on window.__VSP_KPI_V2_COUNTS__ (we set below), use it.
    function run(){
      var counts = window.__VSP_KPI_V2_COUNTS__ || null;
      if (!counts) { hideZeroLegacyStrip(); return; }
      var n = syncLegacyStrip(counts);
      console.log('[P963J] sync legacy KPI ok=', n);
      if (n < 3) hideZeroLegacyStrip();
    }

    // expose a setter so P963I can store counts
    window.__VSP_P963J_SET_COUNTS__ = function(counts){
      window.__VSP_KPI_V2_COUNTS__ = counts || null;
      setTimeout(run, 0);
      setTimeout(run, 300);
      setTimeout(run, 900);
    };

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
    else setTimeout(run, 0);
  }catch(e){
    console.warn('[P963J] init error', e);
  }
})();
'''
# also patch P963I addon to call __VSP_P963J_SET_COUNTS__ if present
if "/* VSP_P963I_KPI_V2 */" in s and "__VSP_P963J_SET_COUNTS__" not in s:
    s = s.replace(
        "ensureCioBlock(j.counts||{}, {rid: rid, n: j.n||0});",
        "ensureCioBlock(j.counts||{}, {rid: rid, n: j.n||0});\n          if (window.__VSP_P963J_SET_COUNTS__) window.__VSP_P963J_SET_COUNTS__(j.counts||{});"
    )

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended P963J and wired P963I->P963J setter")
PY

echo "== [gate] JS strict gate (best-effort) =="
bash bin/p934_js_syntax_strict_gate.sh 2>/dev/null || true

echo "== restart+wait =="
sudo -v || true
sudo systemctl restart "$SVC" || true
VSP_UI_BASE="$BASE" MAX_WAIT=45 bash bin/ops/ops_restart_wait_ui_v1.sh

echo "[PASS] P963J applied. Open /vsp5?rid=... then Ctrl+Shift+R"
