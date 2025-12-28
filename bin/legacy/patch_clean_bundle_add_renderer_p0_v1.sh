#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_add_renderer_${TS}"
echo "[BACKUP] $F.bak_add_renderer_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_CLEAN_RENDERER_P0_V1"
if MARK in s:
    print("[OK] renderer already present")
    raise SystemExit(0)

insert = r"""
  // ---------- {MARK}: minimal UI renderer (avoid blank page) ----------
  function ensureShell(){
    // if template already provides panes, do nothing
    if (document.querySelector('#vsp-dashboard-main') || document.querySelector('#vspShell')) return;

    const shell=document.createElement('div');
    shell.id='vspShell';
    shell.style.cssText="display:flex; min-height:100vh; background:#0b1020; color:#e9eef7; font-family:system-ui, -apple-system, Segoe UI, Roboto, sans-serif;";

    const nav=document.createElement('div');
    nav.id='vspNav';
    nav.style.cssText="width:260px; padding:18px 14px; border-right:1px solid rgba(255,255,255,.08); background:rgba(10,14,26,.96);";
    nav.innerHTML = `
      <div style="font-weight:850; font-size:16px; letter-spacing:.02em;">VersaSecure Platform</div>
      <div style="opacity:.7; font-size:12px; margin-top:2px;">VSP 2025 • UI gateway 8910</div>
      <div style="margin-top:14px; opacity:.85; font-size:12px;">RID: <span id="vspRidTop">(none)</span></div>
      <div style="display:flex; gap:8px; margin-top:12px; flex-wrap:wrap;">
        <button id="btnExportHTML" style="all:unset; cursor:pointer; padding:8px 10px; border:1px solid rgba(255,255,255,.10); border-radius:10px; background:rgba(255,255,255,.06); font-weight:750; font-size:12px;">Export HTML</button>
        <button id="btnExportTGZ"  style="all:unset; cursor:pointer; padding:8px 10px; border:1px solid rgba(255,255,255,.10); border-radius:10px; background:rgba(255,255,255,.06); font-weight:750; font-size:12px;">Export TGZ</button>
        <button id="btnVerifySHA"  style="all:unset; cursor:pointer; padding:8px 10px; border:1px solid rgba(255,255,255,.10); border-radius:10px; background:rgba(255,255,255,.06); font-weight:750; font-size:12px;">Verify SHA</button>
      </div>
      <div style="margin-top:18px; display:grid; gap:8px;">
        ${['dashboard','runs','datasource','settings','rules'].map(k=>`
          <a href="#${k}" data-tab="${k}" style="text-decoration:none; color:#e9eef7; padding:10px 10px; border-radius:12px; border:1px solid rgba(255,255,255,.08); background:rgba(255,255,255,.03); display:flex; justify-content:space-between; font-weight:750;">
            <span>${k[0].toUpperCase()+k.slice(1)}</span><span style="opacity:.55;">›</span>
          </a>`).join('')}
      </div>
    `;

    const main=document.createElement('div');
    main.id='vspMain';
    main.style.cssText="flex:1; padding:20px 22px;";

    const panes=document.createElement('div');
    panes.innerHTML = `
      <div id="vsp-dashboard-main"></div>
      <div id="vsp-runs-main" style="display:none;"></div>
      <div id="vsp-datasource-main" style="display:none;"></div>
      <div id="vsp-settings-main" style="display:none;"></div>
      <div id="vsp-rules-main" style="display:none;"></div>
    `;
    main.appendChild(panes);

    shell.appendChild(nav);
    shell.appendChild(main);
    document.body.innerHTML = "";
    document.body.appendChild(shell);
  }

  function card(title, bodyHtml){
    return `
      <div style="border:1px solid rgba(255,255,255,.10); background:rgba(255,255,255,.04); border-radius:16px; padding:14px 14px; box-shadow:0 18px 45px rgba(0,0,0,.35);">
        <div style="font-weight:850; font-size:13px; letter-spacing:.06em; opacity:.9;">${title}</div>
        <div style="margin-top:10px; opacity:.9; font-size:12px; line-height:1.35; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; white-space:pre-wrap;">${bodyHtml}</div>
      </div>
    `;
  }

  async function renderDashboard(){
    const host = document.querySelector('#vsp-dashboard-main');
    if(!host) return;
    host.innerHTML = `
      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:14px;">
        <div style="font-size:18px; font-weight:900;">Dashboard</div>
        <button id="btnRefreshDash" style="all:unset; cursor:pointer; padding:8px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(255,255,255,.06); font-weight:800;">Refresh</button>
      </div>
      <div id="dashGrid" style="display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:12px;"></div>
    `;
    const grid = document.querySelector('#dashGrid');
    const data = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now()).catch(()=>({error:true}));
    grid.innerHTML = [
      card('OVERALL (raw)', JSON.stringify(data?.overall||data||{}, null, 2).replace(/</g,'&lt;')),
      card('TOOLS (raw)', JSON.stringify(data?.tools||data?.tools_a||data?.tools_b||{}, null, 2).replace(/</g,'&lt;')),
      card('GATE (raw)', JSON.stringify(data?.gate||data?.gate_overall||{}, null, 2).replace(/</g,'&lt;')),
      card('META (raw)', JSON.stringify({rid:LATEST.rid, run_dir:LATEST.run_dir}, null, 2).replace(/</g,'&lt;')),
    ].join('');
    const btn = document.querySelector('#btnRefreshDash');
    if(btn) btn.onclick = ()=>renderDashboard();
  }

  async function renderRuns(){
    const host = document.querySelector('#vsp-runs-main');
    if(!host) return;
    host.innerHTML = `
      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:14px;">
        <div style="font-size:18px; font-weight:900;">Runs & Reports</div>
        <button id="btnRefreshRuns" style="all:unset; cursor:pointer; padding:8px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.10); background:rgba(255,255,255,.06); font-weight:800;">Refresh</button>
      </div>
      <div id="runsBox"></div>
    `;
    const box = document.querySelector('#runsBox');
    const data = await fetchJson('/api/vsp/runs_index_v3_fs_resolved?ts=' + Date.now()).catch(()=>({error:true}));
    box.innerHTML = card('RUNS (raw)', JSON.stringify(data, null, 2).replace(/</g,'&lt;'));
    const btn = document.querySelector('#btnRefreshRuns');
    if(btn) btn.onclick = ()=>renderRuns();
  }

  function renderSettings(){
    const host = document.querySelector('#vsp-settings-main');
    if(!host) return;
    host.innerHTML = `
      <div style="font-size:18px; font-weight:900; margin-bottom:14px;">Settings</div>
      ${card('Info', 'This is minimal clean UI shell. Your full commercial template can be plugged back later.')}
    `;
  }
  function renderDatasource(){
    const host = document.querySelector('#vsp-datasource-main');
    if(!host) return;
    host.innerHTML = `
      <div style="font-size:18px; font-weight:900; margin-bottom:14px;">Data Source</div>
      ${card('Hint', 'Open Runs & Reports → Export HTML/TGZ to view findings.json.')}
    `;
  }
  function renderRules(){
    const host = document.querySelector('#vsp-rules-main');
    if(!host) return;
    host.innerHTML = `
      <div style="font-size:18px; font-weight:900; margin-bottom:14px;">Rule Overrides</div>
      ${card('Hint', 'Rule Overrides UI will be re-attached as separate module (clean).')}
    `;
  }

  async function bindShellButtons(){
    const html=$('#btnExportHTML'), tgz=$('#btnExportTGZ'), sha=$('#btnVerifySHA');
    const ridTop=$('#vspRidTop');
    async function resolve(){
      await refreshLatest();
      if(ridTop) ridTop.textContent = LATEST.rid || '(none)';
      if(!LATEST.run_dir) throw new Error('No ci_run_dir');
      return LATEST.run_dir;
    }
    if(html) html.onclick = async ()=>{ try{ const rd=await resolve(); window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now()), '_blank'); }catch(e){ toast('Open HTML failed ❌', false); } };
    if(tgz)  tgz.onclick  = async ()=>{ try{ const rd=await resolve(); window.location.href='/api/vsp/export_report_tgz_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now()); }catch(e){ toast('Export TGZ failed ❌', false); } };
    if(sha)  sha.onclick  = async ()=>{ try{ const rd=await resolve(); const j=await fetchJson('/api/vsp/verify_report_sha_v1?run_dir='+encodeURIComponent(rd)+'&ts='+(Date.now())); toast(j&&j.ok?'SHA256 OK ✅':'SHA256 FAIL ❌', !!(j&&j.ok)); }catch(e){ toast('Verify error ❌', false); } };
  }

  async function renderAllForTab(key){
    // called on hashchange too
    if(key==='dashboard') await renderDashboard();
    if(key==='runs') await renderRuns();
    if(key==='settings') renderSettings();
    if(key==='datasource') renderDatasource();
    if(key==='rules') renderRules();
  }
"""
# inject before boot() function (first occurrence)
i = s.find("// ---------- boot ----------")
if i<0:
    raise SystemExit("[ERR] cannot find boot marker in clean bundle")
s = s[:i] + insert.replace("{MARK}", MARK) + "\n\n" + s[i:]

# also ensure boot() calls ensureShell + bindShellButtons + renderAllForTab
s = s.replace("function boot(){", "function boot(){\n    try{ ensureShell(); }catch(_){ }\n", 1)

# after bindHashRouter(), call renderAllForTab(normalizeHash())
s = s.replace("bindHashRouter();", "bindHashRouter();\n      try{ renderAllForTab(normalizeHash()); }catch(_){ }", 1)

# ensure bindShellButtons called (after ensureShell)
if "bindShellButtons();" not in s:
    s = s.replace("bindHashRouter();", "bindHashRouter();\n      try{ bindShellButtons(); }catch(_){ }", 1)

p.write_text(s, encoding="utf-8")
print("[OK] injected renderer:", MARK)
PY

node --check "$F"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R. UI sẽ hiện shell + Dashboard/Runs hiển thị JSON (không trắng)."
