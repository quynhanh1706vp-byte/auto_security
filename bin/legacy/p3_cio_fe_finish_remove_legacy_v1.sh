#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re, time

ts=time.strftime("%Y%m%d_%H%M%S")
root=Path("static/js")

def bak(p:Path, orig:str):
    b=p.with_name(p.name+f".bak_cio_finish_{ts}")
    b.write_text(orig, encoding="utf-8")
    print("[BACKUP]", b.name)

def ensure_cio_helper(s:str)->str:
    if "__VSP_CIO_HELPER_V1" in s:
        return s
    helper = r'''
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = ()=>document.visibilityState === "visible";
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.api = {
      ridLatestV3: ()=>"/api/vsp/rid_latest_v3",
      dashboardV3: (rid)=> rid ? `/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}` : "/api/vsp/dashboard_v3",
      runsV3: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gateV3: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsV3: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifactV3: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();
'''
    m=re.search(r'(?m)^[\'"]use strict[\'"];\s*$', s)
    if m:
        nl=s.find("\n", m.end())
        return s[:nl+1] + helper + "\n" + s[nl+1:]
    return helper + "\n" + s

def gate_console(s:str)->str:
    # Gate console.log/debug/info behind __VSP_CIO.debug (keep warn/error)
    s=re.sub(r'(?m)^\s*console\.(log|debug|info)\s*\(',
             r'if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.\1(',
             s)
    return s

