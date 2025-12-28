#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] Target active JS that references plumbing/legacy (excluding backups) =="
grep -RIn --line-number \
  --exclude='*.bak*' --exclude='*.disabled*' \
  '/api/vsp/run_file_allow|/api/vsp/runs\?limit=1|rid_latest_gate_root_v2|run_gate_summary_v1|trend_v1|top_findings_v1|window\.__vsp' \
  static/js | head -n 160 || true
echo

python3 - <<'PY'
from pathlib import Path
import re, time

ts=time.strftime("%Y%m%d_%H%M%S")
root=Path("static/js")

def backup_write(p:Path, orig:str):
    bak=p.with_name(p.name+f".bak_cioharden_{ts}")
    bak.write_text(orig, encoding="utf-8")
    print("[BACKUP]", bak.name)

# Inject a tiny CIO helper (visibility gating + backoff + debug gate) into bundle-ish files
def ensure_helper(s:str)->str:
    if "__VSP_CIO_HELPER_V1" in s:
        return s
    helper = r'''
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = function(){ return document.visibilityState === "visible"; };
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.backoff = async function(fn, opt){
      opt = opt || {};
      let delay = opt.delay || 800;
      const maxDelay = opt.maxDelay || 8000;
      const maxTries = opt.maxTries || 6;
      for(let i=0;i<maxTries;i++){
        if(!window.__VSP_CIO.visible()){
          await window.__VSP_CIO.sleep(600);
          continue;
        }
        try { return await fn(); }
        catch(e){
          if(window.__VSP_CIO.debug) console.warn("[VSP] backoff retry", i+1, e);
          await window.__VSP_CIO.sleep(delay);
          delay = Math.min(maxDelay, delay*2);
        }
      }
      throw new Error("backoff_exhausted");
    };
    window.__VSP_CIO.api = {
      ridLatest: ()=>"/api/vsp/rid_latest_v3",
      runs: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gate: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsPage: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifact: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();
'''
    # Put helper near top after "use strict" if present
    m=re.search(r'(?m)^[\'"]use strict[\'"];\s*$', s)
    if m:
        nl=s.find("\n", m.end())
        return s[:nl+1] + helper + "\n" + s[nl+1:]
    return helper + "\n" + s

def patch_file(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s

    # Only patch active JS (not backups)
    # 1) Ensure helper exists
    if any(k in s for k in ["/api/vsp/run_file_allow","/api/vsp/runs?limit=1","window.__vsp"]):
        s=ensure_helper(s)

    # 2) Remove legacy poll "runs?limit=1" => rid_latest_v3
    s=s.replace("/api/vsp/runs?limit=1", "/api/vsp/rid_latest_v3")

    # 3) Replace run_file_allow usage broadly:
    #    - If it was used for downloads, map to artifact_v3 kinds (best-effort)
    #    - If it was used to read findings/gate, map to findings_v3 / run_gate_v3
    if "/api/vsp/run_file_allow" in s:
        # gate summary fetch pattern
        s=re.sub(r'/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=run_gate_summary\.json',
                 '/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid)}', s)

        # findings file fetch patterns -> findings_v3 page
        s=re.sub(r'/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*findings[^)]*\)\}(?:&limit=\d+)?',
                 '/api/vsp/findings_v3?rid=${encodeURIComponent(rid)}&limit=500&offset=0', s)

        # remaining run_file_allow -> artifact_v3 (then try infer kind by path string)
        s=s.replace("/api/vsp/run_file_allow", "/api/vsp/artifact_v3")

        # infer kind by common substrings near query
        s=re.sub(r'/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*pdf[^)]*\)\}[^"\']*',
                 '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=pdf&download=1', s)
        s=re.sub(r'/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*html[^)]*\)\}[^"\']*',
                 '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=html&download=1', s)
        s=re.sub(r'/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*csv[^)]*\)\}[^"\']*',
                 '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=csv&download=1', s)
        s=re.sub(r'/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*tgz[^)]*\)\}[^"\']*',
                 '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=tgz&download=1', s)
        s=re.sub(r'/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*zip[^)]*\)\}[^"\']*',
                 '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=zip&download=1', s)

    # 4) Debug leak scrub:
    #    - disable noisy window.__vsp* exports unless debug enabled
    if "window.__vsp" in s:
        # wrap assignments with if (__VSP_CIO.debug)
        s=re.sub(r'(?m)^\s*window\.__vsp([A-Za-z0-9_]+)\s*=\s*', r'if(window.__VSP_CIO && window.__VSP_CIO.debug){ window.__vsp\1 = ', s)
        # close braces at end of line for the wrapped ones (best-effort)
        s=re.sub(r'(?m)^(if\(window\.__VSP_CIO.*?=\s*.*?;)\s*$', r'\1 }', s)

    # 5) Remove obvious internal strings (do not break logic)
    for leak in ["findings_unified.json","reports/findings_unified.json","run_gate_summary.json","reports/run_gate_summary.json"]:
        s=s.replace(leak,"")

    if s != orig:
        backup_write(p, orig)
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p.name)

# Patch only files likely involved (fast)
for p in sorted(root.glob("*.js")):
    if p.name.endswith(".bak") or ".bak_" in p.name:  # just in case
        continue
    txt=p.read_text(encoding="utf-8", errors="replace")
    if any(k in txt for k in ["/api/vsp/run_file_allow","/api/vsp/runs?limit=1","window.__vsp","trend_v1","top_findings_v1","run_gate_summary_v1","rid_latest_gate_root_v2"]):
        patch_file(p)
PY

echo
echo "== [1] Post-check: active JS must NOT contain run_file_allow =="
if grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '/api/vsp/run_file_allow' static/js >/dev/null; then
  echo "[ERR] still has run_file_allow in active JS:"
  grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '/api/vsp/run_file_allow' static/js | head -n 80
  exit 3
else
  echo "[OK] no run_file_allow in active JS"
fi

echo
echo "== [2] Post-check: active JS should not call runs?limit=1 =="
if grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '/api/vsp/runs\?limit=1' static/js >/dev/null; then
  echo "[WARN] still has runs?limit=1:"
  grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '/api/vsp/runs\?limit=1' static/js | head -n 60
else
  echo "[OK] no runs?limit=1 in active JS"
fi

echo
echo "[DONE] Now hard-refresh browser (Ctrl+Shift+R). CIO check: F12->Network should be calm."
