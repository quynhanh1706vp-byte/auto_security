#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"

echo "== write luxe js =="
JS="static/js/vsp_dashboard_luxe_v1.js"
mkdir -p static/js
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* VSP_DASH_LUXE_V1 (Commercial polish; safe, no-throw) */
(() => {
  if (window.__vsp_dash_luxe_v1) return;
  window.__vsp_dash_luxe_v1 = true;

  const el = (sel, root=document) => root.querySelector(sel);
  const els = (sel, root=document) => Array.from(root.querySelectorAll(sel));
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const sleep = (ms) => new Promise(r=>setTimeout(r,ms));

  function injectCSS(){
    if (el('#VSP_DASH_LUXE_V1_CSS')) return;
    const css = document.createElement('style');
    css.id = 'VSP_DASH_LUXE_V1_CSS';
    css.textContent = `
      :root{
        --vsp-bg:#070e1a;
        --vsp-card:rgba(255,255,255,.04);
        --vsp-card2:rgba(255,255,255,.055);
        --vsp-line:rgba(255,255,255,.08);
        --vsp-text:#dbe6ff;
        --vsp-muted:#8da2d6;
        --vsp-glow:rgba(90,120,255,.35);
        --vsp-ok:#32d583;
        --vsp-warn:#fdb022;
        --vsp-bad:#f97066;
        --vsp-sky:#7aa7ff;
      }
      .vsp-luxe-wrap{max-width:1220px;margin:0 auto;padding:14px 14px 28px;}
      .vsp-luxe-hero{
        border:1px solid var(--vsp-line);
        background: radial-gradient(900px 240px at 15% 0%, rgba(122,167,255,.18), transparent 60%),
                    radial-gradient(700px 220px at 80% 0%, rgba(249,112,102,.10), transparent 62%),
                    linear-gradient(180deg, rgba(255,255,255,.05), rgba(255,255,255,.03));
        border-radius:18px; padding:14px 14px 12px; box-shadow: 0 10px 28px rgba(0,0,0,.35);
      }
      .vsp-luxe-top{display:flex;gap:12px;align-items:center;justify-content:space-between;flex-wrap:wrap}
      .vsp-luxe-title{display:flex;gap:12px;align-items:center}
      .vsp-luxe-badge{
        width:36px;height:36px;border-radius:12px;
        background:linear-gradient(135deg, rgba(122,167,255,.35), rgba(90,120,255,.12));
        border:1px solid var(--vsp-line);
        box-shadow:0 0 0 6px rgba(122,167,255,.06);
      }
      .vsp-luxe-h1{font-weight:800;letter-spacing:.2px;color:var(--vsp-text);font-size:18px;margin:0;line-height:1.1}
      .vsp-luxe-sub{color:var(--vsp-muted);font-size:12px;margin-top:2px}
      .vsp-luxe-actions{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
      .vsp-btn{
        cursor:pointer; user-select:none;
        border:1px solid var(--vsp-line); color:var(--vsp-text);
        background:linear-gradient(180deg, rgba(255,255,255,.06), rgba(255,255,255,.03));
        padding:8px 10px;border-radius:12px;font-size:12px;
        display:flex;gap:8px;align-items:center;
      }
      .vsp-btn:hover{border-color:rgba(122,167,255,.35); box-shadow:0 0 0 6px rgba(122,167,255,.06)}
      .vsp-chip{font-size:12px;border:1px solid var(--vsp-line);border-radius:999px;padding:6px 10px;color:var(--vsp-muted);background:rgba(0,0,0,.12)}
      .vsp-chip.ok{color:#bff7da;border-color:rgba(50,213,131,.28);background:rgba(50,213,131,.08)}
      .vsp-chip.warn{color:#ffe9bf;border-color:rgba(253,176,34,.28);background:rgba(253,176,34,.08)}
      .vsp-chip.bad{color:#ffd1cd;border-color:rgba(249,112,102,.28);background:rgba(249,112,102,.08)}
      .vsp-grid{display:grid;gap:12px;margin-top:12px}
      .vsp-grid.kpis{grid-template-columns:repeat(12,1fr)}
      .vsp-card{
        border:1px solid var(--vsp-line);
        background:linear-gradient(180deg, var(--vsp-card), rgba(255,255,255,.02));
        border-radius:16px;padding:12px;
        box-shadow:0 10px 22px rgba(0,0,0,.28);
        min-height:78px;
      }
      .vsp-kpi{grid-column:span 3}
      @media (max-width:1100px){ .vsp-kpi{grid-column:span 6} }
      @media (max-width:640px){ .vsp-kpi{grid-column:span 12} }
      .vsp-kpi-label{color:var(--vsp-muted);font-size:12px}
      .vsp-kpi-val{color:var(--vsp-text);font-weight:800;font-size:24px;margin-top:6px;letter-spacing:.3px}
      .vsp-kpi-mini{margin-top:6px;display:flex;gap:8px;align-items:center;color:var(--vsp-muted);font-size:12px}
      .vsp-dot{width:8px;height:8px;border-radius:99px;background:var(--vsp-sky);box-shadow:0 0 0 4px rgba(122,167,255,.10)}
      .vsp-dot.ok{background:var(--vsp-ok);box-shadow:0 0 0 4px rgba(50,213,131,.10)}
      .vsp-dot.warn{background:var(--vsp-warn);box-shadow:0 0 0 4px rgba(253,176,34,.10)}
      .vsp-dot.bad{background:var(--vsp-bad);box-shadow:0 0 0 4px rgba(249,112,102,.10)}
      .vsp-row{display:flex;gap:12px;flex-wrap:wrap}
      .vsp-row > .vsp-card{flex:1 1 360px}
      .vsp-h2{margin:0 0 8px;color:var(--vsp-text);font-size:13px;letter-spacing:.2px}
      .vsp-muted{color:var(--vsp-muted);font-size:12px}
      .vsp-bar{height:10px;border-radius:999px;background:rgba(255,255,255,.06);overflow:hidden;border:1px solid var(--vsp-line)}
      .vsp-bar > span{display:block;height:100%;background:linear-gradient(90deg, rgba(122,167,255,.70), rgba(90,120,255,.20))}
      .vsp-sev{display:grid;grid-template-columns:120px 1fr 54px;gap:10px;align-items:center;margin-top:10px}
      .vsp-sev .name{color:var(--vsp-muted);font-size:12px}
      .vsp-sev .num{color:var(--vsp-text);font-weight:700;font-size:12px;text-align:right}
      .vsp-tools{display:grid;grid-template-columns:repeat(8,1fr);gap:8px;margin-top:10px}
      @media (max-width:900px){ .vsp-tools{grid-template-columns:repeat(4,1fr)}}
      @media (max-width:520px){ .vsp-tools{grid-template-columns:repeat(2,1fr)}}
      .vsp-tool{
        border:1px solid var(--vsp-line);border-radius:14px;padding:10px 10px 8px;
        background:linear-gradient(180deg, rgba(255,255,255,.05), rgba(255,255,255,.02));
      }
      .vsp-tool .t{color:var(--vsp-text);font-weight:700;font-size:12px}
      .vsp-tool .s{color:var(--vsp-muted);font-size:11px;margin-top:4px}
      .vsp-degraded{
        margin-top:10px;
        border:1px dashed rgba(253,176,34,.35);
        background:rgba(253,176,34,.08);
        border-radius:16px;padding:10px 12px;color:#ffe9bf;font-size:12px;
      }
      .vsp-skel{
        background:linear-gradient(90deg, rgba(255,255,255,.04), rgba(255,255,255,.08), rgba(255,255,255,.04));
        background-size:200% 100%;
        animation: vspShimmer 1.25s linear infinite;
        border-radius:12px;
      }
      @keyframes vspShimmer{0%{background-position:200% 0}100%{background-position:-200% 0}}
    `;
    document.head.appendChild(css);
  }

  async function jget(url){
    const r = await fetch(url, {credentials:'same-origin', headers:{'Accept':'application/json'}});
    const ct = r.headers.get('content-type') || '';
    const txt = await r.text();
    if (!r.ok) throw new Error(`HTTP ${r.status} for ${url} :: ${txt.slice(0,160)}`);
    if (ct.includes('application/json')) return JSON.parse(txt);
    // sometimes server sends json with wrong header => try parse
    try { return JSON.parse(txt); } catch { throw new Error(`Non-JSON response for ${url}: ${txt.slice(0,120)}`); }
  }

  function mountRoot(){
    // Try to place inside main content; fallback to body.
    const anchors = [
      '#vsp_dashboard_root',
      '#dashboard',
      'main',
      '#main',
      '.vsp-main',
      '.content',
      'body'
    ];
    let a = null;
    for (const sel of anchors){
      a = el(sel);
      if (a) break;
    }
    if (!a) a = document.body;

    let root = el('#vspDashLuxeRoot');
    if (root) return root;

    root = document.createElement('div');
    root.id = 'vspDashLuxeRoot';
    // Put at top
    a.prepend(root);
    return root;
  }

  function renderSkeleton(root){
    root.innerHTML = `
      <div class="vsp-luxe-wrap">
        <div class="vsp-luxe-hero">
          <div class="vsp-luxe-top">
            <div class="vsp-luxe-title">
              <div class="vsp-luxe-badge"></div>
              <div>
                <h1 class="vsp-luxe-h1">VSP Dashboard</h1>
                <div class="vsp-luxe-sub">Loading latest run data…</div>
              </div>
            </div>
            <div class="vsp-luxe-actions">
              <div class="vsp-chip vsp-skel" style="width:180px;height:30px"></div>
              <div class="vsp-btn vsp-skel" style="width:92px;height:32px"></div>
            </div>
          </div>
        </div>

        <div class="vsp-grid kpis">
          ${Array.from({length:4}).map(()=>`
            <div class="vsp-card vsp-kpi">
              <div class="vsp-skel" style="height:12px;width:120px"></div>
              <div class="vsp-skel" style="height:26px;width:110px;margin-top:10px"></div>
              <div class="vsp-skel" style="height:12px;width:180px;margin-top:10px"></div>
            </div>`).join('')}
        </div>

        <div class="vsp-row">
          <div class="vsp-card">
            <div class="vsp-skel" style="height:14px;width:180px"></div>
            <div class="vsp-skel" style="height:12px;width:260px;margin-top:10px"></div>
            <div class="vsp-skel" style="height:10px;width:100%;margin-top:16px"></div>
            <div class="vsp-skel" style="height:10px;width:100%;margin-top:10px"></div>
            <div class="vsp-skel" style="height:10px;width:100%;margin-top:10px"></div>
          </div>
          <div class="vsp-card">
            <div class="vsp-skel" style="height:14px;width:180px"></div>
            <div class="vsp-tools" style="margin-top:12px">
              ${Array.from({length:8}).map(()=>`<div class="vsp-tool"><div class="vsp-skel" style="height:12px;width:90px"></div><div class="vsp-skel" style="height:10px;width:120px;margin-top:8px"></div></div>`).join('')}
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function statusChip(overall){
    const o = String(overall||'UNKNOWN').toUpperCase();
    if (o.includes('PASS') || o === 'GREEN') return ['ok','PASS'];
    if (o.includes('WARN') || o === 'AMBER') return ['warn','WARN'];
    if (o.includes('FAIL') || o.includes('BLOCK') || o === 'RED') return ['bad','FAIL'];
    return ['','UNKNOWN'];
  }

  function num(n){ return (n===0||n) ? String(n) : '—'; }

  function render(root, state){
    const { rid, gate_root, overall_status, counts, degraded, served_by, tools } = state;

    const [cls, label] = statusChip(overall_status);

    const total = Object.values(counts||{}).reduce((a,b)=>a+(+b||0),0);
    const c = (k)=>+((counts||{})[k]||0);

    const sevRows = [
      ['CRITICAL', c('CRITICAL')],
      ['HIGH', c('HIGH')],
      ['MEDIUM', c('MEDIUM')],
      ['LOW', c('LOW')],
      ['INFO', c('INFO')],
      ['TRACE', c('TRACE')],
    ];
    const maxSev = Math.max(1, ...sevRows.map(x=>x[1]));

    const toolList = tools?.length ? tools : [
      'Bandit','Semgrep','Gitleaks','KICS','Trivy','Syft','Grype','CodeQL'
    ].map(t=>({name:t, status:'OK'}));

    root.innerHTML = `
      <div class="vsp-luxe-wrap">
        <div class="vsp-luxe-hero">
          <div class="vsp-luxe-top">
            <div class="vsp-luxe-title">
              <div class="vsp-luxe-badge"></div>
              <div>
                <h1 class="vsp-luxe-h1">VSP Dashboard</h1>
                <div class="vsp-luxe-sub">
                  RID: <b style="color:var(--vsp-text)">${esc(rid)}</b>
                  <span style="opacity:.6">•</span>
                  gate_root: <span style="color:var(--vsp-text)">${esc(gate_root||'—')}</span>
                  <span style="opacity:.6">•</span>
                  served_by: <span style="color:var(--vsp-muted)">${esc(served_by||'—')}</span>
                </div>
              </div>
            </div>

            <div class="vsp-luxe-actions">
              <span class="vsp-chip ${cls}"><span class="vsp-dot ${cls}"></span>&nbsp;Overall: <b>${esc(label)}</b></span>
              <button class="vsp-btn" id="vspLuxeRefreshBtn" title="Refresh">
                ⟳ Refresh
              </button>
              <button class="vsp-btn" id="vspLuxeOpenRunsBtn" title="Runs & Reports">
                ↗ Runs
              </button>
            </div>
          </div>

          ${degraded ? `
          <div class="vsp-degraded">
            <b>Degraded mode:</b> gate_root_path chưa resolve (RUNS_ROOT chưa cấu hình hoặc evidence chưa nằm trong vùng đọc được).
            Dashboard vẫn chạy, nhưng evidence index/manifest là “virtual”.
          </div>` : ``}
        </div>

        <div class="vsp-grid kpis">
          <div class="vsp-card vsp-kpi">
            <div class="vsp-kpi-label">Total findings</div>
            <div class="vsp-kpi-val">${num(total)}</div>
            <div class="vsp-kpi-mini"><span class="vsp-dot ${cls}"></span>From unified severity counts</div>
          </div>
          <div class="vsp-card vsp-kpi">
            <div class="vsp-kpi-label">Critical</div>
            <div class="vsp-kpi-val">${num(c('CRITICAL'))}</div>
            <div class="vsp-kpi-mini"><span class="vsp-dot bad"></span>Immediate attention</div>
          </div>
          <div class="vsp-card vsp-kpi">
            <div class="vsp-kpi-label">High</div>
            <div class="vsp-kpi-val">${num(c('HIGH'))}</div>
            <div class="vsp-kpi-mini"><span class="vsp-dot warn"></span>Prioritize in sprint</div>
          </div>
          <div class="vsp-card vsp-kpi">
            <div class="vsp-kpi-label">Medium+</div>
            <div class="vsp-kpi-val">${num(c('MEDIUM') + c('HIGH') + c('CRITICAL'))}</div>
            <div class="vsp-kpi-mini"><span class="vsp-dot"></span>Risk-bearing backlog</div>
          </div>
        </div>

        <div class="vsp-row">
          <div class="vsp-card">
            <h3 class="vsp-h2">Severity distribution</h3>
            <div class="vsp-muted">Normalized to 6 DevSecOps levels</div>
            ${sevRows.map(([name, n])=>`
              <div class="vsp-sev">
                <div class="name">${esc(name)}</div>
                <div class="vsp-bar"><span style="width:${Math.round((n/maxSev)*100)}%"></span></div>
                <div class="num">${num(n)}</div>
              </div>
            `).join('')}
          </div>

          <div class="vsp-card">
            <h3 class="vsp-h2">Tool lanes</h3>
            <div class="vsp-muted">8-tool pipeline health (display-only)</div>
            <div class="vsp-tools">
              ${toolList.map(t=>`
                <div class="vsp-tool">
                  <div class="t">${esc(t.name)}</div>
                  <div class="s">status: ${esc(t.status||'OK')}</div>
                </div>
              `).join('')}
            </div>
          </div>
        </div>
      </div>
    `;

    const btn = el('#vspLuxeRefreshBtn', root);
    if (btn) btn.addEventListener('click', () => window.__vsp_dash_luxe_v1_reload?.());
    const runsBtn = el('#vspLuxeOpenRunsBtn', root);
    if (runsBtn) runsBtn.addEventListener('click', () => {
      // best effort navigation
      const cands = ['/runs', '/runs_reports', '/runs&reports', '/runs-reports', '/runs_reports_v1'];
      for (const u of cands){
        // try same-origin navigation
        window.location.href = u;
        break;
      }
    });
  }

  async function loadState(){
    // 1) latest rid + gate_root
    const latest = await jget('/api/vsp/rid_latest_gate_root');
    const rid = latest?.rid || '';
    const gate_root = latest?.gate_root || '';

    // 2) manifest (degraded/served_by)
    let manifest = null;
    try { manifest = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`); } catch {}

    // 3) gate summary (overall + counts if present)
    let gateSummary = null;
    try { gateSummary = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`); } catch {}

    // 4) fallback counts from findings_unified meta if gate summary doesn't have
    let counts = (gateSummary?.meta?.counts_by_severity) || (gateSummary?.counts_by_severity) || null;
    if (!counts){
      try {
        const fu = await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`);
        counts = fu?.meta?.counts_by_severity || null;
      } catch {}
    }
    counts = counts || {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0};

    const overall_status =
      gateSummary?.overall_status ||
      gateSummary?.overall ||
      gateSummary?.meta?.overall_status ||
      'UNKNOWN';

    const degraded = !!(manifest && (manifest.degraded === true));
    const served_by = manifest?.served_by || gateSummary?.served_by || '';

    return {
      rid, gate_root,
      overall_status,
      counts,
      degraded,
      served_by,
      tools: null
    };
  }

  async function main(){
    try{
      injectCSS();
      const root = mountRoot();
      renderSkeleton(root);

      const run = async () => {
        try{
          renderSkeleton(root);
          const st = await loadState();
          render(root, st);
        } catch (e){
          // never throw -> show minimal error card
          root.innerHTML = `
            <div class="vsp-luxe-wrap">
              <div class="vsp-luxe-hero">
                <div class="vsp-luxe-top">
                  <div class="vsp-luxe-title">
                    <div class="vsp-luxe-badge"></div>
                    <div>
                      <h1 class="vsp-luxe-h1">VSP Dashboard</h1>
                      <div class="vsp-luxe-sub">Failed to load data: <span style="color:#ffd1cd">${esc(e?.message||e)}</span></div>
                    </div>
                  </div>
                  <div class="vsp-luxe-actions">
                    <button class="vsp-btn" id="vspLuxeRetryBtn">⟳ Retry</button>
                  </div>
                </div>
              </div>
            </div>
          `;
          const b = el('#vspLuxeRetryBtn', root);
          if (b) b.addEventListener('click', () => run());
        }
      };

      window.__vsp_dash_luxe_v1_reload = run;

      // slight delay to avoid fighting existing scripts during initial render
      await sleep(60);
      await run();
    } catch {
      // swallow
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', main);
  } else {
    main();
  }
})();
JS

