#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p471_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, datetime

f = Path("static/js/vsp_c_runs_v1.js")
s = f.read_text(encoding="utf-8", errors="replace")

# 1) Strip ALL previous P467..P470 blocks (and friends) to stop “double UI / blank / observer fight”.
tags = [
  "VSP_P467", "VSP_P467B", "VSP_P467C", "VSP_P467D",
  "VSP_P468", "VSP_P469", "VSP_P470",
  "VSP_P466", "VSP_P466A", "VSP_P466A2",
]
for t in tags:
  # remove blocks like: /* ===== TAG ===== */ ... /* ===== /TAG ===== */
  pat = re.compile(rf";?\s*/\*\s*=+\s*{re.escape(t)}.*?\*/.*?;?\s*/\*\s*=+\s*/{re.escape(t)}.*?\*/\s*",
                   re.DOTALL | re.IGNORECASE)
  s, _n = pat.subn("", s)

# also remove any “runs pro” leftovers by heuristic (safe)
pat2 = re.compile(r"/\*\s*=+\s*VSP_P46\d+.*?\*/.*?/\\*\s*=+\s*/VSP_P46\d+.*?\*/", re.DOTALL | re.IGNORECASE)
s = pat2.sub("", s)

stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

addon = rf"""
;/* ===================== VSP_P471_C_RUNS_PRO_SINGLE_V1 ===================== */
(function(){{
  if (window.__VSP_P471_C_RUNS_PRO_SINGLE_V1) return;
  window.__VSP_P471_C_RUNS_PRO_SINGLE_V1 = true;

  const BUILD = "{stamp}";
  const log = (...a)=>console.log("[P471]", ...a);
  const warn = (...a)=>console.warn("[P471]", ...a);

  function qs(sel, root=document){{ try{{ return root.querySelector(sel); }}catch(e){{ return null; }} }}
  function qsa(sel, root=document){{ try{{ return Array.from(root.querySelectorAll(sel)); }}catch(e){{ return []; }} }}

  function isCRuns() {{
    try {{
      return location && location.pathname && location.pathname.startsWith("/c/runs");
    }} catch(e) {{ return false; }}
  }}

  function getRidFromUrl() {{
    try {{
      const u = new URL(location.href);
      return (u.searchParams.get("rid") || "").trim();
    }} catch(e) {{ return ""; }}
  }}

  function setRid(rid) {{
    const r = (rid||"").trim();
    if(!r) return;
    // Keep it simple & deterministic
    location.href = "/c/runs?rid=" + encodeURIComponent(r);
  }}

  function fmtTs(ts) {{
    if(!ts) return "";
    try {{
      const d = new Date(ts);
      if(String(d) === "Invalid Date") return "";
      const pad=n=>String(n).padStart(2,"0");
      return `${{d.getFullYear()}}-${{pad(d.getMonth()+1)}}-${{pad(d.getDate())}} ${{pad(d.getHours())}}:${{pad(d.getMinutes())}}`;
    }} catch(e) {{ return ""; }}
  }}

  async function fetchJson(url, toMs=5000) {{
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), toMs);
    try {{
      const r = await fetch(url, {{signal: ctl.signal, credentials:"same-origin"}});
      const j = await r.json();
      return {{ok:true, status:r.status, json:j}};
    }} catch(e) {{
      return {{ok:false, err:String(e)}};
    }} finally {{
      clearTimeout(t);
    }}
  }}

  async function fetchRunsAny() {{
    // Prefer /api/vsp/runs (it has lots of CI)
    const tries = [
      "/api/vsp/runs?limit=250&offset=0",
      "/api/vsp/runs?limit=250",
      "/api/vsp/runs_v3?limit=250&include_ci=1",
      "/api/vsp/runs_v3?limit=250",
      "/api/ui/runs_v3?limit=250&include_ci=1",
      "/api/ui/runs_v3?limit=250",
    ];
    for(const u of tries) {{
      const r = await fetchJson(u, 8000);
      if(!r.ok || !r.json) continue;
      const j = r.json;
      let items = [];
      if (Array.isArray(j.runs)) {{
        items = j.runs.map(x=>({{
          rid: (x.rid||x.run_id||"").toString(),
          ts: (x.ts ? Date.parse(x.ts) : (x.mtime ? (Number(x.mtime)*1000) : 0)),
          label: (x.label||"").toString()
        }}));
      }} else if (Array.isArray(j.items)) {{
        items = j.items.map(x=>({{
          rid: (x.rid||x.run_id||x.name||"").toString(),
          ts: (x.ts ? Date.parse(x.ts) : 0),
          label: (x.label||"").toString()
        }}));
      }}
      items = items.filter(x=>x.rid);
      if(items.length) {{
        items.sort((a,b)=>(b.ts||0)-(a.ts||0));
        return {{ok:true, src:u, items, total: (j.total||items.length)}};
      }}
    }}
    return {{ok:false, items:[], total:0}};
  }}

  async function headOK(url, toMs=2500) {{
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), toMs);
    try {{
      const r = await fetch(url, {{method:"HEAD", signal:ctl.signal, credentials:"same-origin"}});
      return r && (r.status>=200 && r.status<400);
    }} catch(e) {{
      return false;
    }} finally {{
      clearTimeout(t);
    }}
  }}

  async function guessDownload(kind, rid) {{
    const r = encodeURIComponent(rid);
    const cands = (kind==="csv") ? [
      `/api/vsp/findings_csv?rid=${{r}}`,
      `/api/vsp/download_findings_csv?rid=${{r}}`,
      `/api/vsp/findings?rid=${{r}}&fmt=csv`,
      `/api/vsp/export_findings_csv?rid=${{r}}`,
      `/api/vsp/findings.csv?rid=${{r}}`,
    ] : [
      `/api/vsp/reports_tgz?rid=${{r}}`,
      `/api/vsp/download_reports_tgz?rid=${{r}}`,
      `/api/vsp/reports?rid=${{r}}&fmt=tgz`,
      `/api/vsp/reports.tgz?rid=${{r}}`,
    ];
    for(const u of cands) {{
      if(await headOK(u)) return u;
    }}
    return "";
  }}

  function injectStyles() {{
    if(qs("#vsp_p471_style")) return;
    const st = document.createElement("style");
    st.id = "vsp_p471_style";
    st.textContent = `
      .vsp-p471-card {{
        margin: 12px 12px 18px 12px;
        padding: 14px 14px 10px 14px;
        border: 1px solid rgba(120,140,180,.22);
        border-radius: 14px;
        background: rgba(12,16,28,.55);
        backdrop-filter: blur(10px);
      }}
      .vsp-p471-title {{
        display:flex; align-items:center; justify-content:space-between;
        gap:12px; margin-bottom:10px;
      }}
      .vsp-p471-title h2 {{
        margin:0; font-size:15px; letter-spacing:.2px;
      }}
      .vsp-p471-sub {{
        opacity:.75; font-size:12px;
      }}
      .vsp-p471-toolbar {{
        display:flex; flex-wrap:wrap; gap:10px;
        align-items:center; margin: 10px 0 12px 0;
      }}
      .vsp-p471-input {{
        height:32px; padding:0 10px; border-radius:10px;
        border:1px solid rgba(120,140,180,.22);
        background: rgba(8,10,18,.55);
        color: inherit; outline: none;
      }}
      .vsp-p471-btn {{
        height:32px; padding:0 10px; border-radius:10px;
        border:1px solid rgba(120,140,180,.22);
        background: rgba(18,24,44,.55);
        color: inherit; cursor:pointer;
      }}
      .vsp-p471-btn:hover {{ filter: brightness(1.08); }}
      .vsp-p471-chip {{
        padding: 4px 10px; border-radius: 999px;
        border:1px solid rgba(120,140,180,.22);
        background: rgba(18,24,44,.35);
        font-size:12px; opacity:.9;
      }}
      .vsp-p471-table {{
        width:100%;
        border-collapse: collapse;
        font-size: 13px;
      }}
      .vsp-p471-table th, .vsp-p471-table td {{
        padding: 10px 8px;
        border-bottom: 1px solid rgba(120,140,180,.12);
        vertical-align: middle;
      }}
      .vsp-p471-actions {{
        display:flex; flex-wrap:wrap; gap:8px; justify-content:flex-end;
      }}
      .vsp-p471-pill {{
        padding: 6px 10px;
        border-radius: 999px;
        border:1px solid rgba(120,140,180,.22);
        background: rgba(18,24,44,.35);
        cursor:pointer;
        font-size:12px;
      }}
      .vsp-p471-pill:hover {{ filter: brightness(1.08); }}
      .vsp-p471-scan-grid {{
        display:grid;
        grid-template-columns: 1.6fr .9fr;
        gap: 12px;
      }}
      .vsp-p471-scan-row {{
        display:flex; gap:10px; align-items:center;
      }}
      .vsp-p471-box {{
        border:1px solid rgba(120,140,180,.18);
        border-radius: 12px;
        background: rgba(8,10,18,.35);
        padding: 10px;
        min-height: 48px;
        overflow:auto;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        font-size: 12px;
        white-space: pre-wrap;
      }}
      @media (max-width: 980px) {{
        .vsp-p471-scan-grid {{ grid-template-columns: 1fr; }}
      }}
    `;
    document.head.appendChild(st);
  }}

  function hideLegacySafely() {{
    // Hide ONLY cards that look like the old “Runs & Reports” blocks, not parents.
    const blocks = [];
    for(const el of qsa("div,section")) {{
      if(!el || el.dataset && el.dataset.vspP471 === "1") continue;
      const txt = (el.innerText||"").trim();
      if(!txt) continue;

      const looksLikeLegacyRuns =
        txt.includes("Filter by RID") ||
        txt.includes("Pick a RID") ||
        (txt.includes("Runs & Reports") && txt.includes("client-side"));

      const looksLikeLegacyScan =
        txt.includes("Scan / Start Run") ||
        txt.includes("Kick off via /api/vsp/run_v1");

      if(looksLikeLegacyRuns || looksLikeLegacyScan) {{
        // avoid hiding our own card
        if(el.closest && el.closest("#vsp_p471_root")) continue;
        blocks.push(el);
      }}
    }}
    let n=0;
    for(const el of blocks) {{
      // Don’t hide body/html or huge containers
      if(el === document.body || el === document.documentElement) continue;
      if(el.parentElement === document.body && (el.textContent||"").length > 20000) continue;
      el.style.display = "none";
      n++;
    }}
    log("legacy blocks hidden:", n);
  }}

  function ensureMountPoint() {{
    let root = qs("#vsp_p471_root");
    if(root) return root;

    root = document.createElement("div");
    root.id = "vsp_p471_root";
    root.dataset.vspP471 = "1";

    // Insert near top but not inside legacy blocks
    const body = document.body;
    const first = body.firstElementChild;
    if(first) body.insertBefore(root, first);
    else body.appendChild(root);
    return root;
  }}

  function buildRunsCard(root) {{
    const card = document.createElement("div");
    card.className = "vsp-p471-card";
    card.dataset.vspP471 = "1";

    const ridSel = getRidFromUrl();
    card.innerHTML = `
      <div class="vsp-p471-title">
        <div>
          <h2>Runs & Reports (commercial)</h2>
          <div class="vsp-p471-sub">P471 • single-source • API-driven • rid=${ridSel ? ridSel : "(none)"} • build=${BUILD}</div>
        </div>
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:flex-end">
          <span class="vsp-p471-chip" id="vsp_p471_total">Total: -</span>
          <span class="vsp-p471-chip" id="vsp_p471_shown">Shown: -</span>
          <span class="vsp-p471-chip" id="vsp_p471_sel">Selected: ${ridSel ? ridSel : "-"}</span>
        </div>
      </div>

      <div class="vsp-p471-toolbar">
        <input class="vsp-p471-input" id="vsp_p471_q" placeholder="Search RID..." style="min-width:220px" />
        <select class="vsp-p471-input" id="vsp_p471_page" title="Page size">
          <option value="20">20/page</option>
          <option value="50">50/page</option>
          <option value="100">100/page</option>
          <option value="200">200/page</option>
        </select>
        <button class="vsp-p471-btn" id="vsp_p471_refresh">Refresh</button>
        <button class="vsp-p471-btn" id="vsp_p471_open_runs">Open Exports (/runs)</button>
      </div>

      <div style="overflow:auto">
        <table class="vsp-p471-table">
          <thead>
            <tr>
              <th style="text-align:left; width:44%">RID</th>
              <th style="text-align:left; width:18%">DATE</th>
              <th style="text-align:left; width:18%">STATUS</th>
              <th style="text-align:right; width:20%">ACTIONS</th>
            </tr>
          </thead>
          <tbody id="vsp_p471_tbody">
            <tr><td colspan="4" style="opacity:.75">Loading…</td></tr>
          </tbody>
        </table>
      </div>
    `;
    root.appendChild(card);
    return card;
  }}

  function buildScanCard(root) {{
    const card = document.createElement("div");
    card.className = "vsp-p471-card";
    card.dataset.vspP471 = "1";

    card.innerHTML = `
      <div class="vsp-p471-title">
        <div>
          <h2>Scan / Start Run</h2>
          <div class="vsp-p471-sub">Kick off via <code>/api/vsp/run_v1</code> • Poll via <code>/api/vsp/run_status_v1</code> (best-effort)</div>
        </div>
        <div class="vsp-p471-chip" id="vsp_p471_scan_rid">RID: (none)</div>
      </div>

      <div class="vsp-p471-scan-grid">
        <div>
          <div class="vsp-p471-sub" style="margin:0 0 6px 2px">Target path</div>
          <input class="vsp-p471-input" id="vsp_p471_target" style="width:100%" value="/home/test/Data/SECURITY_BUNDLE" />
          <div class="vsp-p471-sub" style="margin:10px 0 6px 2px">Note</div>
          <input class="vsp-p471-input" id="vsp_p471_note" style="width:100%" placeholder="optional note for audit trail" />
        </div>
        <div>
          <div class="vsp-p471-sub" style="margin:0 0 6px 2px">Mode</div>
          <select class="vsp-p471-input" id="vsp_p471_mode" style="width:100%">
            <option value="FULL">FULL (8 tools)</option>
            <option value="FAST">FAST</option>
          </select>
          <div class="vsp-p471-scan-row" style="margin-top:12px; justify-content:flex-end">
            <button class="vsp-p471-btn" id="vsp_p471_start">Start scan</button>
            <button class="vsp-p471-btn" id="vsp_p471_poll">Refresh status</button>
          </div>
        </div>
      </div>

      <div style="margin-top:10px" class="vsp-p471-box" id="vsp_p471_scan_out">Ready.</div>
    `;
    root.appendChild(card);
    return card;
  }}

  function renderRows(rows, pageSize, q) {{
    const tb = qs("#vsp_p471_tbody");
    if(!tb) return;
    const query = (q||"").trim().toLowerCase();
    let list = rows || [];
    if(query) list = list.filter(x => (x.rid||"").toLowerCase().includes(query));
    const shown = list.slice(0, pageSize);

    qs("#vsp_p471_shown") && (qs("#vsp_p471_shown").textContent = "Shown: " + shown.length);
    tb.innerHTML = "";
    if(!shown.length) {{
      tb.innerHTML = `<tr><td colspan="4" style="opacity:.75">No runs.</td></tr>`;
      return;
    }}
    for(const r of shown) {{
      const tr = document.createElement("tr");
      const date = r.ts ? fmtTs(r.ts) : (r.label||"");
      tr.innerHTML = `
        <td style="font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;">${r.rid}</td>
        <td style="opacity:.9">${date}</td>
        <td style="opacity:.8">UNKNOWN</td>
        <td>
          <div class="vsp-p471-actions">
            <span class="vsp-p471-pill" data-act="use" data-rid="${r.rid}">Use RID</span>
            <span class="vsp-p471-pill" data-act="dash" data-rid="${r.rid}">Dashboard</span>
            <span class="vsp-p471-pill" data-act="csv" data-rid="${r.rid}">CSV</span>
            <span class="vsp-p471-pill" data-act="tgz" data-rid="${r.rid}">TGZ</span>
          </div>
        </td>
      `;
      tb.appendChild(tr);
    }}
  }}

  async function wireActions(allRows) {{
    const pageSel = qs("#vsp_p471_page");
    const qInp = qs("#vsp_p471_q");
    const refreshBtn = qs("#vsp_p471_refresh");
    const openRunsBtn = qs("#vsp_p471_open_runs");

    let pageSize = 20;
    let q = "";

    const rerender = ()=>renderRows(allRows, pageSize, q);

    pageSel && pageSel.addEventListener("change", ()=>{{
      pageSize = Number(pageSel.value||"20")||20;
      rerender();
    }});
    qInp && qInp.addEventListener("input", ()=>{{
      q = qInp.value||"";
      rerender();
    }});
    refreshBtn && refreshBtn.addEventListener("click", async ()=>{{
      await boot(true);
    }});
    openRunsBtn && openRunsBtn.addEventListener("click", ()=>{{
      const rid = getRidFromUrl();
      const u = rid ? ("/runs?rid="+encodeURIComponent(rid)) : "/runs";
      window.open(u, "_blank");
    }});

    document.addEventListener("click", async (ev)=>{{
      const t = ev.target;
      if(!t || !t.getAttribute) return;
      const act = t.getAttribute("data-act");
      const rid = t.getAttribute("data-rid");
      if(!act || !rid) return;

      if(act==="use") return setRid(rid);
      if(act==="dash") return (location.href = "/c/dashboard?rid=" + encodeURIComponent(rid));
      if(act==="csv") {{
        const u = await guessDownload("csv", rid);
        if(u) window.open(u, "_blank");
        else alert("CSV endpoint not found (tried common candidates).");
      }}
      if(act==="tgz") {{
        const u = await guessDownload("tgz", rid);
        if(u) window.open(u, "_blank");
        else alert("TGZ endpoint not found (tried common candidates).");
      }}
    }}, true);

    // Scan UI
    const out = qs("#vsp_p471_scan_out");
    const ridChip = qs("#vsp_p471_scan_rid");
    const startBtn = qs("#vsp_p471_start");
    const pollBtn = qs("#vsp_p471_poll");
    const targetInp = qs("#vsp_p471_target");
    const noteInp = qs("#vsp_p471_note");
    const modeSel = qs("#vsp_p471_mode");

    async function postRun() {{
      const target = (targetInp?.value||"").trim();
      const note = (noteInp?.value||"").trim();
      const mode = (modeSel?.value||"FULL").trim();
      if(!target) return alert("Target path is empty.");

      out && (out.textContent = "Starting…");
      try {{
        const r = await fetch("/api/vsp/run_v1", {{
          method:"POST",
          headers:{{"Content-Type":"application/json"}},
          credentials:"same-origin",
          body: JSON.stringify({{target_path: target, mode, note}})
        }});
        const j = await r.json().catch(()=>null);
        const rid = (j && (j.rid||j.run_id)) ? String(j.rid||j.run_id) : "";
        ridChip && (ridChip.textContent = "RID: " + (rid||"(unknown)"));
        out && (out.textContent = JSON.stringify(j||{{status:r.status}}, null, 2));
      }} catch(e) {{
        out && (out.textContent = "Start failed: " + String(e));
      }}
    }}

    async function poll() {{
      out && (out.textContent = "Polling…");
      try {{
        const r = await fetch("/api/vsp/run_status_v1", {{credentials:"same-origin"}});
        const j = await r.json().catch(()=>null);
        out && (out.textContent = JSON.stringify(j||{{status:r.status}}, null, 2));
      }} catch(e) {{
        out && (out.textContent = "Poll failed: " + String(e));
      }}
    }}

    startBtn && startBtn.addEventListener("click", postRun);
    pollBtn && pollBtn.addEventListener("click", poll);
  }}

  async function boot(fromRefresh=false) {{
    if(!isCRuns()) return;

    injectStyles();

    // Always mount our UI first, then hide legacy (so we never blank the page)
    const root = ensureMountPoint();
    root.innerHTML = "";
    buildRunsCard(root);
    buildScanCard(root);

    // now hide legacy blocks (safe scope)
    hideLegacySafely();

    const tb = qs("#vsp_p471_tbody");
    tb && (tb.innerHTML = `<tr><td colspan="4" style="opacity:.75">Loading from API…</td></tr>`);

    const r = await fetchRunsAny();
    const rows = (r && r.ok) ? r.items : [];
    qs("#vsp_p471_total") && (qs("#vsp_p471_total").textContent = "Total: " + (r.total||rows.length||0));
    log("runs src:", (r.src||"n/a"), "items:", rows.length, "refresh:", !!fromRefresh);

    renderRows(rows, 20, "");
    await wireActions(rows);
  }}

  // Run
  if(document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", ()=>boot(false), {{once:true}});
  }} else {{
    boot(false);
  }}

}})();
;/* ===================== /VSP_P471_C_RUNS_PRO_SINGLE_V1 ===================== */
"""

# Append
s = (s.rstrip() + "\n\n" + addon + "\n")
f.write_text(s, encoding="utf-8")
print("[OK] wrote", f)
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  systemctl is-active "$SVC" || true
else
  echo "[WARN] no systemd; please restart service manually" | tee -a "$OUT/log.txt"
fi

echo "[OK] P471 done. Close ALL /c/runs tabs, reopen: http://127.0.0.1:8910/c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
