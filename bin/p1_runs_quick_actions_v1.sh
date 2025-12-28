#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need awk; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# --- locate runs template (avoid guessing wrong file) ---
TPL=""
if [ -f "templates/vsp_runs_reports_v1.html" ]; then
  TPL="templates/vsp_runs_reports_v1.html"
else
  # pick the most likely template containing "Runs" or "runs" and "reports"
  TPL="$(ls -1 templates 2>/dev/null | egrep -i 'runs|reports' | head -n1 || true)"
  [ -n "$TPL" ] && TPL="templates/$TPL"
fi

[ -n "$TPL" ] && [ -f "$TPL" ] || { echo "[ERR] cannot find runs template under templates/ (expected vsp_runs_reports_v1.html)"; exit 2; }

JS="static/js/vsp_runs_quick_actions_v1.js"
mkdir -p static/js

echo "[INFO] template=$TPL"
echo "[INFO] js=$JS"
echo "[INFO] base=$BASE"

# --- backups ---
cp -f "$TPL" "${TPL}.bak_runs_quick_actions_${TS}"
echo "[BACKUP] ${TPL}.bak_runs_quick_actions_${TS}"
if [ -f "$JS" ]; then
  cp -f "$JS" "${JS}.bak_${TS}"
  echo "[BACKUP] ${JS}.bak_${TS}"
fi

# --- write JS (idempotent marker) ---
python3 - <<'PY'
from pathlib import Path
import textwrap