if [ "$node_ok" -eq 1 ]; then
  echo "== node --check $JS =="
  node --check "$JS" >/dev/null && echo "[OK] node syntax OK"
fi

echo "== patch templates: auto-inject luxe script next to bundle =="
python3 - <<'PY'
from pathlib import Path
import re, time

tpl_dir = Path("templates")
if not tpl_dir.is_dir():
    raise SystemExit("[ERR] templates/ not found")

cands = sorted(tpl_dir.glob("*.html"))
targets = []
for p in cands:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_bundle_commercial_v2.js" in s and "/vsp5" in s or "VSP •" in s:
        targets.append(p)

# fallback: any template that includes the bundle
if not targets:
    for p in cands:
        s = p.read_text(encoding="utf-8", errors="replace")
        if "vsp_bundle_commercial_v2.js" in s:
            targets.append(p)

if not targets:
    raise SystemExit("[ERR] no template includes vsp_bundle_commercial_v2.js")

ts = time.strftime("%Y%m%d_%H%M%S")

for p in targets[:6]:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_dashboard_luxe_v1.js" in s:
        print("[SKIP] already injected:", p.name)
        continue
    bak = p.with_name(p.name + f".bak_dashluxe_{ts}")
    bak.write_text(s, encoding="utf-8")

    # inject after bundle tag (best effort)
    s2, n = re.subn(
        r'(<script[^>]+vsp_bundle_commercial_v2\.js[^>]*></script>)',
        r'\1\n<script src="/static/js/vsp_dashboard_luxe_v1.js?v={{ asset_v }}"></script>',
        s,
        count=1
    )
    if n == 0:
        # inject before </body>
        s2 = s.replace("</body>", '<script src="/static/js/vsp_dashboard_luxe_v1.js?v={{ asset_v }}"></script>\n</body>', 1)

    p.write_text(s2, encoding="utf-8")
    print("[OK] injected luxe script into:", p.name)
PY

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke =="
echo "GET /vsp5 (first 60 lines)"
curl -fsS "$BASE/vsp5" | head -n 60 | sed -n '1,60p'

echo "Check that luxe script is referenced:"
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head || true

echo "[DONE] Open /vsp5 and you should see new hero + KPI cards + severity distribution."
