#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

# =========================
# [P1-1] Add export route on gateway 8910
# =========================
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF (expected gateway app)"; exit 1; }

cp -f "$PYF" "$PYF.bak_export_v3_${TS}"
echo "[BACKUP] $PYF.bak_export_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# If already present, skip
if re.search(r"@app\.route\(\s*['\"]/api/vsp/run_export_v3/<", t):
    print("[OK] export route already exists, skip")
    raise SystemExit(0)

TAG = "\n# === VSP_GATEWAY_EXPORT_V3_V1 ===\n"
BLOCK = r'''
# === VSP_GATEWAY_EXPORT_V3_V1 ===
def _vsp_norm_rid_to_ci_key(rid: str) -> str:
    # Accept: RUN_VSP_CI_YYYYmmdd_HHMMSS  OR  VSP_CI_YYYYmmdd_HHMMSS
    s = (rid or "").strip()
    if s.startswith("RUN_"):
        s = s[len("RUN_"):]
    return s

def _vsp_resolve_ci_run_dir(rid: str):
    from pathlib import Path
    import glob, os

    key = _vsp_norm_rid_to_ci_key(rid)
    # Common bases (CI out + bundle out). Add more if needed later.
    bases = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]

    # Try exact dir
    for b in bases:
        cand = Path(b) / key
        if cand.is_dir():
            return cand

    # Try glob fallback
    pats = [
        f"**/{key}",
        f"**/RUN_{key}",
        f"**/{key}*",
    ]
    for b in bases:
        bp = Path(b)
        if not bp.exists():
            continue
        for pat in pats:
            for m in bp.glob(pat):
                if m.is_dir():
                    return m
    return None

def _vsp_export_candidates(ci_run_dir, fmt: str):
    from pathlib import Path
    import glob

    d = Path(ci_run_dir)
    # Common report locations/names in your pipeline
    html = [
        d / "reports" / "vsp_run_report_cio_v3.html",
        d / "reports" / "report.html",
        d / "reports" / "index.html",
        d / "vsp_run_report_cio_v3.html",
        d / "report.html",
    ]
    pdf = [
        d / "reports" / "report.pdf",
        d / "reports" / "vsp_run_report_cio_v3.pdf",
        d / "report.pdf",
    ]
    zips = [
        d / "reports" / "report.zip",
        d / "reports.zip",
        d / "report.zip",
    ]

    # Also accept: first matching extension under reports/
    if fmt == "html":
        cands = html + [Path(x) for x in glob.glob(str(d / "reports" / "*.html"))]
    elif fmt == "pdf":
        cands = pdf + [Path(x) for x in glob.glob(str(d / "reports" / "*.pdf"))]
    else:
        cands = zips + [Path(x) for x in glob.glob(str(d / "reports" / "*.zip"))]

    out = []
    for f in cands:
        try:
            if f.is_file() and f.stat().st_size > 0:
                out.append(f)
        except Exception:
            pass
    # de-dupe keep order
    seen = set()
    uniq = []
    for f in out:
        k = str(f)
        if k not in seen:
            uniq.append(f); seen.add(k)
    return uniq

@app.route("/api/vsp/run_export_v3/<rid>", methods=["GET","HEAD"])
def api_vsp_run_export_v3(rid):
    # Gateway implementation:
    # - If report exists: serve it (HEAD used by UI to enable button)
    # - If not: 404 export_file_not_found (commercial-meaningful)
    from flask import request, jsonify, send_file, Response
    import mimetypes

    fmt = (request.args.get("fmt","html") or "html").lower().strip()
    if fmt not in ("html","pdf","zip"):
        return jsonify(ok=False, error="bad_fmt", fmt=fmt), 400

    ci_dir = _vsp_resolve_ci_run_dir(rid)
    if not ci_dir:
        return jsonify(ok=False, error="run_not_found", rid=rid), 404

    cands = _vsp_export_candidates(ci_dir, fmt)
    if not cands:
        return jsonify(ok=False, error="export_file_not_found", rid=rid, fmt=fmt, ci_run_dir=str(ci_dir)), 404

    f = cands[0]
    ctype = mimetypes.guess_type(str(f))[0] or ("text/html" if fmt=="html" else "application/pdf" if fmt=="pdf" else "application/zip")

    if request.method == "HEAD":
        resp = Response(status=200)
        resp.headers["Content-Type"] = ctype
        try:
            resp.headers["Content-Length"] = str(f.stat().st_size)
        except Exception:
            pass
        return resp

    # GET
    as_attach = (fmt == "zip")
    return send_file(str(f), mimetype=ctype, as_attachment=as_attach, download_name=f.name)
# === /VSP_GATEWAY_EXPORT_V3_V1 ===
'''

