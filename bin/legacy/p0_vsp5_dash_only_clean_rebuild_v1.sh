#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

JS="static/js/vsp_dash_only_v1.js"
CSS="static/css/vsp_dash_only_v1.css"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_dashonly_clean_${TS}"
echo "[BACKUP] ${WSGI}.bak_dashonly_clean_${TS}"

mkdir -p "$(dirname "$JS")" "$(dirname "$CSS")"

cat > "$CSS" <<'CSS'
/* VSP_DASH_ONLY_V1 (luxe, dashboard-only) */
:root{
  --bg0:#070e1a; --bg1:#0b1220; --card:rgba(255,255,255,.035);
  --bd:rgba(255,255,255,.08); --bd2:rgba(255,255,255,.12);
  --txt:rgba(226,232,240,.94); --mut:rgba(148,163,184,.92);
  --acc:rgba(56,189,248,.88); --acc2:rgba(168,85,247,.68);
  --ok:rgba(34,197,94,.9); --warn:rgba(245,158,11,.92); --bad:rgba(239,68,68,.92);
  --r:16px;
}
html,body{margin:0;background:var(--bg0);color:var(--txt);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial}
.vsp5_wrap{padding:14px 14px 28px}
.hrow{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.h1{font-size:14px;font-weight:700;letter-spacing:.2px}
.pill{font-size:12px;padding:6px 10px;border:1px solid var(--bd);border-radius:999px;background:rgba(0,0,0,.18)}
.btn{cursor:pointer;font-size:12px;padding:7px 10px;border:1px solid var(--bd2);border-radius:12px;background:rgba(255,255,255,.04);color:var(--txt)}
.btn:hover{background:rgba(255,255,255,.07)}
.grid{display:grid;grid-template-columns:1.2fr .8fr;gap:12px;margin-top:12px}
@media(max-width:1100px){.grid{grid-template-columns:1fr}}
.card{border:1px solid var(--bd);border-radius:var(--r);background:linear-gradient(180deg, rgba(255,255,255,.045), rgba(255,255,255,.02)); box-shadow:0 12px 28px rgba(0,0,0,.35)}
.card .hd{padding:12px 12px 0}
.card .ttl{font-size:12px;font-weight:700;color:rgba(226,232,240,.92)}
.card .sub{font-size:11px;color:var(--mut);margin-top:4px}
.card .bd{padding:12px}
.kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:10px;margin-top:10px}
@media(max-width:1100px){.kpis{grid-template-columns:repeat(3,1fr)}}
.kpi{border:1px solid var(--bd);border-radius:14px;background:rgba(0,0,0,.18);padding:10px}
.kpi .k{font-size:10px;color:var(--mut);letter-spacing:.2px}
.kpi .v{font-size:16px;font-weight:800;margin-top:6px}
.sep{height:1px;background:rgba(255,255,255,.06);margin:12px 0}
.tools{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
@media(max-width:1100px){.tools{grid-template-columns:repeat(2,1fr)}}
.tool{border:1px solid var(--bd);border-radius:14px;background:rgba(0,0,0,.18);padding:10px}
.tool .n{font-size:12px;font-weight:800}
.tool .s{font-size:11px;color:var(--mut);margin-top:6px}
.badge{display:inline-flex;align-items:center;gap:6px}
.dot{width:8px;height:8px;border-radius:50%}
.dot.ok{background:var(--ok)} .dot.warn{background:var(--warn)} .dot.bad{background:var(--bad)}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace}
.small{font-size:11px;color:var(--mut)}
.table{width:100%;border-collapse:collapse}
.table th,.table td{padding:8px 6px;border-bottom:1px solid rgba(255,255,255,.06);font-size:12px;text-align:left}
.table th{color:rgba(226,232,240,.85);font-size:11px}
CSS

