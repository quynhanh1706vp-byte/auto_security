#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_force_gate_root_fetch_${TS}"
echo "[BACKUP] ${F}.bak_force_gate_root_fetch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

patch = textwrap.dedent(r"""
/* VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V1
 * Force any gate fetch via /api/vsp/run_file_allow to use rid_latest_gate_root (prefer CI run)
 * and prefer path=run_gate_summary.json to avoid 403/404 + SUMMARY.txt surprises.
 */
(()=> {
  if (window.__vsp_gate_fetch_force_gate_root_v1) return;
  window.__vsp_gate_fetch_force_gate_root_v1 = true;

  const LS_GATE_ROOT = 'vsp_rid_latest_gate_root_v1';
  const LS_LATEST    = 'vsp_rid_latest_v1';

  const _origFetch = window.fetch ? window.fetch.bind(window) : null;
  if (!_origFetch) return;

  async function getGateRootRid(){
    try{
      // 0) in-memory
      if (window.vsp_rid_latest_gate_root && String(window.vsp_rid_latest_gate_root).trim()){
        return String(window.vsp_rid_latest_gate_root).trim();
      }
      // 1) localStorage
      const ls = localStorage.getItem(LS_GATE_ROOT);
      if (ls && String(ls).trim()){
        window.vsp_rid_latest_gate_root = String(ls).trim();
        return window.vsp_rid_latest_gate_root;
      }
      // 2) ask API
      const r = await _origFetch('/api/vsp/runs?limit=5', {cache:'no-store'});
      const j = await r.json().catch(()=>null);
      const rid = (j && (j.rid_latest_gate_root || j.rid_latest_gate || j.rid_latest)) ? String(j.rid_latest_gate_root || j.rid_latest_gate || j.rid_latest).trim() : '';
      if (rid){
        window.vsp_rid_latest_gate_root = rid;
        try { localStorage.setItem(LS_GATE_ROOT, rid); } catch(_){}
        // also keep latest for other parts
        try { localStorage.setItem(LS_LATEST, rid); } catch(_){}
      }
      return rid || '';
    }catch(_){
      return '';
    }
  }

  function rewriteGateUrl(u, rid){
    try{
      const url = new URL(u, window.location.origin);
      if (!url.pathname.includes('/api/vsp/run_file_allow')) return u;

      const path = (url.searchParams.get('path') || '').trim();
      const isGate = (path === 'run_gate.json' || path === 'run_gate_summary.json'
                      || path === 'reports/run_gate.json' || path === 'reports/run_gate_summary.json');
      if (!isGate) return u;

      // force preferred path
      url.searchParams.set('path', 'run_gate_summary.json');

      if (rid && rid.trim()){
        url.searchParams.set('rid', rid.trim());
      }
      return url.toString();
    }catch(_){
      return u;
    }
  }

  window.fetch = async function(input, init){
    try{
      const u = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
      if (u && u.includes('/api/vsp/run_file_allow') && u.includes('path=')){
        // only rewrite gate-related paths
        const rid = await getGateRootRid();
        const u2 = rewriteGateUrl(u, rid);
        if (u2 !== u){
          console.log("[GateStoryV1][%s] fetch rewrite =>", "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V1", u2);
          if (typeof input === 'string') input = u2;
          else input = new Request(u2, input);
        }
      }
    }catch(_){}
    return _origFetch(input, init);
  };

  console.log("[GateStoryV1][%s] installed", "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V1");
})();
""").lstrip("\n")

# Put patch at top (after possible shebang/comments), safest: insert before first IIFE or at file start.
s2 = patch + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", marker, "->", p)
PY

# optional syntax check if node exists
if command -v node >/dev/null 2>&1; then
  node --check "$F" && echo "[OK] node --check $F"
fi

echo
echo "== NEXT =="
echo "Browser console:"
echo "  localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "Then Ctrl+F5 /vsp5"
