#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_sidebar_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p479_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p479_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_sidebar_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P479_DEMO_MODE_DASHBOARD_DS_V1"
if MARK in s:
    print("[OK] already patched P479")
else:
    add=r"""

/* VSP_P479_DEMO_MODE_DASHBOARD_DS_V1 */
(function(){
  if (window.__VSP_P479__) return;
  window.__VSP_P479__ = 1;

  function isDemo(){ return localStorage.getItem("VSP_DEMO_RUNS")==="1"; }

  function ensureCss(){
    if(document.getElementById("vsp_p479_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p479_css";
    st.textContent=`
#vsp_p479_demo_btn{
  border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:6px 10px;
  font-size:12px;
}
#vsp_p479_demo_btn.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
#vsp_p479_demo_badge{
  display:inline-flex;align-items:center;gap:6px;
  padding:4px 10px;border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  font-size:12px;opacity:.92;
}
#vsp_p479_demo_badge.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
`;
    document.head.appendChild(st);
  }

  function addDemoToggleToTitlebar(){
    ensureCss();
    const tb = document.getElementById("vsp_p474_titlebar");
    if(!tb) return;
    const r = tb.querySelector(".r");
    if(!r) return;
    if(document.getElementById("vsp_p479_demo_btn")) return;

    const badge=document.createElement("span");
    badge.id="vsp_p479_demo_badge";
    badge.textContent = isDemo() ? "DEMO: ON" : "DEMO: OFF";
    if(isDemo()) badge.classList.add("on");

    const btn=document.createElement("button");
    btn.id="vsp_p479_demo_btn";
    btn.textContent = isDemo() ? "Turn DEMO OFF" : "Turn DEMO ON";
    if(isDemo()) btn.classList.add("on");
    btn.onclick=()=>{
      if(isDemo()) localStorage.removeItem("VSP_DEMO_RUNS");
      else localStorage.setItem("VSP_DEMO_RUNS","1");
      location.reload();
    };

    // put near env badge
    r.insertBefore(btn, r.firstChild);
    r.insertBefore(badge, r.firstChild);
  }

  // ---- DEMO payloads (superset keys to avoid schema mismatch) ----
  function demoTopFindings(){
    const items = [
      { severity:"HIGH", title:"Hardcoded secret in repo", tool:"gitleaks", file:"ui/vsp_demo_app.py", cwe:"CWE-798" },
      { severity:"MEDIUM", title:"SQL injection risk (string concat)", tool:"semgrep", file:"api/query.py", cwe:"CWE-89" },
      { severity:"LOW", title:"Missing security headers", tool:"bandit", file:"wsgi_vsp_ui_gateway.py", cwe:"CWE-693" },
      { severity:"INFO", title:"Outdated package version", tool:"trivy", file:"requirements.txt", cwe:"CWE-1104" },
    ];
    return {
      ver:"demo_top_findings",
      rid:"RUN_DEMO_001",
      total: items.length,
      items: items,
      findings: items,
      top_findings: items,
    };
  }

  function demoTrend(){
    const now = Date.now();
    const pts = [];
    for(let i=9;i>=0;i--){
      pts.push({ t: new Date(now - i*86400_000).toISOString().slice(0,10),
                 critical: (i%7===0)?1:0, high: (i%3)+1, medium: (i%4)+2, low: (i%5)+3 });
    }
    return {
      ver:"demo_trend",
      points: pts,
      series: pts,
      items: pts,
    };
  }

  function demoDatasource(){
    const rows = [
      { tool:"semgrep", severity:"MEDIUM", title:"XSS via innerHTML", file:"static/js/vsp_ui.js", rule:"js-xss", cwe:"CWE-79" },
      { tool:"kics", severity:"LOW", title:"Terraform S3 bucket public ACL", file:"iac/main.tf", rule:"S3PublicACL", cwe:"CWE-200" },
      { tool:"trivy", severity:"HIGH", title:"CVE-2024-xxxx in openssl", file:"sbom/syft.json", rule:"CVE", cwe:"CWE-1104" },
    ];
    return {
      ver:"demo_datasource",
      total: rows.length,
      items: rows,
      rows: rows,
      findings: rows,
    };
  }

  // ---- Fetch hook (best-effort) ----
  function installFetchHook(){
    if(window.__VSP_P479_FETCH_HOOK__) return;
    window.__VSP_P479_FETCH_HOOK__ = 1;

    // Keep a stable base fetch (in case other patches wrap fetch later, that's OK)
    const baseFetch = window.fetch;

    window.fetch = async function(input, init){
      try{
        const url = (typeof input==="string") ? input : (input && input.url) ? input.url : "";
        if(isDemo()){
          const u = url.toLowerCase();
          // dashboard sources (broad match)
          if(u.includes("/api/vsp/top_findings") || u.includes("top_findings_v")){
            return new Response(JSON.stringify(demoTopFindings()), {status:200, headers:{"Content-Type":"application/json"}});
          }
          if(u.includes("/api/vsp/trend_v1") || u.includes("/api/vsp/trend")){
            return new Response(JSON.stringify(demoTrend()), {status:200, headers:{"Content-Type":"application/json"}});
          }
          if(u.includes("/api/vsp/datasource") || u.includes("/api/vsp/data_source")){
            return new Response(JSON.stringify(demoDatasource()), {status:200, headers:{"Content-Type":"application/json"}});
          }
        }
      }catch(e){}
      return baseFetch.apply(this, arguments);
    };
  }

  function boot(){
    try{
      installFetchHook();
      // titlebar may be injected by P474; retry a few times
      let n=0;
      const t=setInterval(()=>{
        addDemoToggleToTitlebar();
        if(document.getElementById("vsp_p479_demo_btn") || n++>10) clearInterval(t);
      }, 150);
      console && console.log && console.log("[P479] demo mode hook ready (DEMO=" + (isDemo()?"ON":"OFF") + ")");
    }catch(e){
      console && console.warn && console.warn("[P479] err", e);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P479 into vsp_c_sidebar_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P479 done. Reopen /c/dashboard then Ctrl+Shift+R (toggle DEMO on titlebar)" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