def patch_dashboard_luxe(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    s=ensure_cio_helper(s)
    s=gate_console(s)

    # rid_latest -> rid_latest_v3
    s=s.replace('/api/vsp/rid_latest', '/api/vsp/rid_latest_v3')

    # run_gate_summary_v1 -> run_gate_v3
    s=s.replace('/api/vsp/run_gate_summary_v1?rid=', '/api/vsp/run_gate_v3?rid=')

    # trend_v1 / top_findings_v1: replace with dashboard_v3 + findings_v3 (client-side normalize)
    if "/api/vsp/trend_v1" in s or "/api/vsp/top_findings_v1" in s:
        # Inject minimal adapters once
        if "__VSP_CIO_ADAPTERS_V1" not in s:
            adapter = r'''
// __VSP_CIO_ADAPTERS_V1
async function __cioGetJson(url){
  const r = await fetch(url, {cache:"no-store"});
  if(!r.ok) throw new Error("http_"+r.status);
  return await r.json();
}
async function __cioTrendFromDashboardV3(rid){
  const j = await __cioGetJson(window.__VSP_CIO.api.dashboardV3(rid));
  // dashboard_v3 returns {trend:[{label,total,ts,rid}...]} (or empty)
  return (j && (j.trend || j.points) ) || [];
}
async function __cioTopFromFindingsV3(rid, limit){
  const j = await __cioGetJson(window.__VSP_CIO.api.findingsV3(rid, limit||10, 0));
  const items = (j && (j.items || j.findings || [])) || [];
  // If API returns page items, use as "top"
  return items.slice(0, limit||10);
}
'''
            # place near top
            s = adapter + "\n" + s

        # replace calls (best-effort string-based)
        s = s.replace('/api/vsp/trend_v1?path=', '/* CIO */ __cioTrendFromDashboardV3(rid)')
        s = re.sub(r'fetchJson\("/api/vsp/trend_v1\?path="[^)]*\)',
                   '__cioTrendFromDashboardV3(rid)', s)

        s = re.sub(r'fetchJson\("/api/vsp/top_findings_v1\?rid="\s*\+\s*encodeURIComponent\(rid\)\s*\+\s*"&limit=\d+"\)',
                   '__cioTopFromFindingsV3(rid, 10)', s)
        s = re.sub(r'fetchJson\("/api/vsp/top_findings_v1\?limit=\d+"\)',
                   '__cioTopFromFindingsV3(rid, 10)', s)

        # fallback: raw jget(...) usage
        s = re.sub(r'jget\("/api/vsp/trend_v1\?path=.*?"\)', '__cioTrendFromDashboardV3(rid)', s)
        s = re.sub(r'jget\("/api/vsp/top_findings_v1\?limit=.*?"\)', '__cioTopFromFindingsV3(rid, 10)', s)

    if s != orig:
        bak(p, orig); p.write_text(s, encoding="utf-8"); print("[OK] patched", p.name)

def patch_dashboard_render(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    s=ensure_cio_helper(s)
    s=gate_console(s)

    # dashboard legacy -> dashboard_v3
    s=s.replace("/api/vsp/dashboard", "/api/vsp/dashboard_v3")

    # runs_index_v3 -> runs_v3 with tolerant parsing
    if "/api/vsp/runs_index_v3" in s:
        s=s.replace("/api/vsp/runs_index_v3", "/api/vsp/runs_v3?limit=80&offset=0")
        if "__cioNormalizeRunsV3" not in s:
            helper = r'''
function __cioNormalizeRunsV3(j){
  // Accept {runs:[...]} or legacy-like shapes
  if(!j) return [];
  if(Array.isArray(j.runs)) return j.runs;
  if(Array.isArray(j.items)) return j.items;
  if(Array.isArray(j.data)) return j.data;
  return [];
}
'''
            s = helper + "\n" + s
            # best-effort: replace "data.runs" occurrences
            s = re.sub(r'(\b)(data|j)\.runs\b', r'__cioNormalizeRunsV3(\2)', s)

    if s != orig:
        bak(p, orig); p.write_text(s, encoding="utf-8"); print("[OK] patched", p.name)

def patch_security_bundle(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    s=ensure_cio_helper(s)
    s=gate_console(s)
    if s != orig:
        bak(p, orig); p.write_text(s, encoding="utf-8"); print("[OK] patched", p.name)

def patch_settings_render(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    s=ensure_cio_helper(s)
    s=gate_console(s)
    # Remove “log JSON lên console” hint text (CIO clean)
    s=s.replace("Hiện tại Save sẽ log JSON cấu hình lên console để bạn kiểm tra.", "Save sẽ lưu cấu hình theo policy hiện hành.")
    if s != orig:
        bak(p, orig); p.write_text(s, encoding="utf-8"); print("[OK] patched", p.name)

def patch_kpi_toolstrip_v2(p:Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    s=ensure_cio_helper(s)
    s=gate_console(s)
    # Block plumbing-y listing call /api/vsp/run_file?...name=reports/ unless debug enabled
    if "/api/vsp/run_file?rid=" in s and "reports/" in s:
        s=re.sub(r'const\s+summary\s*=\s*await\s+getJson\(`\/api\/vsp\/run_file\?rid=\$\{encodeURIComponent\(rid\)\}&name=\$\{encodeURIComponent\("reports\/"\)\}`[^;]*;\s*',
                 'let summary=null; if(window.__VSP_CIO&&window.__VSP_CIO.debug){ summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/")}`, 15000); }\n',
                 s)
    if s != orig:
        bak(p, orig); p.write_text(s, encoding="utf-8"); print("[OK] patched", p.name)

targets = {
  "vsp_dashboard_luxe_v1.js": patch_dashboard_luxe,
  "dashboard_render.js": patch_dashboard_render,
  "security_bundle.js": patch_security_bundle,
  "settings_render_v2.js": patch_settings_render,
  "vsp_dashboard_kpi_toolstrip_v2.js": patch_kpi_toolstrip_v2,
}

for name, fn in targets.items():
    p=root/name
    if p.exists():
        fn(p)
    else:
        print("[SKIP] missing", name)

PY

echo
echo "== [CHECK] Remaining legacy endpoints in active JS (exclude backups) =="
grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' \
  '/api/vsp/run_gate_summary_v1|/api/vsp/top_findings_v1|/api/vsp/trend_v1|/api/vsp/rid_latest[^_v3]|/api/vsp/dashboard[^_v3]' \
  static/js | head -n 120 || echo "[OK] no legacy hot endpoints found"

echo
echo "[DONE] Hard refresh browser (Ctrl+Shift+R). In F12 Network: expect calls mainly to rid_latest_v3 / dashboard_v3 / runs_v3 / run_gate_v3 / findings_v3 / artifact_v3."
