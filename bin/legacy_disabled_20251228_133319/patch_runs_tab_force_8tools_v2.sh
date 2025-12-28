#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

TPL="templates/vsp_4tabs_commercial_v1.html"
JS="static/js/vsp_runs_tab_8tools_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

cp -f "$TPL" "$TPL.bak_runs8force_${TS}"
echo "[BACKUP] $TPL.bak_runs8force_${TS}"

# ---------
# 1) Update Runs 8-tools JS (stronger mount + nicer drawer)
# ---------
cp -f "$JS" "$JS.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* vsp_runs_tab_8tools_v1.js (v2 force)
 * - Force Runs tab render to 8 tools (A/B)
 * - Avoid being overridden by legacy runs scripts
 * - Drawer shows tool table + links
 */
(function(){
  const RUNS_INDEX_URL = "/api/vsp/runs_index_v3_fs_resolved?limit=50&hide_empty=0&filter=1";
  const STATUS_V2_URL  = (rid) => `/api/vsp/run_status_v2/${encodeURIComponent(rid)}`;
  const ARTIFACTS_URL  = (rid) => `/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`;
  const EXPORT_URL     = (rid, fmt) => `/api/vsp/run_export_v3/${encodeURIComponent(rid)}?fmt=${encodeURIComponent(fmt)}`;

  const TOOLS_A = ["SEMGREP","TRIVY","KICS","GITLEAKS"];
  const TOOLS_B = ["CODEQL","BANDIT","SYFT","GRYPE"];
  const TOOLS_ALL = [...TOOLS_A, ...TOOLS_B];

  function normVerdict(v){
    if(!v) return "NOT_RUN";
    const s = String(v).toUpperCase();
    if (["PASS","OK","SUCCESS","GREEN"].includes(s)) return "GREEN";
    if (["FAIL","ERROR","RED"].includes(s)) return "RED";
    if (["WARN","WARNING","AMBER","YELLOW"].includes(s)) return "AMBER";
    if (["NOT_RUN","NOTRUN","SKIP","SKIPPED"].includes(s)) return "NOT_RUN";
    if (["DISABLED"].includes(s)) return "DISABLED";
    if (["DEGRADED"].includes(s)) return "DEGRADED";
    return s;
  }

  function pickTool(status, tool){
    const byTool = status?.run_gate_summary?.by_tool || {};
    const o = byTool?.[tool] || byTool?.[tool.toLowerCase()] || null;
    const verdict = normVerdict(o?.verdict || o?.overall || o?.status || null);
    const total = (o?.total ?? o?.findings_total ?? o?.count ?? o?.n ?? 0);
    return { verdict, total };
  }

  function badgeHtml(label, verdict, extra){
    const v = normVerdict(verdict);
    const x = (extra === null || extra === undefined) ? "" : ` (${extra})`;
    return `<span class="vsp-badge vsp-badge-${v}" title="${label}: ${v}${x}">${label}:${v}${x}</span>`;
  }

  async function fetchJson(url){
    const r = await fetch(url, { cache:"no-store" });
    const j = await r.json().catch(()=>null);
    if(!r.ok) throw new Error(`HTTP ${r.status}`);
    return j;
  }

  async function headProbe(url){
    try{
      const r = await fetch(url, { method:"HEAD", cache:"no-store" });
      return r.ok;
    }catch(e){
      return false;
    }
  }

  function ensureStyles(){
    if (document.getElementById("vspRuns8ToolsStyles")) return;
    const css = document.createElement("style");
    css.id = "vspRuns8ToolsStyles";
    css.textContent = `
      .vsp-runs8-wrap{ padding:12px; }
      .vsp-runs8-title{ font-weight:750; font-size:14px; margin:6px 0 10px; opacity:0.95; }
      .vsp-runs8-table{ width:100%; border-collapse:collapse; font-size:12px; }
      .vsp-runs8-table th,.vsp-runs8-table td{ border-bottom:1px solid rgba(255,255,255,0.08); padding:10px 8px; vertical-align:top; }
      .vsp-runs8-table th{ text-transform:uppercase; font-size:11px; letter-spacing:.06em; opacity:.8; }
      .vsp-badge{ display:inline-block; padding:3px 7px; border-radius:10px; margin:2px 4px 2px 0; border:1px solid rgba(255,255,255,0.18); white-space:nowrap; }
      .vsp-badge-RED{ background: rgba(220,38,38,0.18); }
      .vsp-badge-AMBER{ background: rgba(245,158,11,0.18); }
      .vsp-badge-GREEN{ background: rgba(34,197,94,0.18); }
      .vsp-badge-NOT_RUN{ background: rgba(148,163,184,0.12); }
      .vsp-badge-DISABLED{ background: rgba(100,116,139,0.12); }
      .vsp-badge-DEGRADED{ background: rgba(56,189,248,0.12); }
      .vsp-badge-UNKNOWN{ background: rgba(148,163,184,0.12); }
      .vsp-exp-wrap{ display:flex; gap:6px; flex-wrap:wrap; }
      .vsp-exp-btn{ font-size:11px; padding:5px 8px; border-radius:10px; border:1px solid rgba(255,255,255,0.18); background: rgba(255,255,255,0.06); color: inherit; cursor:pointer; }
      .vsp-exp-btn[disabled]{ opacity:0.45; cursor:not-allowed; }
      .vsp-row-click{ cursor:pointer; }
      .vsp-link{ opacity:0.9; text-decoration:underline; }
      .vsp-drawer{ position:fixed; top:0; right:0; height:100%; width:min(620px, 94vw);
        background: rgba(2,6,23,0.98); border-left:1px solid rgba(255,255,255,0.10);
        padding:14px; z-index:99999; overflow:auto; display:none; }
      .vsp-drawer h3{ margin:0 0 10px; font-size:14px; }
      .vsp-drawer .close{ float:right; cursor:pointer; opacity:0.8; }
      .vsp-mini{ opacity:.85; font-size:12px; }
      .vsp-mini-table{ width:100%; border-collapse:collapse; margin-top:8px; font-size:12px; }
      .vsp-mini-table td,.vsp-mini-table th{ border-bottom:1px solid rgba(255,255,255,0.08); padding:8px 6px; text-align:left; }
      .vsp-pill{ display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,0.16); }
    `;
    document.head.appendChild(css);
  }

  function findMount(){
    // strongest: explicit marker from template
    const m = document.querySelector("[data-vsp-runs-mount='1']");
    if (m) return m;

    // fallback heuristics
    const ids = ["vsp_runs_mount","tab_runs","runs_tab","vsp4_runs","runs","runsTab"];
    for(const id of ids){
      const el = document.getElementById(id);
      if(el) return el;
    }
    // last fallback: create under body
    const wrap = document.createElement("div");
    wrap.id = "vsp_runs_mount";
    (document.querySelector("#app") || document.body).appendChild(wrap);
    return wrap;
  }

  function mkShell(){
    return `
      <div class="vsp-runs8-wrap">
        <div class="vsp-runs8-title">Runs & Reports (8 tools)</div>
        <table class="vsp-runs8-table">
          <thead>
            <tr>
              <th>Run</th>
              <th>Overall</th>
              <th>Gate</th>
              <th>Tools A</th>
              <th>Tools B</th>
              <th>Degraded</th>
              <th>Export</th>
            </tr>
          </thead>
          <tbody id="vspRuns8Tbody">
            <tr><td colspan="7">Loading…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="vsp-drawer" id="vspRuns8Drawer">
        <span class="close" id="vspRuns8DrawerClose">✕</span>
        <h3 id="vspRuns8DrawerTitle">Run details</h3>
        <div id="vspRuns8DrawerBody"></div>
      </div>
    `;
  }

  function openDrawer(title, bodyHtml){
    const d = document.getElementById("vspRuns8Drawer");
    const t = document.getElementById("vspRuns8DrawerTitle");
    const b = document.getElementById("vspRuns8DrawerBody");
    if(!d || !t || !b) return;
    t.textContent = title;
    b.innerHTML = bodyHtml;
    d.style.display = "block";
  }
  function closeDrawer(){
    const d = document.getElementById("vspRuns8Drawer");
    if(d) d.style.display = "none";
  }

  function exportCell(rid){
    const btn = (fmt, label) => `<button class="vsp-exp-btn" data-rid="${rid}" data-fmt="${fmt}" disabled title="probe...">${label}</button>`;
    return `<div class="vsp-exp-wrap">${btn("html","HTML")}${btn("pdf","PDF")}${btn("zip","ZIP")}</div>`;
  }

  function toolBadges(status, tools){
    return tools.map(t=>{
      const r = pickTool(status, t);
      return badgeHtml(t, r.verdict, r.total);
    }).join("");
  }

  function drawToolTable(status){
    const by = status?.run_gate_summary?.by_tool || {};
    const rows = TOOLS_ALL.map(t=>{
      const r = pickTool(status, t);
      const v = normVerdict(r.verdict);
      return `<tr>
        <td><span class="vsp-pill">${t}</span></td>
        <td>${badgeHtml("v", v, "")}</td>
        <td>${r.total ?? 0}</td>
      </tr>`;
    }).join("");
    return `
      <table class="vsp-mini-table">
        <thead><tr><th>Tool</th><th>Verdict</th><th>Total</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  async function render(){
    ensureStyles();

    const mount = findMount();
    mount.innerHTML = mkShell();

    const tbody = document.getElementById("vspRuns8Tbody");
    const closeBtn = document.getElementById("vspRuns8DrawerClose");
    if(closeBtn) closeBtn.onclick = closeDrawer;

    let runs;
    try{
      runs = await fetchJson(RUNS_INDEX_URL);
    }catch(e){
      tbody.innerHTML = `<tr><td colspan="7">Failed to load runs_index: ${String(e)}</td></tr>`;
      return;
    }
    const items = runs?.items || runs?.runs || [];
    if(!items.length){
      tbody.innerHTML = `<tr><td colspan="7">No runs found.</td></tr>`;
      return;
    }

    tbody.innerHTML = items.map((it, idx)=>{
      const rid = it.run_id || it.rid || it.id || it.name || `run_${idx}`;
      return `<tr id="vspRuns8Row_${idx}">
        <td><span class="vsp-link" title="${rid}">${rid}</span></td>
        <td id="vspRuns8Overall_${idx}">…</td>
        <td id="vspRuns8Gate_${idx}">…</td>
        <td id="vspRuns8A_${idx}">…</td>
        <td id="vspRuns8B_${idx}">…</td>
        <td id="vspRuns8Deg_${idx}">…</td>
        <td id="vspRuns8Exp_${idx}">${exportCell(rid)}</td>
      </tr>`;
    }).join("");

    // Load statuses with limited concurrency
    const limit = 6;
    let i = 0;
    const results = new Array(items.length).fill(null);

    async function worker(){
      while(i < items.length){
        const idx = i++;
        const it = items[idx];
        const rid = it.run_id || it.rid || it.id || it.name;
        try{
          const st = await fetchJson(STATUS_V2_URL(rid));
          results[idx] = { rid, st };
        }catch(e){
          results[idx] = { rid, st: null, err: String(e) };
        }
      }
    }
    await Promise.all(new Array(Math.min(limit, items.length)).fill(0).map(worker));

    for(let idx=0; idx<items.length; idx++){
      const rid = items[idx].run_id || items[idx].rid || items[idx].id || items[idx].name;
      const st = results[idx]?.st || null;

      const cellO = document.getElementById(`vspRuns8Overall_${idx}`);
      const cellG = document.getElementById(`vspRuns8Gate_${idx}`);
      const cellA = document.getElementById(`vspRuns8A_${idx}`);
      const cellB = document.getElementById(`vspRuns8B_${idx}`);
      const cellD = document.getElementById(`vspRuns8Deg_${idx}`);

      if(!st){
        if(cellO) cellO.innerHTML = `<span class="vsp-badge vsp-badge-UNKNOWN">ERR</span>`;
        if(cellG) cellG.textContent = "status_v2 failed";
        if(cellA) cellA.textContent = "-";
        if(cellB) cellB.textContent = "-";
        if(cellD) cellD.textContent = "-";
        continue;
      }

      const gateV = normVerdict(st?.run_gate_summary?.overall || st?.overall_verdict);
      const overallV = normVerdict(st?.overall_verdict || st?.run_gate_summary?.overall);
      if(cellO) cellO.innerHTML = `<span class="vsp-badge vsp-badge-${overallV}">${overallV}</span>`;
      if(cellG) cellG.innerHTML = `<span class="vsp-badge vsp-badge-${gateV}">${gateV}</span>`;

      if(cellA) cellA.innerHTML = toolBadges(st, TOOLS_A);
      if(cellB) cellB.innerHTML = toolBadges(st, TOOLS_B);

      const dn = (st?.degraded_tools && Array.isArray(st.degraded_tools)) ? st.degraded_tools.length : (st?.degraded_n ?? 0);
      const dv = dn > 0 ? "AMBER" : "GREEN";
      if(cellD) cellD.innerHTML = `<span class="vsp-badge vsp-badge-${dv}">${dn}</span>`;

      // Row -> drawer
      const row = document.getElementById(`vspRuns8Row_${idx}`);
      if(row){
        row.classList.add("vsp-row-click");
        row.onclick = async ()=>{
          let artifacts = null;
          try{ artifacts = await fetchJson(ARTIFACTS_URL(rid)); }catch(e){ artifacts = null; }

          const ci = st?.ci_run_dir || st?.ci || "-";
          const degraded = st?.degraded_tools || [];
          const links = `
            <div class="vsp-mini" style="margin:8px 0 10px">
              <div><b>RID:</b> ${rid}</div>
              <div><b>CI:</b> ${ci}</div>
              <div style="margin-top:8px"><b>Links</b></div>
              <div><a class="vsp-link" href="${STATUS_V2_URL(rid)}" target="_blank">status_v2</a></div>
              <div><a class="vsp-link" href="${ARTIFACTS_URL(rid)}" target="_blank">artifacts_index</a></div>
              <div style="margin-top:8px"><b>Export</b></div>
              <div>
                <a class="vsp-link" href="${EXPORT_URL(rid,"html")}" target="_blank">HTML</a> |
                <a class="vsp-link" href="${EXPORT_URL(rid,"pdf")}" target="_blank">PDF</a> |
                <a class="vsp-link" href="${EXPORT_URL(rid,"zip")}" target="_blank">ZIP</a>
              </div>
            </div>
          `;
          const toolTable = `<div style="margin-top:10px"><b>by_tool (8 tools)</b></div>${drawToolTable(st)}`;
          const degBlock = `<div style="margin-top:10px"><b>degraded_tools</b></div><pre style="white-space:pre-wrap">${JSON.stringify(degraded, null, 2)}</pre>`;
          const artBlock = `<div style="margin-top:10px"><b>artifacts</b></div><pre style="white-space:pre-wrap">${JSON.stringify(artifacts, null, 2)}</pre>`;

          openDrawer(`Run details`, links + toolTable + degBlock + artBlock);
        };
      }

      // Export buttons probe (HEAD)
      const expCell = document.getElementById(`vspRuns8Exp_${idx}`);
      if(expCell){
        const btns = expCell.querySelectorAll("button.vsp-exp-btn");
        btns.forEach(async (btn)=>{
          const fmt = btn.getAttribute("data-fmt");
          const ok = await headProbe(EXPORT_URL(rid, fmt));
          btn.disabled = !ok;
          btn.title = ok ? "open export" : "no report yet";
          btn.onclick = ()=>{
            if(btn.disabled) return;
            window.open(EXPORT_URL(rid, fmt), "_blank");
          };
        });
      }
    }
  }

  function shouldRender(){
    const h = String(location.hash || "").toLowerCase();
    if(!h) return true;
    return h.includes("runs");
  }

  let _inflight = false;
  async function boot(){
    if(!shouldRender()) return;
    if(_inflight) return;
    _inflight = true;
    try{ await render(); } finally { _inflight = false; }
  }

  window.addEventListener("hashchange", boot);
  window.addEventListener("DOMContentLoaded", boot);
})();
JS

echo "[OK] updated $JS"

# ---------
# 2) Patch template:
#   - inject mount <div data-vsp-runs-mount="1"></div>
#   - disable legacy runs scripts (any script src containing "runs_tab" except our 8tools)
#   - ensure our script is included once
# ---------
python3 - <<'PY'
from pathlib import Path
import re, time

tpl = Path("templates/vsp_4tabs_commercial_v1.html")
s = tpl.read_text(encoding="utf-8", errors="ignore")
ts = time.strftime("%Y%m%d_%H%M%S")

tag_js = '<script src="/static/js/vsp_runs_tab_8tools_v1.js"></script>'
mount = '<div data-vsp-runs-mount="1"></div>'

# 2.1 Disable legacy runs scripts
def disable_legacy_scripts(html: str) -> str:
    def repl(m):
        src = m.group(1)
        if "vsp_runs_tab_8tools_v1.js" in src:
            return m.group(0)
        # comment out
        return f"<!-- DISABLED_LEGACY_RUNS_SCRIPT: {m.group(0)} -->"
    return re.sub(r'<script[^>]+src="([^"]*runs[^"]*)"[^>]*>\s*</script>', repl, html, flags=re.I)

s2 = disable_legacy_scripts(s)

# 2.2 Ensure mount exists: try insert near a Runs panel marker; else before </body>
if mount not in s2:
    inserted = False
    # common markers (best-effort)
    patterns = [
        r'(id="runs"[^>]*>)',
        r'(id="tab_runs"[^>]*>)',
        r'(id="tab-runs"[^>]*>)',
        r'(data-tab="runs"[^>]*>)',
    ]
    for pat in patterns:
        m = re.search(pat, s2, flags=re.I)
        if m:
            i = m.end()
            s2 = s2[:i] + "\n" + mount + "\n" + s2[i:]
            inserted = True
            break
    if not inserted:
        m = re.search(r"</body\s*>", s2, flags=re.I)
        if m:
            i = m.start()
            s2 = s2[:i] + "\n" + mount + "\n" + s2[i:]
        else:
            s2 += "\n" + mount + "\n"

# 2.3 Ensure our JS included once (insert before </body>)
if tag_js not in s2:
    m = re.search(r"</body\s*>", s2, flags=re.I)
    if m:
        i = m.start()
        s2 = s2[:i] + "\n" + tag_js + "\n" + s2[i:]
    else:
        s2 += "\n" + tag_js + "\n"

# 2.4 De-dupe accidental duplicates
while s2.count(tag_js) > 1:
    s2 = s2.replace(tag_js, "", 1)

tpl.write_text(s2, encoding="utf-8")
print("[OK] template patched: mount + legacy runs scripts disabled + ensure runs8 js include")
PY

echo "[DONE] Runs tab forced to 8-tools renderer."
echo "Next: reload UI with hard refresh: http://127.0.0.1:8910/vsp4#runs"
