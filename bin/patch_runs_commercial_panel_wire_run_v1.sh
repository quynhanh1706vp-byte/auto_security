#!/usr/bin/env bash
set -euo pipefail
F="static/js/vsp_runs_commercial_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_wire_runv1_${TS}"
echo "[BACKUP] $F.bak_wire_runv1_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_commercial_panel_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Inject helpers + UI block if not present
if "VSP_RUNS_COMMERCIAL_WIRE_RUN_V1" not in txt:
    inject = r'''
  // === VSP_RUNS_COMMERCIAL_WIRE_RUN_V1 ===
  async function apiPostJSON(url, data) {
    const res = await fetch(url, {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify(data || {})
    });
    const t = await res.text();
    let j = null;
    try { j = JSON.parse(t); } catch(e) {}
    return { ok: res.ok, status: res.status, json: j, text: t };
  }

  async function apiGetJSON(url) {
    const res = await fetch(url, { cache: 'no-store' });
    const t = await res.text();
    let j = null;
    try { j = JSON.parse(t); } catch(e) {}
    return { ok: res.ok, status: res.status, json: j, text: t };
  }

  function ensurePanel(host) {
    let box = host.querySelector('#vsp-commercial-runbox');
    if (box) return box;

    const wrap = document.createElement('div');
    wrap.id = 'vsp-commercial-runbox';
    wrap.style.cssText = 'margin:12px 0; padding:12px; border:1px solid rgba(255,255,255,.08); border-radius:14px; background:rgba(255,255,255,.02)';

    wrap.innerHTML = `
      <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">
        <div style="font-weight:700;">Run Scan Now</div>
        <span id="vsp-run-badge" class="vsp-badge" style="padding:4px 10px; border-radius:999px; border:1px solid rgba(255,255,255,.12); opacity:.9;">IDLE</span>
        <span id="vsp-run-req" class="vsp-mono" style="opacity:.85;"></span>
        <span id="vsp-run-vspid" class="vsp-mono" style="opacity:.85;"></span>
      </div>

      <div style="display:flex; gap:10px; flex-wrap:wrap; margin-top:10px;">
        <select id="vsp-run-profile" class="vsp-select" style="min-width:160px;">
          <option value="FULL_EXT">FULL_EXT</option>
          <option value="FAST">FAST</option>
        </select>
        <input id="vsp-run-target" class="vsp-input" style="min-width:420px; flex:1;"
          placeholder="/path/to/repo or url..." />
        <button id="vsp-run-go" class="vsp-btn" style="min-width:140px;">Run</button>
        <button id="vsp-run-refresh" class="vsp-btn" style="min-width:140px;">Refresh Runs</button>
      </div>

      <pre id="vsp-run-tail" class="vsp-mono" style="margin-top:10px; max-height:220px; overflow:auto; font-size:11px; white-space:pre-wrap; opacity:.92; border-top:1px dashed rgba(255,255,255,.10); padding-top:10px;"></pre>
    `;

    // Insert near top of runs pane
    host.insertBefore(wrap, host.firstChild);
    return wrap;
  }

  function setBadge(text, kind) {
    const b = document.querySelector('#vsp-run-badge');
    if (!b) return;
    b.textContent = text;
    // lightweight "kind" styling
    const map = {
      IDLE: 'rgba(255,255,255,.12)',
      RUNNING: 'rgba(255,193,7,.25)',
      DONE: 'rgba(34,197,94,.25)',
      FAILED: 'rgba(239,68,68,.25)',
      ERROR: 'rgba(239,68,68,.25)'
    };
    b.style.background = map[kind || text] || 'rgba(255,255,255,.12)';
  }

  function setText(sel, s) {
    const el = document.querySelector(sel);
    if (el) el.textContent = s || '';
  }

  function setTail(s) {
    const el = document.querySelector('#vsp-run-tail');
    if (el) el.textContent = s || '';
  }

  async function refreshRuns() {
    // If runs table loader exists, trigger it
    try {
      if (window.VSP_RUNS_TAB_SIMPLE_V2 && typeof window.VSP_RUNS_TAB_SIMPLE_V2.loadRuns === 'function') {
        await window.VSP_RUNS_TAB_SIMPLE_V2.loadRuns();
        return;
      }
    } catch(e) {}
    // fallback: reload page data (router will re-render)
    try { location.hash = '#runs'; } catch(e) {}
  }

  async function pollStatus(reqId) {
    const url = `/api/vsp/run_status_v1/${encodeURIComponent(reqId)}`;
    while (true) {
      const r = await apiGetJSON(url);
      if (!r.ok || !r.json) {
        setBadge('ERROR', 'ERROR');
        setTail(r.text || `Failed to fetch ${url}`);
        return;
      }
      const st = r.json;
      setBadge(st.status || 'RUNNING', st.status || 'RUNNING');
      setText('#vsp-run-req', st.req_id ? `REQ: ${st.req_id}` : '');
      setText('#vsp-run-vspid', st.vsp_run_id ? `VSP: ${st.vsp_run_id}` : '');
      setTail(st.tail || '');

      if (st.final === true) {
        // auto refresh list once final
        await refreshRuns();
        return;
      }
      await new Promise(res => setTimeout(res, 2000));
    }
  }

  async function bindRunActions(panel) {
    const btn = panel.querySelector('#vsp-run-go');
    const btnR = panel.querySelector('#vsp-run-refresh');
    const inpT = panel.querySelector('#vsp-run-target');
    const selP = panel.querySelector('#vsp-run-profile');

    // defaults
    if (inpT && !inpT.value) inpT.value = '/home/test/Data/SECURITY-10-10-v4';

    btnR && btnR.addEventListener('click', async () => {
      setBadge('IDLE','IDLE');
      await refreshRuns();
    });

    btn && btn.addEventListener('click', async () => {
      setBadge('RUNNING','RUNNING');
      setTail('[UI] Spawning scan...\n');
      setText('#vsp-run-req','');
      setText('#vsp-run-vspid','');

      const payload = {
        mode: 'local',
        profile: (selP && selP.value) ? selP.value : 'FULL_EXT',
        target_type: 'path',
        target: (inpT && inpT.value) ? inpT.value.trim() : '/home/test/Data/SECURITY-10-10-v4'
      };

      const r = await apiPostJSON('/api/vsp/run_v1', payload);
      if (!r.ok || !r.json || !r.json.req_id) {
        setBadge('ERROR','ERROR');
        setTail(r.text || '[UI] Run spawn failed');
        return;
      }
      const reqId = r.json.req_id;
      setText('#vsp-run-req', `REQ: ${reqId}`);
      setTail(`[UI] Spawned: ${reqId}\n[UI] Polling status...\n`);
      await pollStatus(reqId);
    });
  }
  // === END VSP_RUNS_COMMERCIAL_WIRE_RUN_V1 ===
'''
    # put inject before final closing "})();" if possible
    txt = re.sub(r'\n\}\)\(\);\s*$', "\n" + inject + "\n})();\n", txt, flags=re.M)

# Ensure mount() calls ensurePanel+bind once
# find mount() and add panel creation
if "ensurePanel(" not in txt:
    txt = re.sub(
        r'(function\s+mount\(\)\s*\{\s*\n\s*const\s+host\s*=\s*findRunsHost\(\);\s*\n\s*if\s*\(!host\)\s*\{[\s\S]*?\}\s*)',
        r'\1\n    const panel = ensurePanel(host);\n    bindRunActions(panel);\n',
        txt,
        count=1
    )

p.write_text(txt, encoding="utf-8")
print("[OK] patched runs commercial panel: wired /api/vsp/run_v1 + poll /run_status_v1 + refresh runs")
PY

echo "[OK] done patch $F"