js = Path("static/js/vsp_runs_quick_actions_v1.js")
js.write_text(textwrap.dedent(r"""
/* VSP_P1_RUNS_QUICK_ACTIONS_V1 */
(()=> {
  if (window.__vsp_p1_runs_quick_actions_v1) return;
  window.__vsp_p1_runs_quick_actions_v1 = true;

  const log = (...a)=>console.log("[RunsQuickV1]", ...a);
  const warn = (...a)=>console.warn("[RunsQuickV1]", ...a);

  const API = {
    runs: "/api/vsp/runs",
    exportCsv: "/api/vsp/export_csv",
    exportTgz: "/api/vsp/export_tgz",
    runFile: "/api/vsp/run_file",
    openFolder: "/api/vsp/open_folder", // optional (may not exist)
  };

  function qs(sel, root=document){ return root.querySelector(sel); }
  function qsa(sel, root=document){ return Array.from(root.querySelectorAll(sel)); }

  function el(tag, attrs={}, children=[]){
    const n = document.createElement(tag);
    for (const [k,v] of Object.entries(attrs||{})){
      if (k === "class") n.className = v;
      else if (k === "html") n.innerHTML = v;
      else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, String(v));
    }
    for (const c of (children||[])){
      if (c == null) continue;
      n.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    }
    return n;
  }

  function injectStyles(){
    const css = `
      .vsp-runsqa-wrap{padding:12px 0 0 0}
      .vsp-runsqa-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0 12px 0}
      .vsp-runsqa-toolbar input,.vsp-runsqa-toolbar select{background:#0f172a;color:#e5e7eb;border:1px solid #24314f;border-radius:10px;padding:8px 10px;outline:none}
      .vsp-runsqa-btn{background:#111827;color:#e5e7eb;border:1px solid #24314f;border-radius:10px;padding:7px 10px;cursor:pointer}
      .vsp-runsqa-btn:hover{filter:brightness(1.08)}
      .vsp-runsqa-mini{font-size:12px;opacity:.85}
      .vsp-runsqa-table{width:100%;border-collapse:separate;border-spacing:0 8px}
      .vsp-runsqa-row{background:#0b1220;border:1px solid #1f2a44}
      .vsp-runsqa-row td{padding:10px 10px;border-top:1px solid #1f2a44;border-bottom:1px solid #1f2a44}
      .vsp-runsqa-row td:first-child{border-left:1px solid #1f2a44;border-top-left-radius:12px;border-bottom-left-radius:12px}
      .vsp-runsqa-row td:last-child{border-right:1px solid #1f2a44;border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;border:1px solid #24314f;font-size:12px}
      .vsp-badge.ok{background:#06281b}
      .vsp-badge.amber{background:#2a1c06}
      .vsp-badge.bad{background:#2a0b0b}
      .vsp-badge.dim{opacity:.8}
      .vsp-actions{display:flex;flex-wrap:wrap;gap:6px}
      .vsp-toast{position:fixed;right:16px;bottom:16px;background:#0b1220;border:1px solid #24314f;color:#e5e7eb;padding:10px 12px;border-radius:12px;max-width:420px;box-shadow:0 8px 28px rgba(0,0,0,.35);z-index:99999}
    `;
    const s = el("style",{});
    s.textContent = css;
    document.head.appendChild(s);
  }

  function toast(msg, ms=2200){
    const t = el("div",{class:"vsp-toast"},[msg]);
    document.body.appendChild(t);
    setTimeout(()=>{ try{ t.remove(); }catch(e){} }, ms);
  }

  function safeText(x){
    if (x === null || x === undefined) return "";
    if (typeof x === "string") return x;
    try { return JSON.stringify(x); } catch(e){ return String(x); }
  }

  function pickRid(run){
    return run.run_id || run.rid || run.req_id || run.id || run.RID || run.request_id || "";
  }

  function pickOverall(run){
    return (run.overall || run.overall_status || run.status || run.result || run.verdict || "").toString().toUpperCase();
  }

  function pickDegraded(run){
    if (typeof run.degraded === "boolean") return run.degraded;
    if (typeof run.any_degraded === "boolean") return run.any_degraded;
    if (typeof run.tools_degraded === "boolean") return run.tools_degraded;
    if (typeof run.degraded_tools_count === "number") return run.degraded_tools_count > 0;
    if (typeof run.tools_degraded_count === "number") return run.tools_degraded_count > 0;

    // heuristic: any key contains "degraded": true
    try{
      for (const [k,v] of Object.entries(run)){
        if (k.toLowerCase().includes("degraded") && v === True) return true;
        if (k.toLowerCase().includes("degraded") && v === true) return true;
      }
    }catch(e){}
    return false;
  }

  function parseTs(run){
    const raw = run.ts || run.created_at || run.started_at || run.time || run.date || "";
    if (raw){
      const d = new Date(raw);
      if (!isNaN(d.getTime())) return d;
    }
    const rid = pickRid(run);
    // try RID suffix _YYYYmmdd_HHMMSS
    const m = rid.match(/(\d{8})_(\d{6})/);
    if (m){
      const y=m[1].slice(0,4), mo=m[1].slice(4,6), da=m[1].slice(6,8);
      const hh=m[2].slice(0,2), mm=m[2].slice(2,4), ss=m[2].slice(4,6);
      const d = new Date(`${y}-${mo}-${da}T${hh}:${mm}:${ss}`);
      if (!isNaN(d.getTime())) return d;
    }
    return null;
  }

  function fmtDate(d){
    if (!d) return "";
    const pad=n=>String(n).padStart(2,"0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  async function fetchRuns(limit=200){
    // try best-effort params; backend may ignore unknown
    const url = `${API.runs}?limit=${encodeURIComponent(String(limit))}`;
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`runs http ${r.status}`);
    const data = await r.json();

    // tolerate shapes: [] or {runs:[...]} or {items:[...]}
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.runs)) return data.runs;
    if (Array.isArray(data.items)) return data.items;
    if (Array.isArray(data.data)) return data.data;
    return [];
  }

  async function tryOpenUrlCandidates(candidates){
    for (const u of candidates){
      try{
        const rr = await fetch(u, {method:"GET", cache:"no-store"});
        if (rr.ok){
          // If it's downloadable, opening direct URL is better than blob (keeps filename/headers)
          window.open(u, "_blank", "noopener");
          return true;
        }
      }catch(e){}
    }
    // fallback open first anyway
    window.open(candidates[0], "_blank", "noopener");
    return false;
  }

  async function downloadCsv(rid){
    const ridEnc = encodeURIComponent(rid);
    const cands = [
      `${API.exportCsv}?rid=${ridEnc}`,
      `${API.exportCsv}?run_id=${ridEnc}`,
      `${API.exportCsv}?req_id=${ridEnc}`,
    ];
    await tryOpenUrlCandidates(cands);
  }

  async function downloadTgz(rid){
    const ridEnc = encodeURIComponent(rid);
    const cands = [
      `${API.exportTgz}?rid=${ridEnc}`,
      `${API.exportTgz}?run_id=${ridEnc}`,
      `${API.exportTgz}?req_id=${ridEnc}`,
    ];
    await tryOpenUrlCandidates(cands);
  }

  async function openRunFile(rid, path){
    const ridEnc = encodeURIComponent(rid);
    const pathEnc = encodeURIComponent(path);
    const cands = [
      `${API.runFile}?rid=${ridEnc}&path=${pathEnc}`,
      `${API.runFile}?run_id=${ridEnc}&path=${pathEnc}`,
      `${API.runFile}?req_id=${ridEnc}&path=${pathEnc}`,
      `${API.runFile}?rid=${ridEnc}&file=${pathEnc}`,
      `${API.runFile}?run_id=${ridEnc}&file=${pathEnc}`,
      `${API.runFile}?rid=${ridEnc}&name=${pathEnc}`,
    ];
    await tryOpenUrlCandidates(cands);
  }

  async function openFolder(rid){
    const ridEnc = encodeURIComponent(rid);
    const cands = [
      `${API.openFolder}?rid=${ridEnc}`,
      `${API.openFolder}?run_id=${ridEnc}`,
      `${API.openFolder}?req_id=${ridEnc}`,
    ];
    // if unsupported, show toast
    try{
      const r = await fetch(cands[0], {method:"GET", cache:"no-store"});
      if (!r.ok) {
        toast("open folder: backend chưa hỗ trợ (404/!ok)");
        return;
      }
      // if backend opens folder on server, it may return text
      toast("open folder: OK");
    }catch(e){
      toast("open folder: backend chưa hỗ trợ");
    }
  }

  function badgeForOverall(overall){
    const o = (overall||"").toUpperCase();
    if (o.includes("GREEN") || o==="OK" || o==="PASS") return el("span",{class:"vsp-badge ok"},[o||"OK"]);
    if (o.includes("AMBER") || o.includes("WARN") || o==="WARNING") return el("span",{class:"vsp-badge amber"},[o||"AMBER"]);
    if (o.includes("RED") || o.includes("FAIL") || o==="ERROR") return el("span",{class:"vsp-badge bad"},[o||"FAIL"]);
    return el("span",{class:"vsp-badge dim"},[o||"UNKNOWN"]);
  }

  function buildUI(mount){
    injectStyles();

    const wrap = el("div",{class:"vsp-runsqa-wrap"});
    const title = el("div",{class:"vsp-runsqa-mini"},[
      "Quick Actions: filter nhanh + 1-click export/open (CSV/TGZ/JSON/HTML), copy RID, open folder (nếu backend hỗ trợ)."
    ]);

    const ridIn = el("input",{type:"text",placeholder:"Search RID…",style:"min-width:240px"});
    const overallSel = el("select",{},[
      el("option",{value:""},["Overall: ALL"]),
      el("option",{value:"GREEN"},["GREEN"]),
      el("option",{value:"AMBER"},["AMBER"]),
      el("option",{value:"RED"},["RED"]),
      el("option",{value:"PASS"},["PASS/OK"]),
      el("option",{value:"FAIL"},["FAIL/ERROR"]),
    ]);
    const degrSel = el("select",{},[
      el("option",{value:""},["Degraded: ALL"]),
      el("option",{value:"true"},["Degraded: YES"]),
      el("option",{value:"false"},["Degraded: NO"]),
    ]);
    const fromIn = el("input",{type:"date"});
    const toIn = el("input",{type:"date"});
    const refreshBtn = el("button",{class:"vsp-runsqa-btn"},["Refresh"]);
    const clearBtn = el("button",{class:"vsp-runsqa-btn"},["Clear"]);
    const stat = el("span",{class:"vsp-runsqa-mini"},["…"]);

    const toolbar = el("div",{class:"vsp-runsqa-toolbar"},[
      ridIn, overallSel, degrSel,
      el("span",{class:"vsp-runsqa-mini"},["From"]), fromIn,
      el("span",{class:"vsp-runsqa-mini"},["To"]), toIn,
      refreshBtn, clearBtn, stat
    ]);

    const table = el("table",{class:"vsp-runsqa-table"});
    const thead = el("thead",{},[
      el("tr",{},[
        el("th",{},["RID"]),
        el("th",{},["Date"]),
        el("th",{},["Overall"]),
        el("th",{},["Degraded"]),
        el("th",{},["Actions"]),
      ])
    ]);
    const tbody = el("tbody",{});
    table.appendChild(thead); table.appendChild(tbody);

    wrap.appendChild(title);
    wrap.appendChild(toolbar);
    wrap.appendChild(table);

    mount.appendChild(wrap);

    let runsCache = [];

    function passesFilters(run){
      const rid = pickRid(run);
      const overall = pickOverall(run);
      const degraded = pickDegraded(run);
      const ts = parseTs(run);

      const q = ridIn.value.trim().toLowerCase();
      if (q && !String(rid).toLowerCase().includes(q)) return false;

      const o = overallSel.value.trim().toUpperCase();
      if (o){
        // allow bucket match
        if (o==="PASS" && !(overall.includes("PASS") || overall.includes("OK") || overall.includes("GREEN"))) return false;
        else if (o==="FAIL" && !(overall.includes("FAIL") || overall.includes("ERROR") || overall.includes("RED"))) return false;
        else if (o==="GREEN" && !overall.includes("GREEN")) return false;
        else if (o==="AMBER" && !overall.includes("AMBER")) return false;
        else if (o==="RED" && !overall.includes("RED")) return false;
      }

      const dsel = degrSel.value;
      if (dsel==="true" && !degraded) return false;
      if (dsel==="false" && degraded) return false;

      // date range (local)
      const from = fromIn.value ? new Date(fromIn.value + "T00:00:00") : null;
      const to = toIn.value ? new Date(toIn.value + "T23:59:59") : null;
      if ((from || to) && ts){
        if (from && ts < from) return false;
        if (to && ts > to) return false;
      } else if ((from || to) && !ts){
        // if run has no parsable date, keep it (avoid hiding data unexpectedly)
      }

      return true;
    }

    function render(){
      const filtered = runsCache.filter(passesFilters);

      // sort newest first (by parsed ts if possible, else keep order)
      filtered.sort((a,b)=>{
        const ta=parseTs(a), tb=parseTs(b);
        if (ta && tb) return tb.getTime() - ta.getTime();
        if (ta && !tb) return -1;
        if (!ta && tb) return 1;
        return 0;
      });

      tbody.innerHTML = "";
      for (const run of filtered){
        const rid = pickRid(run);
        const overall = pickOverall(run);
        const degraded = pickDegraded(run);
        const ts = parseTs(run);

        const ridCell = el("td",{},[
          el("div",{},[ String(rid||"(no rid)") ]),
          el("div",{class:"vsp-runsqa-mini"},[
            el("button",{class:"vsp-runsqa-btn", onclick: async ()=> {
              try{ await navigator.clipboard.writeText(String(rid||"")); toast("Copied RID"); }
              catch(e){ toast("Copy failed"); }
            }},["Copy RID"]),
            " ",
            el("button",{class:"vsp-runsqa-btn", onclick: async ()=> openFolder(String(rid||""))},["Open folder"]),
          ])
        ]);

        const dtCell = el("td",{},[ fmtDate(ts) || "-" ]);
        const ovCell = el("td",{},[ badgeForOverall(overall) ]);
        const dgCell = el("td",{},[
          degraded ? el("span",{class:"vsp-badge amber"},["DEGRADED"]) : el("span",{class:"vsp-badge ok"},["OK"])
        ]);

        const actions = el("div",{class:"vsp-actions"},[
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=> downloadCsv(String(rid||""))},["CSV"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=> downloadTgz(String(rid||""))},["TGZ"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=> openRunFile(String(rid||""), "run_gate.json")},["Open JSON"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=> openRunFile(String(rid||""), "reports/findings_unified.html")},["Open HTML"]),
        ]);

        const tr = el("tr",{class:"vsp-runsqa-row"},[
          ridCell, dtCell, ovCell, dgCell, el("td",{},[actions])
        ]);
        tbody.appendChild(tr);
      }
      stat.textContent = `Runs: ${filtered.length}/${runsCache.length}`;
    }

    async function load(){
      stat.textContent = "Loading…";
      try{
        const runs = await fetchRuns(300);
        runsCache = Array.isArray(runs) ? runs : [];
        render();
        log("loaded runs:", runsCache.length);
      }catch(e){
        warn("load failed:", e);
        stat.textContent = "Load failed (see console)";
        toast("Load runs failed — check /api/vsp/runs");
      }
    }

    // events
    [ridIn, overallSel, degrSel, fromIn, toIn].forEach(x=>x.addEventListener("input", render));
    refreshBtn.addEventListener("click", load);
    clearBtn.addEventListener("click", ()=>{
      ridIn.value=""; overallSel.value=""; degrSel.value=""; fromIn.value=""; toIn.value="";
      render();
    });

    load();
  }

  function mount(){
    // Try to find an existing runs container; fallback to body.
    const prefer =
      qs("#vspRunsQuickActionsV1") ||
      qs("[data-vsp-runs-root]") ||
      qs("#runs") ||
      qs("#runs-root") ||
      qs("main") ||
      qs(".container") ||
      document.body;

    const anchor = el("div",{id:"vspRunsQuickActionsV1"});
    // insert near top of prefer container
    if (prefer === document.body){
      document.body.insertBefore(anchor, document.body.firstChild);
    } else {
      prefer.insertBefore(anchor, prefer.firstChild);
    }
    buildUI(anchor);
    log("loaded + running");
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
""").lstrip(), encoding="utf-8")
print("[OK] wrote", js)
PY

