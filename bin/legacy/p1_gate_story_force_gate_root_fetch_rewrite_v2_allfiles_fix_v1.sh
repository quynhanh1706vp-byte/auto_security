#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# candidates: all gate story js + bundles
mapfile -t CANDS < <(
  { find static/js -maxdepth 1 -type f -name 'vsp_dashboard_gate_story*.js' -print 2>/dev/null; \
    find static/js -maxdepth 1 -type f -name 'vsp_bundle_commercial_v*.js' -print 2>/dev/null; } | sort -u
)

[ "${#CANDS[@]}" -gt 0 ] || { echo "[ERR] no candidate js found under static/js"; exit 2; }

for f in "${CANDS[@]}"; do
  cp -f "$f" "${f}.bak_force_gate_root_rewrite_v2_${TS}"
  echo "[BACKUP] ${f}.bak_force_gate_root_rewrite_v2_${TS}"
done

LIST="/tmp/vsp_gate_rewrite_v2_files_${TS}.txt"
printf "%s\n" "${CANDS[@]}" > "$LIST"
echo "[INFO] list=$LIST files=$(wc -l < "$LIST" | tr -d ' ')"

python3 - "$LIST" <<'PY'
from pathlib import Path
import re, textwrap, sys

list_path = Path(sys.argv[1])
files = [line.strip() for line in list_path.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]

marker = "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2"

patch = textwrap.dedent(r"""
/* VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2
 * Force gate fetch to use rid_latest_gate_root and path=run_gate_summary.json.
 * Hooks BOTH fetch + XMLHttpRequest.
 */
(()=> {
  if (window.__vsp_gate_fetch_force_gate_root_v2) return;
  window.__vsp_gate_fetch_force_gate_root_v2 = true;

  const LS_GATE_ROOT = 'vsp_rid_latest_gate_root_v1';
  const LS_LATEST    = 'vsp_rid_latest_v1';

  function _log(){ try{ console.log.apply(console, arguments); }catch(_){ } }

  async function getGateRootRid(){
    try{
      if (window.vsp_rid_latest_gate_root && String(window.vsp_rid_latest_gate_root).trim()){
        return String(window.vsp_rid_latest_gate_root).trim();
      }
      const ls = localStorage.getItem(LS_GATE_ROOT);
      if (ls && String(ls).trim()){
        window.vsp_rid_latest_gate_root = String(ls).trim();
        return window.vsp_rid_latest_gate_root;
      }
      const r = await fetch('/api/vsp/runs?limit=5', {cache:'no-store'});
      const j = await r.json().catch(()=>null);
      const rid = (j && (j.rid_latest_gate_root || j.rid_latest_gate || j.rid_latest)) ? String(j.rid_latest_gate_root || j.rid_latest_gate || j.rid_latest).trim() : '';
      if (rid){
        window.vsp_rid_latest_gate_root = rid;
        try{ localStorage.setItem(LS_GATE_ROOT, rid); }catch(_){}
        try{ localStorage.setItem(LS_LATEST, rid); }catch(_){}
      }
      return rid || '';
    }catch(_){
      return '';
    }
  }

  function isGatePath(path){
    path = (path||"").trim();
    return (
      path === 'run_gate.json' ||
      path === 'run_gate_summary.json' ||
      path === 'reports/run_gate.json' ||
      path === 'reports/run_gate_summary.json'
    );
  }

  function rewriteUrl(u, rid){
    try{
      const url = new URL(u, window.location.origin);
      if (!url.pathname.includes('/api/vsp/run_file_allow')) return u;
      const path = (url.searchParams.get('path')||'').trim();
      if (!isGatePath(path)) return u;

      url.searchParams.set('path', 'run_gate_summary.json');
      if (rid && rid.trim()) url.searchParams.set('rid', rid.trim());
      return url.toString();
    }catch(_){
      return u;
    }
  }

  // ---- hook fetch ----
  const _origFetch = window.fetch ? window.fetch.bind(window) : null;
  if (_origFetch){
    window.fetch = async function(input, init){
      try{
        const u = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
        if (u && u.includes('/api/vsp/run_file_allow') && u.includes('path=')){
          const rid = await getGateRootRid();
          const u2 = rewriteUrl(u, rid);
          if (u2 !== u){
            _log("[GateStoryV1][%s] fetch rewrite => %s", "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2", u2);
            if (typeof input === 'string') input = u2;
            else input = new Request(u2, input);
          }
        }
      }catch(_){}
      return _origFetch(input, init);
    };
  }

  // ---- hook XHR ----
  try{
    const _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url){
      try{
        if (url && String(url).includes('/api/vsp/run_file_allow') && String(url).includes('path=')){
          const u = String(url);
          let rid = '';
          try{ rid = (window.vsp_rid_latest_gate_root || localStorage.getItem(LS_GATE_ROOT) || '').trim(); }catch(_){}
          const u2 = rewriteUrl(u, rid || '');
          if (u2 !== u){
            _log("[GateStoryV1][%s] xhr rewrite => %s", "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2", u2);
            url = u2;
          }
        }
      }catch(_){}
      return _open.apply(this, arguments);
    };
  }catch(_){}

  _log("[GateStoryV1][%s] installed", "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2");
})();
""").lstrip("\n")

def should_patch(txt: str) -> bool:
    return (
        "GateStoryV1" in txt or
        "VSP_P1_GATE_ROOT_PICK" in txt or
        "/api/vsp/run_file_allow" in txt or
        "run_file_allow" in txt
    )

patched = 0
skipped = 0

for fp in files:
    p = Path(fp)
    if not p.exists():
        skipped += 1
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        skipped += 1
        continue
    if not should_patch(s):
        skipped += 1
        continue
    p.write_text(patch + "\n" + s, encoding="utf-8")
    print("[OK] patched:", fp)
    patched += 1

print("[DONE] patched=", patched, "skipped=", skipped)
PY

echo
echo "== GREP marker =="
grep -RIn --exclude='*.bak_*' "VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2" static/js | head -n 30 || true

echo
echo "== NEXT (browser) =="
echo "1) Console run:"
echo "   localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "2) Ctrl+F5 /vsp5"
echo "Expected console:"
echo "   [GateStoryV1][VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2] installed"
echo "   [GateStoryV1][VSP_P1_GATE_FETCH_FORCE_GATE_ROOT_V2] fetch rewrite => ...rid=VSP_CI_RUN_...&path=run_gate_summary.json"