# Insert near run_status routes if possible, else before __main__ or EOF
anchor = None
for pat in [
    r"@app\.route\(\s*['\"]/api/vsp/run_status_v2/",
    r"def\s+api_vsp_run_status_v2",
    r"@app\.route\(\s*['\"]/api/vsp/run_status_v1/",
]:
    m = re.search(pat, t)
    if m:
        anchor = m.start()
        break

if anchor is not None:
    t2 = t[:anchor] + TAG + BLOCK + "\n" + t[anchor:]
else:
    mm = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", t)
    if mm:
        i = mm.start()
        t2 = t[:i] + TAG + BLOCK + "\n" + t[i:]
    else:
        t2 = t + TAG + BLOCK + "\n"

p.write_text(t2, encoding="utf-8")
print("[OK] inserted /api/vsp/run_export_v3/<rid> (GET/HEAD)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

# =========================
# [P1-2] Runs UI: switch to 8-tools renderer bound to run_gate_summary.by_tool
# =========================
JS_DIR="static/js"
TPL_DIR="templates"
mkdir -p "$JS_DIR"

JS8="$JS_DIR/vsp_runs_tab_8tools_v1.js"
if [ -f "$JS8" ]; then
  cp -f "$JS8" "$JS8.bak_${TS}"
  echo "[BACKUP] $JS8.bak_${TS}"
fi

cat > "$JS8" <<'JS'
/* vsp_runs_tab_8tools_v1.js
 * Commercial Runs UI (8 tools) - binds to status_v2.run_gate_summary.by_tool (preferred).
 * Columns:
 *  Overall | Gate | Tools A (SEMGREP/TRIVY/KICS/GITLEAKS) | Tools B (CODEQL/BANDIT/SYFT/GRYPE) | Degraded | Export
 */
(function(){
  const RUNS_INDEX_URL = "/api/vsp/runs_index_v3_fs_resolved?limit=50&hide_empty=0&filter=1";
  const STATUS_V2_URL  = (rid) => `/api/vsp/run_status_v2/${encodeURIComponent(rid)}`;
  const EXPORT_URL     = (rid, fmt) => `/api/vsp/run_export_v3/${encodeURIComponent(rid)}?fmt=${encodeURIComponent(fmt)}`;

  const TOOLS_A = ["SEMGREP","TRIVY","KICS","GITLEAKS"];
  const TOOLS_B = ["CODEQL","BANDIT","SYFT","GRYPE"];

  const VERDICT_ORDER = ["RED","AMBER","GREEN","NOT_RUN","DISABLED","DEGRADED","UNKNOWN"];
  function normVerdict(v){
    if(!v) return "NOT_RUN";
    const s = String(v).toUpperCase();
    if (["CRITICAL","HIGH"].includes(s)) return "RED";
    if (["MEDIUM"].includes(s)) return "AMBER";
    if (["LOW","INFO","TRACE"].includes(s)) return "GREEN";
    if (["PASS","OK","SUCCESS","GREEN"].includes(s)) return "GREEN";
    if (["FAIL","ERROR","RED"].includes(s)) return "RED";
    if (["WARN","WARNING","AMBER","YELLOW"].includes(s)) return "AMBER";
    if (["NOT_RUN","NOTRUN","SKIP","SKIPPED"].includes(s)) return "NOT_RUN";
    if (["DISABLED"].includes(s)) return "DISABLED";
    if (["DEGRADED"].includes(s)) return "DEGRADED";
    return s;
  }

  function pickToolFromByTool(status, tool){
    const byTool = status?.run_gate_summary?.by_tool || status?.gate_by_tool || status?.gate?.by_tool || {};
    const o = byTool?.[tool] || byTool?.[tool.toLowerCase()] || null;
    const verdict = normVerdict(o?.verdict || o?.overall || o?.status || null);
    const total = (o?.total ?? o?.findings_total ?? o?.count ?? o?.n ?? null);
    return { verdict, total };
  }

  function pickToolFallbackFields(status, tool){
    const k = tool.toLowerCase();
    const verdict = normVerdict(status?.[`${k}_verdict`] || status?.[`${k}Verdict`] || null);
    const total = (status?.[`${k}_total`] ?? status?.[`${k}Total`] ?? null);
    return { verdict, total };
  }

  function toolBadge(status, tool){
    let r = pickToolFromByTool(status, tool);
    if (!r || (!r.verdict || r.verdict==="NOT_RUN")) {
      const f = pickToolFallbackFields(status, tool);
      // prefer by_tool verdict even if total missing; but if by_tool not present, fallback fields help
      if (f && f.verdict) r = (r?.verdict && r.verdict!=="NOT_RUN") ? r : f;
    }
    const v = normVerdict(r?.verdict);
    const total = (r?.total === null || r?.total === undefined) ? "" : ` (${r.total})`;
    return `<span class="vsp-badge vsp-badge-${v}" title="${tool}: ${v}${total}">${tool}:${v}${total}</span>`;
  }

  function overallBadge(status){
    const v = normVerdict(status?.overall_verdict || status?.run_gate_summary?.overall || status?.run_gate_summary?.overall_verdict);
    return `<span class="vsp-badge vsp-badge-${v}" title="overall">${v}</span>`;
  }

  function degradedCell(status){
    const n = (status?.degraded_tools && Array.isArray(status.degraded_tools)) ? status.degraded_tools.length : (status?.degraded_n ?? 0);
    const v = (n > 0) ? "AMBER" : "GREEN";
    return `<span class="vsp-badge vsp-badge-${v}" title="degraded_tools">${n}</span>`;
  }

  function exportCell(rid){
    // UI probes HEAD; if 404 -> disable with tooltip "no report yet"
    const htmlId = `exp_html_${rid}`;
    const pdfId  = `exp_pdf_${rid}`;
    const zipId  = `exp_zip_${rid}`;

    const btn = (id, fmt, label) => `<button class="vsp-exp-btn" id="${id}" data-rid="${rid}" data-fmt="${fmt}" disabled title="probe...">${label}</button>`;
    return `<div class="vsp-exp-wrap">
      ${btn(htmlId,"html","HTML")}
      ${btn(pdfId,"pdf","PDF")}
      ${btn(zipId,"zip","ZIP")}
    </div>`;
  }

  async function headProbe(rid, fmt){
    try{
      const r = await fetch(EXPORT_URL(rid, fmt), { method: "HEAD", cache: "no-store" });
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
      .vsp-runs8-title{ font-weight:700; font-size:14px; margin:6px 0 10px; opacity:0.95; }
      .vsp-runs8-table{ width:100%; border-collapse:collapse; font-size:12px; }
      .vsp-runs8-table th,.vsp-runs8-table td{ border-bottom:1px solid rgba(255,255,255,0.08); padding:10px 8px; vertical-align:top; }
      .vsp-runs8-table th{ text-transform:uppercase; font-size:11px; letter-spacing:.06em; opacity:.8; }
      .vsp-badge{ display:inline-block; padding:3px 7px; border-radius:10px; margin:2px 4px 2px 0; border:1px solid rgba(255,255,255,0.18); }
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
      .vsp-drawer{ position:fixed; top:0; right:0; height:100%; width:min(560px, 92vw); background: rgba(2,6,23,0.98); border-left:1px solid rgba(255,255,255,0.10); padding:14px; z-index:99999; overflow:auto; display:none; }
      .vsp-drawer h3{ margin:0 0 8px; font-size:14px; }
      .vsp-drawer .close{ float:right; cursor:pointer; opacity:0.8; }
      .vsp-drawer pre{ background: rgba(255,255,255,0.06); padding:10px; border-radius:12px; overflow:auto; }
      .vsp-link{ opacity:0.9; text-decoration:underline; }
    `;
    document.head.appendChild(css);
  }

  function findMount(){
    const ids = [
      "vsp_runs_table", "runs_table", "vsp_runs_mount", "tab_runs",
      "runsTab", "runs", "vsp4_runs", "vspRuns"
    ];
    for(const id of ids){
      const el = document.getElementById(id);
      if(el) return el;
    }
    const q = document.querySelector("[data-vsp-runs-mount]") || document.querySelector(".vsp-runs-mount");
    if(q) return q;

    // fallback: create a mount inside main container
    const main = document.querySelector("#app") || document.body;
    const wrap = document.createElement("div");
    wrap.id = "vsp_runs_mount";
    main.appendChild(wrap);
    return wrap;
  }

  function mkTableShell(){
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

  async function fetchJson(url){
    const r = await fetch(url, { cache: "no-store" });
    const j = await r.json().catch(()=>null);
    if(!r.ok) throw new Error(`HTTP ${r.status}`);
    return j;
  }

  // Simple concurrency limiter
  async function mapLimit(arr, limit, fn){
    const ret = new Array(arr.length);
    let i = 0;
    const workers = new Array(Math.min(limit, arr.length)).fill(0).map(async ()=>{
      while(i < arr.length){
        const idx = i++;
        try{ ret[idx] = await fn(arr[idx], idx); }
        catch(e){ ret[idx] = null; }
      }
    });
    await Promise.all(workers);
    return ret;
  }

  async function renderRuns8(){
    ensureStyles();
    const mount = findMount();
    mount.innerHTML = mkTableShell();

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

    // Render rows with placeholders first
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

    // Load status_v2 per run (limit concurrency)
    const statuses = await mapLimit(items, 6, async (it)=>{
      const rid = it.run_id || it.rid || it.id || it.name;
      const st = await fetchJson(STATUS_V2_URL(rid));
      return { rid, st };
    });

    statuses.forEach((o, idx)=>{
      const rid = items[idx].run_id || items[idx].rid || items[idx].id || items[idx].name;
      const st = o?.st || null;

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
        return;
      }

      const gateV = normVerdict(st?.run_gate_summary?.overall || st?.run_gate_summary?.overall_verdict || st?.overall_verdict);
      if(cellO) cellO.innerHTML = overallBadge(st);
      if(cellG) cellG.innerHTML = `<span class="vsp-badge vsp-badge-${gateV}">${gateV}</span>`;

      if(cellA) cellA.innerHTML = TOOLS_A.map(t=>toolBadge(st,t)).join("");
      if(cellB) cellB.innerHTML = TOOLS_B.map(t=>toolBadge(st,t)).join("");
      if(cellD) cellD.innerHTML = degradedCell(st);

      // Row click -> drawer
      const row = document.getElementById(`vspRuns8Row_${idx}`);
      if(row){
        row.classList.add("vsp-row-click");
        row.onclick = ()=>{
          const byTool = st?.run_gate_summary?.by_tool || {};
          const degraded = st?.degraded_tools || [];
          const body =
            `<div style="margin:8px 0 10px">
               <div><b>RID:</b> ${rid}</div>
               <div><b>CI:</b> ${st?.ci_run_dir || st?.ci || "-"}</div>
               <div style="margin-top:8px"><b>Links</b></div>
               <div><a class="vsp-link" href="${STATUS_V2_URL(rid)}" target="_blank">status_v2</a></div>
               <div><a class="vsp-link" href="/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}" target="_blank">artifacts_index</a></div>
               <div style="margin-top:8px"><b>Export</b></div>
               <div><a class="vsp-link" href="${EXPORT_URL(rid,"html")}" target="_blank">HTML</a> | <a class="vsp-link" href="${EXPORT_URL(rid,"pdf")}" target="_blank">PDF</a> | <a class="vsp-link" href="${EXPORT_URL(rid,"zip")}" target="_blank">ZIP</a></div>
             </div>
             <div style="margin-top:10px"><b>by_tool (from run_gate_summary.by_tool)</b></div>
             <pre>${JSON.stringify(byTool, null, 2)}</pre>
             <div style="margin-top:10px"><b>degraded_tools</b></div>
             <pre>${JSON.stringify(degraded, null, 2)}</pre>`;
          openDrawer(`Run details`, body);
        };
      }

      // Probe export buttons (HEAD) - do not throw, just enable/disable + tooltip
      const fmts = ["html","pdf","zip"];
      fmts.forEach(async (fmt)=>{
        const id = fmt==="html" ? `exp_html_${rid}` : fmt==="pdf" ? `exp_pdf_${rid}` : `exp_zip_${rid}`;
        const btn = document.getElementById(id);
        if(!btn) return;
        const ok = await headProbe(rid, fmt);
        btn.disabled = !ok;
        btn.title = ok ? "open export" : "no report yet";
        btn.onclick = ()=>{
          if(btn.disabled) return;
          window.open(EXPORT_URL(rid, fmt), "_blank");
        };
      });
    });
  }

  // Only render on Runs tab-ish (hash contains runs), but also safe to render if unknown
  function shouldRender(){
    const h = String(location.hash || "");
    if(!h) return true;
    return h.toLowerCase().includes("runs");
  }

  function boot(){
    if(!shouldRender()) return;
    renderRuns8().catch(e=>console.error("[runs8] render failed", e));
  }

  window.addEventListener("hashchange", boot);
  window.addEventListener("DOMContentLoaded", boot);
})();
JS

echo "[OK] wrote $JS8"

# Patch templates to load new JS instead of old
if [ -d "$TPL_DIR" ]; then
  python3 - <<'PY'
from pathlib import Path
import re
import time

tpl = Path("templates")
ts = time.strftime("%Y%m%d_%H%M%S")

targets = []
for p in tpl.rglob("*"):
    if p.is_file() and p.suffix.lower() in [".html",".jinja",".jinja2",".htm"]:
        s = p.read_text(encoding="utf-8", errors="ignore")
        if "vsp_runs_tab_v1.js" in s:
            targets.append(p)

if not targets:
    print("[WARN] no template references to vsp_runs_tab_v1.js found (may be loaded elsewhere)")
    raise SystemExit(0)

for p in targets:
    b = p.with_suffix(p.suffix + f".bak_runs8_{ts}")
    b.write_text(p.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
    s = p.read_text(encoding="utf-8", errors="ignore").replace("vsp_runs_tab_v1.js","vsp_runs_tab_8tools_v1.js")
    p.write_text(s, encoding="utf-8")
    print(f"[OK] patched template: {p} -> backup {b.name}")
PY
else
  echo "[WARN] templates/ not found; you may need to manually update the script include (search vsp_runs_tab_v1.js)"
fi

echo "=================="
echo "[DONE] P1 patch applied:"
echo " - export route: /api/vsp/run_export_v3/<rid>?fmt=html|pdf|zip (GET/HEAD)"
echo " - runs UI JS:  static/js/vsp_runs_tab_8tools_v1.js (8 tools, by_tool binding)"
echo "Next: restart 8910 to activate backend route + reload UI."