# --- patch template: add a stable mount + include JS once ---
python3 - <<'PY'
from pathlib import Path
import re

tpl = Path(r"""'"$TPL"'" """)
s = tpl.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_QUICK_ACTIONS_V1"
if marker in s:
    print("[OK] template already patched:", tpl)
else:
    # 1) ensure a mount node exists (harmless even if JS creates one)
    mount_html = '\n<!-- VSP_P1_RUNS_QUICK_ACTIONS_V1 -->\n<div id="vspRunsQuickActionsV1"></div>\n'
    if "vspRunsQuickActionsV1" not in s:
        # insert right after <body ...> if possible
        s2, n = re.subn(r'(<body\b[^>]*>)', r'\1' + mount_html, s, count=1, flags=re.I)
        if n == 0:
            # fallback: before </body>
            s2, n = re.subn(r'(</body\s*>)', mount_html + r'\1', s, count=1, flags=re.I)
        s = s2

    # 2) include JS before </body> (respect asset_v if present)
    js_tag = '\n<script src="/static/js/vsp_runs_quick_actions_v1.js?v={{ asset_v }}"></script>\n'
    # If template doesn't have asset_v, still safe: Jinja may render empty; else leave as-is
    if "vsp_runs_quick_actions_v1.js" not in s:
        s2, n = re.subn(r'(</body\s*>)', js_tag + r'\1', s, count=1, flags=re.I)
        if n == 0:
            s += "\n" + js_tag
        else:
            s = s2

    tpl.write_text(s, encoding="utf-8")
    print("[OK] patched template:", tpl)
PY

# --- restart (best-effort, keep stable) ---
restart_ok=0
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -qE '^vsp-ui-8910\.service'; then
    echo "[INFO] systemctl restart vsp-ui-8910.service"
    sudo systemctl restart vsp-ui-8910.service || true
    restart_ok=1
  fi
fi

if [ "$restart_ok" -eq 0 ]; then
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    echo "[INFO] restart via bin/p1_ui_8910_single_owner_start_v2.sh"
    rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
    bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[WARN] no systemd service and no start script found; please restart UI manually"
  fi
fi

# --- probe quick (do NOT touch /vsp5 logic) ---
echo "== PROBE 5 tabs =="
curl -fsS -I "$BASE/" | head -n 5
curl -fsS -I "$BASE/vsp5" | head -n 5
curl -fsS -I "$BASE/runs" | head -n 5 || true
curl -fsS -I "$BASE/data_source" | head -n 5
curl -fsS -I "$BASE/settings" | head -n 5
curl -fsS -I "$BASE/rule_overrides" | head -n 5

echo "== PROBE runs api =="
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo

echo "[DONE] Runs & Reports Quick Actions V1 patched. Open tab Runs & Reports and check console: [RunsQuickV1] loaded + running"