cat > "$JS" <<'JS'
/* VSP_DASH_ONLY_V1 - single renderer for /vsp5 (no legacy intervals) */
(()=> {
  if (window.__vsp_dash_only_v1_loaded) return;
  window.__vsp_dash_only_v1_loaded = true;

  const $ = (q,root=document)=>root.querySelector(q);
  const esc = (s)=>String(s??'').replace(/[&<>"']/g,m=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));

  const fetchJson = async (url, ms=6000) => {
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), ms);
    try{
      const r = await fetch(url, {cache:'no-store', signal: ctrl.signal});
      const ct = (r.headers.get('content-type')||'');
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      if (!ct.includes('application/json')) {
        const txt = await r.text();
        throw new Error(`non-json (${ct}) ${txt.slice(0,120)}`);
      }
      return await r.json();
    } finally { clearTimeout(t); }
  };

  const state = {
    rid: null,
    gate_root: null,
    autoLatest: true,
    lastErr: null,
    lastUpdate: null,
    interval: null,
  };

  const getPinnedRid = ()=>{
    const u = new URL(location.href);
    const qRid = u.searchParams.get('rid');
    if (qRid) return qRid;
    // hint from your UI: "Pin RID in localStorage + broadcast vsp:rid"
    const k = localStorage.getItem('vsp:rid');
    if (k && k.trim()) return k.trim();
    return null;
  };

  const setPinnedRid = (rid)=>{
    try{ localStorage.setItem('vsp:rid', rid); }catch(e){}
  };

  const render = (data)=>{
    const root = document.getElementById('vsp5_root');
    if (!root) return;

    const counts = data?.counts || {};
    const byTool = data?.by_tool || {};
    const overall = data?.overall || 'UNKNOWN';
    const degraded = data?.degraded ?? null;
    const auditReady = !!data?.audit_ready;

    const sev = (k)=>Number(counts[k]||0);
    const total = Number(counts.total||counts.TOTAL||counts.all||0) || (sev('CRITICAL')+sev('HIGH')+sev('MEDIUM')+sev('LOW')+sev('INFO')+sev('TRACE'));

    const pillOverall = (v)=>{
      let cls = 'pill';
      let dot = 'warn';
      if (String(v).toUpperCase()==='GREEN' || String(v).toUpperCase()==='PASS') dot='ok';
      if (String(v).toUpperCase()==='RED' || String(v).toUpperCase()==='FAIL') dot='bad';
      return `<span class="${cls} badge"><span class="dot ${dot}"></span><span class="mono">${esc(v)}</span></span>`;
    };

    const toolCard = (name, st)=>{
      const s = (st||'UNKNOWN').toUpperCase();
      let dot='warn';
      if (s==='OK' || s==='PASS' || s==='GREEN') dot='ok';
      if (s==='FAIL' || s==='RED' || s==='CRITICAL') dot='bad';
      return `
        <div class="tool">
          <div class="n">${esc(name)}</div>
          <div class="s badge"><span class="dot ${dot}"></span><span class="mono">${esc(s)}</span></div>
        </div>`;
    };

    const ridLine = state.rid ? `<span class="pill mono">RID: ${esc(state.rid)}</span>` : `<span class="pill mono">RID: (none)</span>`;
    const updLine = state.lastUpdate ? `<span class="pill">Updated: <span class="mono">${esc(state.lastUpdate)}</span></span>` : '';
    const errLine = state.lastErr ? `<span class="pill" style="border-color:rgba(239,68,68,.35)">Err: <span class="mono">${esc(state.lastErr)}</span></span>` : '';

    root.innerHTML = `
      <link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css"/>
      <div class="vsp5_wrap">
        <div class="hrow">
          <div class="h1">VSP • Dashboard</div>
          ${pillOverall(overall)}
          ${ridLine}
          ${updLine}
          ${auditReady ? `<span class="pill badge"><span class="dot ok"></span>Audit Ready</span>` : `<span class="pill badge"><span class="dot warn"></span>Audit Pending</span>`}
          ${degraded===null ? '' : `<span class="pill">Degraded: <span class="mono">${esc(degraded)}</span></span>`}
          <span style="flex:1"></span>
          <button class="btn" id="vsp_btn_sync_latest">Sync latest</button>
          <button class="btn" id="vsp_btn_refresh">Refresh</button>
          <label class="pill" style="display:inline-flex;align-items:center;gap:8px">
            <input type="checkbox" id="vsp_ck_auto" ${state.autoLatest?'checked':''}/>
            Auto latest (30s)
          </label>
          <button class="btn" id="vsp_btn_open_gate">Open gate JSON</button>
          <button class="btn" id="vsp_btn_open_html">Open HTML</button>
        </div>

        <div class="kpis">
          <div class="kpi"><div class="k">TOTAL</div><div class="v">${esc(total)}</div></div>
          <div class="kpi"><div class="k">CRITICAL</div><div class="v">${esc(sev('CRITICAL'))}</div></div>
          <div class="kpi"><div class="k">HIGH</div><div class="v">${esc(sev('HIGH'))}</div></div>
          <div class="kpi"><div class="k">MEDIUM</div><div class="v">${esc(sev('MEDIUM'))}</div></div>
          <div class="kpi"><div class="k">LOW</div><div class="v">${esc(sev('LOW'))}</div></div>
          <div class="kpi"><div class="k">INFO/TRACE</div><div class="v">${esc(sev('INFO')+sev('TRACE'))}</div></div>
        </div>

        <div class="grid">
          <div class="card">
            <div class="hd">
              <div class="ttl">Tool Lane (8 tools)</div>
              <div class="sub">Display-only health (from gate summary if available)</div>
            </div>
            <div class="bd">
              <div class="tools">
                ${toolCard('Semgrep', byTool.semgrep || byTool.Semgrep)}
                ${toolCard('Gitleaks', byTool.gitleaks || byTool.Gitleaks)}
                ${toolCard('KICS', byTool.kics || byTool.KICS)}
                ${toolCard('Trivy', byTool.trivy || byTool.Trivy)}
                ${toolCard('Syft', byTool.syft || byTool.Syft)}
                ${toolCard('Grype', byTool.grype || byTool.Grype)}
                ${toolCard('Bandit', byTool.bandit || byTool.Bandit)}
                ${toolCard('CodeQL', byTool.codeql || byTool.CodeQL)}
              </div>
              <div class="sep"></div>
              <div class="small">
                Data source: <span class="mono">/api/vsp/run_file_allow?rid=...&path=run_gate_summary.json</span>
              </div>
            </div>
          </div>

          <div class="card">
            <div class="hd">
              <div class="ttl">Actions & Evidence</div>
              <div class="sub">Open key artifacts quickly (no heavy probing)</div>
            </div>
            <div class="bd">
              <table class="table">
                <thead><tr><th>Artifact</th><th>Path</th></tr></thead>
                <tbody>
                  <tr><td>run_gate_summary</td><td class="mono">run_gate_summary.json</td></tr>
                  <tr><td>run_gate</td><td class="mono">run_gate.json</td></tr>
                  <tr><td>findings_unified</td><td class="mono">findings_unified.json</td></tr>
                  <tr><td>reports CSV</td><td class="mono">reports/findings_unified.csv</td></tr>
                  <tr><td>reports SARIF</td><td class="mono">reports/findings_unified.sarif</td></tr>
                </tbody>
              </table>
              <div class="sep"></div>
              <div class="small">
                Tip: pin RID via localStorage key <span class="mono">vsp:rid</span> or use <span class="mono">?rid=...</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;

    const openArtifact = (path)=>{
      if (!state.rid) return;
      const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(state.rid)}&path=${encodeURIComponent(path)}`;
      window.open(u, '_blank', 'noopener');
    };

    $('#vsp_btn_open_gate')?.addEventListener('click', ()=>openArtifact('run_gate.json'));
    $('#vsp_btn_open_html')?.addEventListener('click', ()=>openArtifact('reports/findings_unified.html'));
    $('#vsp_btn_refresh')?.addEventListener('click', ()=>refreshOnce(true));
    $('#vsp_btn_sync_latest')?.addEventListener('click', ()=>syncLatest(true));
    $('#vsp_ck_auto')?.addEventListener('change', (e)=>{
      state.autoLatest = !!e.target.checked;
      if (state.interval) { clearInterval(state.interval); state.interval=null; }
      if (state.autoLatest) {
        state.interval = setInterval(()=>syncLatest(false), 30000);
      }
    });
  };

  const loadGateSummary = async ()=>{
    if (!state.rid) throw new Error('RID missing');
    // 1) prefer run_gate_summary
    const u1 = `/api/vsp/run_file_allow?rid=${encodeURIComponent(state.rid)}&path=run_gate_summary.json`;
    const j1 = await fetchJson(u1, 8000);
    // normalize minimal shape
    const out = {
      overall: (j1.overall || j1.status || j1.overall_status || 'UNKNOWN'),
      degraded: (j1.degraded ?? j1.degraded_mode ?? null),
      counts: (j1.counts_total || j1.counts || (j1.meta && j1.meta.counts_by_severity) || {}),
      by_tool: (j1.by_tool || j1.tools || {}),
      audit_ready: (j1.audit_ready ?? j1.auditReady ?? false),
      raw: j1
    };
    // if counts_total is boolean in your older contract, fallback try meta
    if (typeof out.counts === 'boolean') out.counts = (j1.meta && j1.meta.counts_by_severity) || {};
    if (!out.counts || typeof out.counts !== 'object') out.counts = {};
    // ensure TOTAL
    if (out.counts.total==null && out.counts.TOTAL==null) {
      const t = (out.counts.CRITICAL||0)+(out.counts.HIGH||0)+(out.counts.MEDIUM||0)+(out.counts.LOW||0)+(out.counts.INFO||0)+(out.counts.TRACE||0);
      out.counts.total = t;
    }
    return out;
  };

  const syncLatest = async (force)=>{
    if (!state.autoLatest && !force) return;
    try{
      const j = await fetchJson('/api/vsp/rid_latest_gate_root', 5000);
      if (j && j.ok && j.rid) {
        if (j.rid !== state.rid) {
          state.rid = j.rid;
          state.gate_root = j.gate_root || null;
          setPinnedRid(state.rid);
        }
      }
    } catch(e){
      // ignore, keep pinned rid
    }
    await refreshOnce(false);
  };

  const refreshOnce = async (fromClick)=>{
    try{
      if (!state.rid) state.rid = getPinnedRid();
      state.lastErr = null;
      render({overall:'LOADING', counts:{total:0,CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, by_tool:{}});
      const g = await loadGateSummary();
      state.lastUpdate = new Date().toLocaleString();
      render(g);
      if (fromClick) console.log('[VSP][DASH_ONLY_V1] refreshed', {rid: state.rid});
    } catch(e){
      state.lastErr = (e && e.message) ? e.message : String(e);
      state.lastUpdate = new Date().toLocaleString();
      render({overall:'ERROR', counts:{total:0,CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, by_tool:{}});
      console.warn('[VSP][DASH_ONLY_V1] refresh failed', e);
    }
  };

  // boot
  console.log('[VSP][DASH_ONLY_V1] boot', {path: location.pathname});
  if (location.pathname !== '/vsp5') return;

  state.rid = getPinnedRid();
  state.autoLatest = true;

  refreshOnce(false).then(()=>syncLatest(false)).catch(()=>{});
  state.interval = setInterval(()=>syncLatest(false), 30000);
})();
JS

echo "[OK] wrote $JS"
echo "[OK] wrote $CSS"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_VSP5_DASH_ONLY_CLEAN_MW_V1"
if MARK in s:
    print("[OK] marker already present, skip patch")
else:
    block = textwrap.dedent(r'''
    # ===================== VSP_P0_VSP5_DASH_ONLY_CLEAN_MW_V1 =====================
    # Serve /vsp5 as DASH-ONLY page (no vsp_bundle_commercial_v2.js) to stop "jump"/double-render.
    import os, json, time
    from datetime import datetime

    def _vsp_json(start_response, code, obj):
        body = json.dumps(obj, ensure_ascii=False, separators=(",",":")).encode("utf-8")
        headers = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-cache, no-store, must-revalidate"),
            ("Pragma","no-cache"),
            ("Expires","0"),
            ("Content-Length", str(len(body))),
        ]
        start_response(code, headers)
        return [body]

    def _vsp_text(start_response, code, text, ctype="text/html; charset=utf-8"):
        body = text.encode("utf-8")
        headers = [
            ("Content-Type", ctype),
            ("Cache-Control","no-cache, no-store, must-revalidate"),
            ("Pragma","no-cache"),
            ("Expires","0"),
            ("Content-Length", str(len(body))),
        ]
        start_response(code, headers)
        return [body]

    def _vsp_guess_run_roots():
        # Best-effort roots (override with env VSP_RUNS_ROOT if needed)
        roots = []
        env = os.environ.get("VSP_RUNS_ROOT","").strip()
        if env:
            roots.extend([x.strip() for x in env.split(":") if x.strip()])
        roots += [
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY-10-10-v4/out",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        # keep existing ones only
        out=[]
        for r in roots:
            try:
                if os.path.isdir(r):
                    out.append(r)
            except Exception:
                pass
        return out

    def _vsp_scan_runs(limit=200):
        roots = _vsp_guess_run_roots()
        found = []
        wanted = ("run_gate_summary.json","run_gate.json","findings_unified.json")
        for root in roots:
            try:
                for name in os.listdir(root):
                    d = os.path.join(root, name)
                    if not os.path.isdir(d): 
                        continue
                    # accept dirs likely to be runs
                    if not (name.startswith("RUN_") or name.startswith("VSP_") or name.startswith("AATE_")):
                        # still allow if it contains key files
                        pass
                    hit = False
                    for fn in wanted:
                        if os.path.exists(os.path.join(d, fn)) or os.path.exists(os.path.join(d, "reports", "findings_unified.csv")):
                            hit = True
                            break
                    if not hit:
                        continue
                    st = os.stat(d)
                    found.append({"rid": name, "root": root, "mtime": int(st.st_mtime)})
            except Exception:
                continue
        found.sort(key=lambda x: x["mtime"], reverse=True)
        return found[:limit]

    def _vsp5_dash_only_html():
        # minimal /vsp5 shell (nav kept), only loads fetch shim + dash-only JS + dash-only CSS
        v = str(int(time.time()))
        return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
  <meta http-equiv="Pragma" content="no-cache"/>
  <meta http-equiv="Expires" content="0"/>
  <title>VSP5</title>
  <link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css?v={v}"/>
  <style>
    body{{ margin:0; background:#0b1220; color:rgba(226,232,240,.96);
          font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; }}
    .vsp5nav{{ display:flex; gap:10px; padding:10px 14px; border-bottom:1px solid rgba(255,255,255,.10);
              background: rgba(0,0,0,.22); position:sticky; top:0; z-index:9999; }}
    .vsp5nav a{{ color:rgba(226,232,240,.92); text-decoration:none; font-size:12px;
                padding:8px 10px; border:1px solid rgba(255,255,255,.14); border-radius:12px; }}
    .vsp5nav a:hover{{ background: rgba(255,255,255,.06); }}
    #vsp5_root{{ min-height: 60vh; }}
  </style>
</head>
<body>
  <div class="vsp5nav">
    <a href="/vsp5">Dashboard</a>
    <a href="/runs">Runs &amp; Reports</a>
    <a href="/data_source">Data Source</a>
    <a href="/settings">Settings</a>
    <a href="/rule_overrides">Rule Overrides</a>
  </div>
  <div id="vsp5_root"></div>

  <!-- DASH ONLY: stop jump/double-render -->
  <script src="/static/js/vsp_p0_fetch_shim_v1.js?v={v}"></script>
  <script src="/static/js/vsp_dash_only_v1.js?v={v}"></script>
</body>
</html>"""

    def _vsp5_dash_only_mw(app):
        def _wrap(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            if path == "/vsp5":
                return _vsp_text(start_response, "200 OK", _vsp5_dash_only_html(), "text/html; charset=utf-8")

            # Fallback API (safe) for dash-only and other pages
            if path == "/api/vsp/runs":
                runs = _vsp_scan_runs(limit=200)
                return _vsp_json(start_response, "200 OK", {"ok": True, "runs": runs, "latest_rid": (runs[0]["rid"] if runs else None)})

            if path == "/api/vsp/rid_latest_gate_root":
                runs = _vsp_scan_runs(limit=1)
                if not runs:
                    return _vsp_json(start_response, "200 OK", {"ok": False, "err": "no runs found"})
                rid = runs[0]["rid"]
                return _vsp_json(start_response, "200 OK", {"ok": True, "rid": rid, "gate_root": f"gate_root_{rid}"})

            return app(environ, start_response)
        return _wrap
    # ===================== /VSP_P0_VSP5_DASH_ONLY_CLEAN_MW_V1 =====================
    ''').rstrip()+"\n"

    # Append block near end; then wrap 'application' safely.
    s2 = s + "\n" + block

    # Ensure we wrap application exactly once
    if re.search(r'=\s*_vsp5_dash_only_mw\(\s*application\s*\)', s2):
        pass
    else:
        s2 += "\n# [AUTO] wrap main WSGI app for /vsp5 dash-only\ntry:\n    application = _vsp5_dash_only_mw(application)\nexcept Exception:\n    pass\n"

    p.write_text(s2, encoding="utf-8")
    print("[OK] patched wsgi with dash-only clean middleware")

PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== wait /vsp5 ready =="
for i in $(seq 1 40); do
  curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== verify /vsp5 does NOT load vsp_bundle_commercial_v2.js =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" >/dev/null 2>&1 && { echo "[ERR] still loading bundle"; exit 3; } || true
curl -fsS "$BASE/vsp5" | grep -n "vsp_dash_only_v1.js" || { echo "[ERR] dash-only js not found in html"; exit 4; }

echo "== verify /api/vsp/rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Console should show: [VSP][DASH_ONLY_V1] boot"
