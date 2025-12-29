/* VSP_P120_C_COMMON_SHIM_V1
 * Purpose:
 * - Provide a stable global window.VSPC for /c/* suite
 * - Fix: "Cannot read properties of undefined (reading 'onRefresh')"
 * - Provide refresh event bus + RID resolution (latest) + fetchJSON with timeout
 */
(function(){
  'use strict';

  const log = (...a)=>{ try{ console.log('[VSPC]', ...a); }catch(e){} };
  const warn = (...a)=>{ try{ console.warn('[VSPC]', ...a); }catch(e){} };

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function sanitizeRid(x){
    x = (x||'').toString().trim();
    // allow VSP_CI_YYYYmmdd_HHMMSS and RUN_* style, block accidental "VSP_FILL_..." junk
    if(!x) return '';
    if(x.length > 128) return '';
    if(!/^[A-Za-z0-9_.:-]+$/.test(x)) return '';
    if(/^VSP_FILL_/i.test(x)) return '';
    return x;
  }

  function getUrlParam(name){
    try{
      const u = new URL(window.location.href);
      return u.searchParams.get(name) || '';
    }catch(e){ return ''; }
  }

  function setUrlParam(name, value){
    try{
      const u = new URL(window.location.href);
      if(value) u.searchParams.set(name, value);
      else u.searchParams.delete(name);
      history.replaceState({}, '', u.toString());
    }catch(e){}
  }

  async function fetchJSON(url, opt){
    opt = opt || {};
    const timeoutMs = opt.timeoutMs || 2500;
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, cache:'no-store', credentials:'same-origin'});
      const ct = (r.headers.get('content-type')||'').toLowerCase();
      const txt = await r.text();
      let j = null;
      if(ct.includes('application/json')){
        try{ j = JSON.parse(txt); }catch(e){ j = null; }
      }else{
        // best effort JSON parse
        try{ j = JSON.parse(txt); }catch(e){ j = null; }
      }
      return {ok: r.ok, status: r.status, json: j, text: txt, headers: r.headers};
    }catch(e){
      return {ok:false, status:0, json:null, text:String(e)};
    }finally{
      clearTimeout(t);
    }
  }

  async function resolveLatestRid(base){
    const url = `${base}/api/vsp/runs_v3?limit=1&include_ci=1`;
    const r = await fetchJSON(url, {timeoutMs: 2500});
    try{
      const rid = sanitizeRid(r.json && r.json.items && r.json.items[0] && r.json.items[0].rid);
      return rid || '';
    }catch(e){ return ''; }
  }

  function dispatchRefresh(){
    try{
      window.dispatchEvent(new CustomEvent('vsp:refresh', {detail:{ts: Date.now()}}));
    }catch(e){}
  }

  function onRefresh(fn){
    window.addEventListener('vsp:refresh', (ev)=>{ try{ fn(ev); }catch(e){} });
  }

  function ensureHeaderHook(){
    // try attach refresh button (id-based first, fallback by text)
    const btn = qs('#b-refresh') || qsa('button').find(b => (b.textContent||'').trim().toUpperCase() === 'REFRESH');
    if(btn && !btn.__vspc_bound){
      btn.__vspc_bound = 1;
      btn.addEventListener('click', ()=>dispatchRefresh());
    }
  }

  function setText(id, txt){
    const el = qs('#'+id);
    if(el) el.textContent = (txt==null?'':String(txt));
  }

  const base = (function(){
    try{ return window.location.origin; }catch(e){ return ''; }
  })();

  // Export global
  window.VSPC = window.VSPC || {};
  Object.assign(window.VSPC, {
    ver: 'P120',
    base,
    sanitizeRid,
    getUrlParam,
    setUrlParam,
    fetchJSON,
    resolveLatestRid,
    onRefresh,
    dispatchRefresh,
    setText,
    ensureHeaderHook
  });

  // bind header on load
  document.addEventListener('DOMContentLoaded', ()=>{
    try{
      ensureHeaderHook();
      log('installed', window.VSPC.ver);
    }catch(e){}
  });
})();


/* VSP_P122_POLISH_C_SUITE_COLORS_AND_RUNS_V1
 * - Make /c/* look consistent (dark pill buttons instead of blue links)
 * - Auto-style action links in Runs tab (Dashboard/CSV/Reports.tgz/Use RID...)
 */
(function(){
  try{
    var path = (location && location.pathname) ? String(location.pathname) : "";
    var page = "";
    if (path.startsWith("/c/")) {
      var seg = path.split("/").filter(Boolean);
      page = "c-" + (seg[1] || "dashboard");
    }
    // dataset markers for CSS targeting
    try{
      document.documentElement.dataset.vspSuite = "c";
      document.documentElement.dataset.vspPage = page;
      if (document.body){
        document.body.dataset.vspSuite = "c";
        document.body.dataset.vspPage = page;
      }
    }catch(_){}

    // inject CSS once
    var STYLE_ID="VSP_P122_STYLE";
    if (!document.getElementById(STYLE_ID)){
      var st=document.createElement("style");
      st.id=STYLE_ID;
      st.textContent = `
/* --- P122 C-suite theme polish --- */
[data-vsp-suite="c"] a{ color:rgba(210,225,255,.92); text-decoration:none; }
[data-vsp-suite="c"] a:hover{ text-decoration:underline; }

/* generic pill for action links (we add class in JS too) */
[data-vsp-suite="c"] a.vsp-btnlink{
  display:inline-block;
  padding:4px 10px;
  margin-right:6px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
  line-height:1.2;
}
[data-vsp-suite="c"] a.vsp-btnlink:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}

/* button polish (Use RID etc) */
[data-vsp-suite="c"] button.vsp-btn{
  padding:5px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  cursor:pointer;
}
[data-vsp-suite="c"] button.vsp-btn:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}
[data-vsp-suite="c"] button.vsp-btn.vsp-btn-mini{
  padding:4px 10px;
  font-size:12px;
}

/* Runs tab: treat table links like buttons even if no class */
[data-vsp-page="c-runs"] table a{
  display:inline-block;
  padding:4px 10px;
  margin-right:6px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
  line-height:1.2;
}
[data-vsp-page="c-runs"] table a:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}

/* soften “link blue” in headers/toolstrips */
[data-vsp-suite="c"] .vsp-toolbar a,
[data-vsp-suite="c"] .toolbar a{
  display:inline-block;
  padding:4px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.05);
  border:1px solid rgba(255,255,255,.12);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
}
[data-vsp-suite="c"] .vsp-toolbar a:hover,
[data-vsp-suite="c"] .toolbar a:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}
      `;
      document.head.appendChild(st);
    }

    // JS class helper: “button-hoá” một số link action phổ biến
    var WANT = {
      "dashboard":1, "csv":1, "reports.tgz":1, "reports":1, "html":1, "sarif":1, "summary":1, "open":1, "sha":1, "use rid":1
    };

    var _scheduled = false;
    function polish(){
      _scheduled = false;
      try{
        var as = document.querySelectorAll("a");
        for (var i=0;i<as.length;i++){
          var a=as[i];
          var t=(a.textContent||"").trim().toLowerCase();
          if (WANT[t]) a.classList.add("vsp-btnlink");
        }
        var bs = document.querySelectorAll("button");
        for (var j=0;j<bs.length;j++){
          var b=bs[j];
          var tb=(b.textContent||"").trim().toLowerCase();
          if (tb==="use rid" || tb==="refresh" || tb==="load" || tb==="save" || tb==="export"){
            b.classList.add("vsp-btn","vsp-btn-mini");
          }
        }
      }catch(_){}
    }
    function schedule(){
      if (_scheduled) return;
      _scheduled = true;
      (window.requestAnimationFrame||setTimeout)(polish, 16);
    }

    schedule();
    window.addEventListener("load", schedule, {once:true});
    try{
      new MutationObserver(schedule).observe(document.documentElement, {subtree:true, childList:true});
    }catch(_){}
  }catch(e){
    try{ console.warn("[P122] polish failed", e); }catch(_){}
  }
})();


/* ===== VSP_P123_POLISH_CSUITE_LAYOUT_V1 ===== */
;(function(){
  if (window.__VSP_P123__) return;
  window.__VSP_P123__ = 1;

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }

  function addStyle(id, css){
    if (document.getElementById(id)) return;
    const st = document.createElement("style");
    st.id = id;
    st.textContent = css;
    document.head.appendChild(st);
  }

  function normText(el){
    return (el && el.textContent ? el.textContent.trim().toLowerCase() : "");
  }

  function hideLegacyTables(){
    // Hide tables that look like legacy header tables (only <thead> or very few rows)
    const tables = Array.from(document.querySelectorAll("table"));
    for (const t of tables){
      try{
        const ths = Array.from(t.querySelectorAll("thead th")).map(x=>normText(x)).filter(Boolean);
        const rows = t.querySelectorAll("tbody tr").length;
        const looksLikeLegacyHeader =
          ths.length >= 4 && ths.includes("rid") && (ths.includes("actions") || ths.includes("overall") || ths.includes("summary"));
        if (looksLikeLegacyHeader && rows <= 1){
          t.style.display = "none";
        }
      }catch(_){}
    }
  }

  function decorateActionChips(){
    // Turn all “action” links/buttons into consistent chips (Runs tab is the biggest win)
    const els = Array.from(document.querySelectorAll("a,button"));
    for (const el of els){
      const t = normText(el);
      if (!t) continue;

      const isAction =
        ["dashboard","csv","reports.tgz","reports","sarif","html","summary","use rid","open","sha","refresh","load","save","export","json"].includes(t);

      if (!isAction) continue;

      el.classList.add("vsp-chip");
      if (t === "dashboard") el.classList.add("vsp-chip--primary");
      else if (t === "use rid") el.classList.add("vsp-chip--accent");
      else if (t === "refresh" || t === "load") el.classList.add("vsp-chip--ghost");
      else el.classList.add("vsp-chip--muted");
    }
  }

  function polishTables(){
    // Add classes to big tables to apply zebra/hover/spacing
    const tables = Array.from(document.querySelectorAll("table"));
    for (const t of tables){
      // Skip tiny layout tables (if any)
      const rows = t.querySelectorAll("tr").length;
      if (rows < 3) continue;
      t.classList.add("vsp-table");
    }
  }

  function collapseHugePre(){
    // Collapse very large <pre> blocks (Settings/Rule Overrides raw JSON) into <details>
    const pres = Array.from(document.querySelectorAll("pre"));
    for (const pre of pres){
      try{
        const txt = (pre.textContent || "").trim();
        if (!txt) continue;
        // Heuristic: looks like JSON and is long
        const looksJson = (txt.startsWith("{") && txt.endsWith("}")) || (txt.startsWith("[") && txt.endsWith("]"));
        const lines = txt.split("\n").length
        const VSP_P127_MINLINES = (/(?:^|\/)c\/(settings|rule_overrides)(?:$|)/.test((location.pathname||"")));
        const minLines = VSP_P127_MINLINES ? 8 : 30;
        if (!looksJson || lines < minLines) continue;

        // avoid double wrap
        if (pre.closest("details")) continue;

        const details = document.createElement("details");
        details.className = "vsp-details";
        details.open = false;

        const sum = document.createElement("summary");
        sum.textContent = "Raw JSON (click to expand)";
        details.appendChild(sum);

        // Keep the pre but constrain height
        pre.classList.add("vsp-pre");
        details.appendChild(pre.cloneNode(true));
        pre.replaceWith(details);
      }catch(_){}
    }
  }

  onReady(function(){
    addStyle("vsp-p123-style", `
      :root{
        --vsp-bg0:#0b1220;
        --vsp-bg1:#0f1a2d;
        --vsp-card:rgba(255,255,255,.035);
        --vsp-card2:rgba(255,255,255,.055);
        --vsp-border:rgba(255,255,255,.08);
        --vsp-border2:rgba(255,255,255,.12);
        --vsp-text:rgba(255,255,255,.86);
        --vsp-text2:rgba(255,255,255,.68);
        --vsp-blue:rgba(96,165,250,.95);
        --vsp-cyan:rgba(34,211,238,.92);
      }

      /* Tables */
      table.vsp-table{
        width:100%;
        border-collapse:separate;
        border-spacing:0;
        background:var(--vsp-card);
        border:1px solid var(--vsp-border);
        border-radius:14px;
        overflow:hidden;
      }
      table.vsp-table thead th{
        text-transform:uppercase;
        letter-spacing:.06em;
        font-size:11px;
        color:var(--vsp-text2);
        background:rgba(255,255,255,.03);
        border-bottom:1px solid var(--vsp-border);
        padding:10px 12px;
      }
      table.vsp-table tbody td{
        padding:10px 12px;
        border-bottom:1px solid rgba(255,255,255,.06);
        color:var(--vsp-text);
        font-size:12px;
      }
      table.vsp-table tbody tr:nth-child(odd){
        background:rgba(255,255,255,.018);
      }
      table.vsp-table tbody tr:hover{
        background:rgba(96,165,250,.08);
      }
      table.vsp-table tbody td:first-child{
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size:11.5px;
        color:rgba(255,255,255,.78);
      }

      /* Chips */
      .vsp-chip{
        display:inline-flex;
        align-items:center;
        justify-content:center;
        gap:6px;
        padding:5px 10px;
        margin-right:8px;
        border-radius:999px;
        border:1px solid var(--vsp-border2);
        background:rgba(255,255,255,.03);
        color:rgba(255,255,255,.86) !important;
        font-size:12px;
        line-height:1;
        text-decoration:none !important;
        cursor:pointer;
        transition:transform .08s ease, background .12s ease, border-color .12s ease;
      }
      .vsp-chip:hover{ transform:translateY(-1px); background:rgba(255,255,255,.06); border-color:rgba(255,255,255,.18); }
      .vsp-chip--primary{ border-color:rgba(96,165,250,.45); background:rgba(96,165,250,.12); }
      .vsp-chip--accent{ border-color:rgba(34,211,238,.45); background:rgba(34,211,238,.10); }
      .vsp-chip--muted{ border-color:rgba(255,255,255,.14); background:rgba(255,255,255,.035); }
      .vsp-chip--ghost{ border-color:rgba(255,255,255,.10); background:transparent; }

      /* Collapsible raw JSON */
      .vsp-details{
        background:var(--vsp-card);
        border:1px solid var(--vsp-border);
        border-radius:14px;
        padding:10px 12px;
        margin:10px 0;
      }
      .vsp-details > summary{
        cursor:pointer;
        color:var(--vsp-text2);
        font-size:12px;
        list-style:none;
      }
      .vsp-pre{
        max-height:420px;
        overflow:auto;
        margin-top:10px;
        padding:10px;
        border-radius:12px;
        border:1px solid rgba(255,255,255,.08);
        background:rgba(0,0,0,.22);
      }
    `);

    hideLegacyTables();
    polishTables();
    decorateActionChips();
    collapseHugePre();

    // Re-run after async renders (Runs/DataSource sometimes render later)
    setTimeout(function(){
      hideLegacyTables();
      polishTables();
      decorateActionChips();
      collapseHugePre();
    }, 350);
  });
})();



/* === VSP_P124_C_SUITE_RUNS_CONTRAST_V1 ===
   Goals:
   - Fix low-contrast visited links in Runs table
   - Make buttons (esp. Use RID) dark-theme instead of white
   - Clamp huge JSON <pre> blocks in Settings/Rule Overrides
*/
(function(){
  try{
    if (window.__VSP_P124_CSUITE__) return;
    window.__VSP_P124_CSUITE__ = 1;

    var css = `
/* --- palette knobs --- */
:root{
  --vspc-link: #86c5ff;
  --vspc-link-hover: #b7dcff;
  --vspc-btn-bg: rgba(255,255,255,0.06);
  --vspc-btn-bg-hover: rgba(255,255,255,0.10);
  --vspc-btn-bd: rgba(255,255,255,0.14);
  --vspc-btn-bd-hover: rgba(255,255,255,0.22);
  --vspc-text: rgba(255,255,255,0.88);
  --vspc-muted: rgba(255,255,255,0.68);
}

/* --- links: unify normal/visited to avoid purple shock --- */
.vsp-c a, .vspc a{
  color: var(--vspc-link) !important;
  text-decoration: none;
}
.vsp-c a:visited, .vspc a:visited{
  color: var(--vspc-link) !important;
}
.vsp-c a:hover, .vspc a:hover{
  color: var(--vspc-link-hover) !important;
  text-decoration: underline;
}

/* --- buttons: kill white default buttons --- */
.vsp-c button, .vspc button,
.vsp-c .btn, .vspc .btn{
  background: var(--vspc-btn-bg) !important;
  border: 1px solid var(--vspc-btn-bd) !important;
  color: var(--vspc-text) !important;
  border-radius: 10px !important;
  padding: 6px 10px !important;
  font-size: 12px !important;
  line-height: 1 !important;
  box-shadow: none !important;
}
.vsp-c button:hover, .vspc button:hover,
.vsp-c .btn:hover, .vspc .btn:hover{
  background: var(--vspc-btn-bg-hover) !important;
  border-color: var(--vspc-btn-bd-hover) !important;
}

/* --- Runs table: tighten actions look like pills --- */
.vsp-c table td a, .vsp-c table th a{
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.10);
  margin-right: 6px;
}
.vsp-c table td a:hover{
  background: rgba(255,255,255,0.08);
  border-color: rgba(255,255,255,0.18);
}

/* --- clamp huge JSON blocks --- */
.vsp-c pre, .vspc pre{
  max-height: 280px;
  overflow: auto;
  color: var(--vspc-text);
}
.vsp-c pre, .vspc pre{
  scrollbar-width: thin;
}

/* --- subtle table readability --- */
.vsp-c table{
  color: var(--vspc-text);
}
.vsp-c table tr{
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.vsp-c table tr:hover{
  background: rgba(255,255,255,0.03);
}
`;

    var st = document.getElementById("VSP_P124_STYLE");
    if(!st){
      st = document.createElement("style");
      st.id = "VSP_P124_STYLE";
      st.type = "text/css";
      st.appendChild(document.createTextNode(css));
      (document.head || document.documentElement).appendChild(st);
    }
  }catch(e){
    try{ console.warn("[VSPC] P124 inject failed:", e); }catch(_){}
  }
})();



/* VSP_P125_C_SUITE_CLEANUP_V1 */
(function(){
  try{
    if(!location.pathname.startsWith('/c/')) return;

    function hidePanelByNeedles(needles){
      const els = Array.from(document.querySelectorAll('div,section,article'));
      for(const el of els){
        const t = (el.innerText || '').trim();
        if(!t) continue;
        const hit = needles.every(nd => t.includes(nd));
        if(hit){
          // if it contains the big JSON block, hide the whole container
          if(el.querySelector('pre, textarea')){
            el.style.display = 'none';
            return true;
          }
        }
      }
      return false;
    }

    function p125(){
      const path = location.pathname;

      // Remove the "live JSON" top panels (rác) but keep the editor panels below.
      if(path === '/c/settings' || path.startsWith('/c/settings')){
        hidePanelByNeedles(['Settings (live links', 'tool legend']);
        // fallback: hide panel that shows lots of JSON and has "Tools (8)" + "Exports:"
        hidePanelByNeedles(['Tools (8)', 'Exports:']);
      }

      if(path === '/c/rule_overrides' || path.startsWith('/c/rule_overrides')){
        hidePanelByNeedles(['Rule Overrides (live from', '/api/vsp/rule_overrides']);
        // fallback: hide panel with "Open JSON"
        hidePanelByNeedles(['Open JSON']);
      }
    }

    if(document.readyState === 'loading'){
      document.addEventListener('DOMContentLoaded', p125);
    } else {
      p125();
    }
  }catch(e){
    console.warn('[VSP][P125] cleanup failed', e);
  }
})();

/* VSP_P125_C_SUITE_CONTRAST_V1 */
(function(){
  try{
    if(!location.pathname.startsWith('/c/')) return;
    const css = `
      .vsp-card a, a.vsp-link, .vsp-table a { text-decoration: none; }
      .vsp-card a:hover, a.vsp-link:hover, .vsp-table a:hover { text-decoration: underline; }
    `;
    const st = document.createElement('style');
    st.setAttribute('data-vsp', 'p125');
    st.textContent = css;
    document.head.appendChild(st);
  }catch(_){}
})();

/* VSP_P126_FIX_BOOL_TOKENS_V1
   - replace bare 'and'/'or' tokens to JS '&&'/'||' safely
   - hide legacy live JSON debug panels on Settings / Rule Overrides
*/
(function(){
  try{
    const p = (location && location.pathname) ? location.pathname : "";
    const isSettings = /\/c\/settings\/?$/.test(p);
    const isOverrides = /\/c\/rule_overrides\/?$/.test(p);
    if(!(isSettings || isOverrides)) return;

    // Hide big "live JSON" panels (legacy debug)
    const needles = [
      "live links",
      "live from /api",
      "Rule Overrides (live",
      "Settings (live"
    ];

    const all = Array.from(document.querySelectorAll("h1,h2,h3,div,span"));
    for(const el of all){
      const t = (el.textContent || "").trim();
      if(!t) continue;
      const hit = needles.some(k => t.toLowerCase().includes(k.toLowerCase()));
      if(!hit) continue;

      // climb up to a reasonable panel container
      let box = el;
      for(let k=0;k<8;k++){
        if(!box || !box.parentElement) break;
        const cls = box.className || "";
        if(typeof cls === "string" && (cls.includes("panel") || cls.includes("card") || cls.includes("box") || cls.includes("container"))){
          break;
        }
        box = box.parentElement;
      }
      if(box && box.style){
        box.style.display = "none";
      }
    }

    // Also hide any large PRE blocks near top area (defensive)
    const pres = Array.from(document.querySelectorAll("pre"));
    for(const pre of pres){
      const txt = (pre.textContent || "");
      if(txt.includes('"updated_by"') || txt.includes('"overrides"') || txt.includes('"evidence"')){
        // heuristic: only hide if it is not inside the editor area
        const par = pre.closest(".rule-editor,.editor,.override-editor");
        if(!par){
          pre.style.display = "none";
          const wrap = pre.parentElement;
          if(wrap && wrap.style) wrap.style.display = "none";
        }
      }
    }
  }catch(_){}
})();




/* VSP_P205_JSON_COLLAPSE_GLOBAL_OBSERVER_V1
 * Goal:
 * - Collapse ALL JSON <pre> blocks on /c/settings and /c/rule_overrides (and generally any /c/* pages),
 *   even if DOM is re-rendered later.
 * - Do NOT touch editable textarea editor.
 * - Persist expand/collapse in localStorage so it won't "snap back".
 */
(function(){
  try{
    if (window.__VSP_P205_INSTALLED) { console.log("[VSP] P205 already installed"); return; }
    window.__VSP_P205_INSTALLED = true;

    const PATH = (location && location.pathname) ? location.pathname : "";
    const ENABLE = (PATH.indexOf("/c/") === 0); // only UI suite pages

    function injectStyleOnce(){
      if (document.getElementById("vsp_p205_style")) return;
      const st = document.createElement("style");
      st.id = "vsp_p205_style";
      st.textContent = `
        .vsp-json-togglebar{
          display:flex; align-items:center; justify-content:space-between;
          gap:10px; padding:8px 10px; margin:6px 0 8px 0;
          border-radius:10px;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.08);
          cursor:pointer;
          user-select:none;
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
          font-size: 12px;
          color: rgba(255,255,255,0.85);
        }
        .vsp-json-togglebar:hover{ border-color: rgba(255,255,255,0.16); }
        .vsp-json-togglebar .left{ opacity:0.95; }
        .vsp-json-togglebar .right{ opacity:0.65; font-size:11px; }
        .vsp-json-hidden{ display:none !important; }
      `;
      document.head.appendChild(st);
    }

    function normLines(txt){
      return (txt || "").replace(/\r\n/g,"\n").replace(/\r/g,"\n");
    }
    function looksLikeJson(txt){
      const t = (txt||"").trim();
      if (t.length < 2) return false;
      const a = t[0], b = t[t.length-1];
      if (!((a==="{" && b==="}") || (a==="[" && b==="]"))) return false;
      // avoid tiny JSON (still ok but not needed)
      return true;
    }
    function countLines(txt){
      const t = normLines(txt);
      if (!t) return 0;
      return t.split("\n").length;
    }
    function makeKeyForPre(pre, idx){
      // stable-ish key even if DOM rerenders
      const hint = (pre.id ? ("#"+pre.id) : "") + (pre.className ? ("."+String(pre.className).split(/\s+/).slice(0,3).join(".")) : "");
      return "vsp_p205|" + PATH + "|pre|" + idx + "|" + hint;
    }

    function bindPre(pre, idx){
      if (!pre || pre.nodeType !== 1) return;
      if (pre.dataset && pre.dataset.vspP205Bound === "1") return;

      // only <pre> that looks like JSON
      const txt = pre.textContent || "";
      if (!looksLikeJson(txt)) return;

      // Heuristic: only collapse if "big enough" to annoy
      const n = countLines(txt);
      if (n < 6) return;

      injectStyleOnce();

      const key = makeKeyForPre(pre, idx);
      const lsKey = "vsp_p205_open:" + key;
      const open = (localStorage.getItem(lsKey) === "1");

      const bar = document.createElement("div");
      bar.className = "vsp-json-togglebar";
      const left = document.createElement("div");
      left.className = "left";
      left.textContent = `JSON (${n} lines) — click to ${open ? "collapse" : "expand"}`;
      const right = document.createElement("div");
      right.className = "right";
      right.textContent = "P205";
      bar.appendChild(left);
      bar.appendChild(right);

      // Insert bar before <pre>
      pre.parentNode.insertBefore(bar, pre);

      function apply(openNow){
        if (openNow){
          pre.classList.remove("vsp-json-hidden");
          left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to collapse`;
          localStorage.setItem(lsKey, "1");
        } else {
          pre.classList.add("vsp-json-hidden");
          left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to expand`;
          localStorage.setItem(lsKey, "0");
        }
      }

      // default collapsed unless user opened
      apply(open);

      bar.addEventListener("click", function(){
        const isHidden = pre.classList.contains("vsp-json-hidden");
        apply(isHidden); // if hidden -> open, else collapse
      });

      // watch text changes (some code updates pre.textContent)
      const mo = new MutationObserver(function(){
        // keep current open/closed state, only refresh line count label
        const isHidden = pre.classList.contains("vsp-json-hidden");
        if (isHidden) left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to expand`;
        else left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to collapse`;
      });
      mo.observe(pre, {subtree:true, childList:true, characterData:true});

      pre.dataset.vspP205Bound = "1";
    }

    function scan(){
      if (!ENABLE) return;
      const pres = Array.from(document.querySelectorAll("pre"));
      for (let i=0;i<pres.length;i++){
        bindPre(pres[i], i);
      }
    }

    // initial
    setTimeout(scan, 50);
    setTimeout(scan, 400);
    setTimeout(scan, 1200);

    // re-apply on DOM changes (tab switch/render)
    let t = null;
    const body = document.body || document.documentElement;
    const mo = new MutationObserver(function(){
      if (t) clearTimeout(t);
      t = setTimeout(scan, 120);
    });
    if (body) mo.observe(body, {subtree:true, childList:true});

    console.log("[VSP] installed P205 (global JSON <pre> collapse observer)");
  }catch(e){
    console.warn("[VSP] P205 failed:", e);
  }
})();

/* VSP_P306_JSON_COLLAPSE_OBSERVER_BEGIN */
(function(){
  try{
    if (window.__VSP_P306_JSON_OBSERVER_INSTALLED) return;
    window.__VSP_P306_JSON_OBSERVER_INSTALLED = true;

    function onTargetPage(){
      try{
        var path = (location && location.pathname) ? location.pathname : "";
        return (path.indexOf("/c/settings")>=0) || (path.indexOf("/c/rule_overrides")>=0) ||
               (path.indexOf("/settings")>=0) || (path.indexOf("/rule_overrides")>=0);
      }catch(e){ return true; }
    }

    function isJsonLike(txt){
      if(!txt) return false;
      var t = (""+txt).trim();
      if(t.length < 2) return false;
      var c0 = t[0], c1 = t[t.length-1];
      if(!((c0==="{" && c1==="}") || (c0==="[" && c1==="]"))) return false;
      // quick reject if looks like HTML
      if(t.indexOf("<html")>=0 || t.indexOf("<!DOCTYPE")>=0) return false;
      return true;
    }

    function lineCount(txt){
      // robust across \n / \r\n
      return (""+txt).split(/\r?\n/).length;
    }

    function collapseOnePre(pre){
      if(!pre || !pre.parentNode) return;
      if(pre.dataset && pre.dataset.vspJsonCollapsed==="1") return;
      if(pre.closest && pre.closest("details")) return;

      var txt = pre.textContent || "";
      if(!isJsonLike(txt)) return;

      var lines = lineCount(txt);
      if(lines < 6) return; // avoid collapsing tiny JSON

      var details = document.createElement("details");
      details.className = "vsp-json-details";
      details.style.cssText = "margin:0; padding:0;";

      var summary = document.createElement("summary");
      summary.className = "vsp-json-summary";
      summary.textContent = "JSON (" + lines + " lines) — click to expand";
      summary.style.cssText = "cursor:pointer; user-select:none; opacity:.85; padding:6px 8px; border-radius:10px;";

      details.appendChild(summary);
      pre.parentNode.insertBefore(details, pre);
      details.appendChild(pre);

      if(pre.dataset) pre.dataset.vspJsonCollapsed="1";
      details.open = false;
    }

    function scan(root){
      if(!onTargetPage()) return;
      var scope = root || document;
      var pres = [];
      try{
        pres = scope.querySelectorAll ? scope.querySelectorAll("pre") : [];
      }catch(e){ pres = []; }
      for(var i=0;i<pres.length;i++){
        collapseOnePre(pres[i]);
      }
    }

    var timer = null;
    function scheduleScan(root){
      if(timer) return;
      timer = setTimeout(function(){
        timer = null;
        scan(root);
      }, 80);
    }

    // initial
    scheduleScan(document);

    // keep collapsing even if tab JS re-renders JSON later
    var obs = new MutationObserver(function(muts){
      // fast exit
      if(!onTargetPage()) return;
      scheduleScan(document);
    });
    obs.observe(document.documentElement || document.body, {subtree:true, childList:true, characterData:true});

    window.addEventListener("hashchange", function(){ scheduleScan(document); });
    window.addEventListener("popstate", function(){ scheduleScan(document); });
    document.addEventListener("visibilitychange", function(){ scheduleScan(document); });

    console.log("[VSP] installed P306 (global JSON collapse observer: settings + rule_overrides)");
  }catch(e){
    console.warn("[VSP] P306 install failed:", e);
  }
})();
 /* VSP_P306_JSON_COLLAPSE_OBSERVER_END */


/* ===================== VSP_JSON_COLLAPSE_P400 (stable) =====================
   Goal: collapse JSON <pre> reliably even when the tab re-renders.
   - Idempotent: marks processed nodes by data-vsp-json="1"
   - Safe: only touches <pre> that looks like JSON ({ or [)
============================================================================= */
(function(){
  try {
    window.VSPC = window.VSPC || {};
    if (window.VSPC.__jsonCollapseP400Installed) return;
    window.VSPC.__jsonCollapseP400Installed = true;

    function looksLikeJson(txt){
      if (!txt) return false;
      const t = (""+txt).trim();
      return t.startsWith("{") || t.startsWith("[");
    }

    function countLines(txt){
      if (!txt) return 0;
      // avoid any weird newline literal issues
      return (""+txt).split("\n").length;
    }

    function wrapPre(pre, opts){
      if (!pre || pre.dataset.vspJson === "1") return;
      const txt = pre.textContent || "";
      if (!looksLikeJson(txt)) return;

      const lines = countLines(txt);
      const page = (opts && opts.page) ? opts.page : "generic";
      const key  = (opts && opts.key) ? opts.key : ("vsp_json_expand::" + page);

      const wrapper = document.createElement("div");
      wrapper.className = "vsp-json-wrap";
      wrapper.style.cssText = "border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:10px;background:rgba(0,0,0,.18);";

      const hdr = document.createElement("div");
      hdr.className = "vsp-json-hdr";
      hdr.style.cssText = "display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;gap:10px;";

      const title = document.createElement("div");
      title.textContent = `JSON (${lines} lines)`;
      title.style.cssText = "font-size:12px;opacity:.85;letter-spacing:.2px;";

      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = "Expand";
      btn.style.cssText = "font-size:12px;padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#e6edf3;cursor:pointer;";

      hdr.appendChild(title);
      hdr.appendChild(btn);

      // move pre into wrapper
      const parent = pre.parentNode
      if (!parent) return;

      wrapper.appendChild(hdr);
      parent.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);

      pre.dataset.vspJson = "1";
      pre.style.margin = "0";
      pre.style.whiteSpace = "pre";
      pre.style.overflow = "auto";
      pre.style.maxHeight = "340px";

      function setExpanded(expanded){
        if (expanded){
          pre.style.display = "block";
          btn.textContent = "Collapse";
        } else {
          pre.style.display = "none";
          btn.textContent = "Expand";
        }
        try { localStorage.setItem(key, expanded ? "1" : "0"); } catch(e){}
      }

      // default collapsed unless previously expanded
      let expanded = False
      try { expanded = (localStorage.getItem(key) == "1"); } catch(e){ expanded = False; }
      setExpanded(expanded);

      btn.addEventListener("click", function(){
        const now = (pre.style.display === "none");
        setExpanded(now);
      });
    }

    window.VSPC.installJsonCollapseP400 = function(root, opts){
      try {
        root = root || document;
        const pres = root.querySelectorAll ? root.querySelectorAll("pre") : [];
        for (const pre of pres) wrapPre(pre, opts || {});
      } catch(e){}
    };

    window.VSPC.reapplyJsonCollapseP400 = function(page){
      // re-apply repeatedly for a short time; covers async renders without heavy observers.
      try {
        const key = "vsp_json_expand::" + (page || "generic");
        const opts = {page: page || "generic", key};
        let n = 0;
        const t = setInterval(function(){
          n++;
          try { window.VSPC.installJsonCollapseP400(document, opts); } catch(e){}
          if (n >= 40) clearInterval(t); // ~10s @250ms
        }, 250);
      } catch(e){}
    };

    console.log("[VSP] installed VSP_JSON_COLLAPSE_P400");
  } catch(e){}
})();


/* VSP_P450_APIUI_TO_APIVSP_V1 */


/* VSP_P472_SIDEBAR_MENU_V1 */
(function(){
  const LABELS = [
    ["Dashboard","/c/dashboard"],
    ["Runs & Reports","/c/runs"],
    ["Data Source","/c/data_source"],
    ["Settings","/c/settings"],
    ["Rule Overrides","/c/rule_overrides"],
  ];
  function css(){
    return `
#vsp_side_menu_v1{position:fixed;top:0;left:0;bottom:0;width:220px;z-index:9999;
  background:rgba(10,14,22,0.98);border-right:1px solid rgba(255,255,255,0.08);
  padding:14px 12px;font-family:inherit}
#vsp_side_menu_v1 .vsp_brand{font-weight:700;letter-spacing:.3px;font-size:13px;margin:2px 0 12px 2px;opacity:.95}
#vsp_side_menu_v1 a{display:flex;align-items:center;gap:10px;text-decoration:none;
  color:rgba(255,255,255,0.82);padding:10px 10px;border-radius:12px;margin:6px 0;
  background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a:hover{background:rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a.active{background:rgba(99,179,237,0.14);border-color:rgba(99,179,237,0.35);color:#fff}
.vsp_p472_shift{margin-left:220px}
.vsp_p472_hide_tabbtn{display:none!important}
`;
  }
  function init(){
    try{
      if(document.getElementById("vsp_side_menu_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_side_menu_v1_css";
      st.textContent=css();
      document.head.appendChild(st);

      const menu=document.createElement("div");
      menu.id="vsp_side_menu_v1";
      const brand=document.createElement("div");
      brand.className="vsp_brand";
      brand.textContent="VSP • Commercial";
      menu.appendChild(brand);

      const path=location.pathname || "";
      for(const [name,href] of LABELS){
        const a=document.createElement("a");
        a.href=href;
        a.textContent=name;
        if(path===href) a.classList.add("active");
        menu.appendChild(a);
      }
      document.body.appendChild(menu);

      // shift main content if possible
      const root = document.querySelector("#vsp_app") || document.querySelector("#app") || document.querySelector("main") || document.body;
      if(root && root!==document.body){
        root.classList.add("vsp_p472_shift");
      }else{
        document.body.classList.add("vsp_p472_shift");
      }

      // hide legacy tab buttons (only the 5 main ones)
      const wanted = new Set(LABELS.map(x=>x[0]));
      document.querySelectorAll("a,button").forEach(el=>{
        const t=(el.textContent||"").trim();
        if(wanted.has(t)) el.classList.add("vsp_p472_hide_tabbtn");
      });

      console && console.log && console.log("[P472] sidebar ready");
    }catch(e){
      console && console.warn && console.warn("[P472] sidebar init error", e);
    }
  }
  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();


/* VSP_P473_LOADER_SNIPPET_V1 */
(function(){
  try{
    if (window.__VSP_SIDEBAR_FRAME_V1__) return;
    if (document.getElementById("vsp_c_sidebar_v1_loader")) return;
    var s=document.createElement("script");
    s.id="vsp_c_sidebar_v1_loader";
    s.src="/static/js/vsp_c_sidebar_v1.js?v="+Date.now();
    document.head.appendChild(s);
  }catch(e){}
})();


/* VSP_P481_DS_POLISH_STICKY_FILTER_DRAWER_V1 */
(function(){
  if (window.__VSP_P481__) return;
  window.__VSP_P481__ = 1;

  const LEVELS = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function onDS(){ return location.pathname.includes("/c/data_source"); }

  function css(){
    if(document.getElementById("vsp_p481_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p481_css";
    st.textContent=`
/* hide accidental huge raw table above (best-effort) */
.vsp_p481_hide_dup_block{display:none!important}

/* chips */
#vsp_p481_bar{
  margin:10px 0 12px 0;
  display:flex;gap:8px;flex-wrap:wrap;align-items:center;
}
.vsp_p481_chip{
  border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.86);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
  user-select:none;
}
.vsp_p481_chip.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
.vsp_p481_sep{opacity:.35;margin:0 4px}

/* sticky header for main DS table */
.vsp_p481_table_wrap{
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  overflow:hidden;
}
.vsp_p481_table_scroller{
  max-height: 62vh;
  overflow:auto;
}
.vsp_p481_table_scroller table{ width:100%; border-collapse:collapse; }
.vsp_p481_table_scroller thead th{
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(20,24,33,0.98);
  backdrop-filter: blur(6px);
  border-bottom:1px solid rgba(255,255,255,0.06);
}
.vsp_p481_table_scroller td, .vsp_p481_table_scroller th{
  padding:8px 10px;
  font-size:12px;
  text-align:left;
  border-bottom:1px solid rgba(255,255,255,0.05);
}
.vsp_p481_row{ cursor:pointer; }
.vsp_p481_row:hover{ background:rgba(255,255,255,0.03); }

/* drawer */
#vsp_p481_drawer_backdrop{
  position:fixed; inset:0;
  background:rgba(0,0,0,0.55);
  z-index: 9998;
}
#vsp_p481_drawer{
  position:fixed; top:0; right:0;
  height:100vh; width: 520px; max-width: 92vw;
  z-index: 9999;
  border-left:1px solid rgba(255,255,255,0.08);
  background: rgba(12,16,24,0.98);
  backdrop-filter: blur(8px);
  padding:14px 14px;
  overflow:auto;
}
#vsp_p481_drawer .t{font-weight:900;font-size:14px;letter-spacing:.2px}
#vsp_p481_drawer .x{
  margin-top:10px; opacity:.86; font-size:12px; line-height:1.6;
}
#vsp_p481_drawer .kv{
  border:1px solid rgba(255,255,255,0.08);
  border-radius:14px;
  background:rgba(255,255,255,0.02);
  padding:10px 12px;
  margin-top:10px;
}
#vsp_p481_drawer .k{opacity:.65;font-size:11px}
#vsp_p481_drawer .v{margin-top:4px;font-size:12px;word-break:break-word}
#vsp_p481_drawer button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:7px 10px;
  font-size:12px;
}
#vsp_p481_drawer button:hover{background:rgba(255,255,255,0.06)}
#vsp_p481_drawer .btns{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
`;
    document.head.appendChild(st);
  }

  function hideHugeRawDuplicate(){
    // Some pages render a giant raw table above the framed content; hide it if it looks like a duplicate findings table
    try{
      const frame = document.querySelector(".vsp_p473_frame");
      if(!frame) return;
      // Look for large tables outside frame
      const tables = Array.from(document.querySelectorAll("table"));
      for(const tb of tables){
        if(frame.contains(tb)) continue;
        const rows = tb.querySelectorAll("tr").length;
        const cols = tb.querySelectorAll("th,td").length;
        if(rows > 15 && cols > 30){
          const wrap = tb.closest("div,section") || tb;
          wrap.classList.add("vsp_p481_hide_dup_block");
          console.log("[P481] hid duplicate raw table block");
          return;
        }
      }
    }catch(e){}
  }

  function findMainCard(){
    // best-effort: find the "Data Source" card inside frame
    const frame = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap");
    if(!frame) return null;
    // pick the first card-like block that contains "Data Source" text and has a table
    const nodes = Array.from(frame.querySelectorAll("div,section"));
    for(const n of nodes){
      const txt=(n.innerText||"");
      if(txt.includes("Data Source") && n.querySelector("table")){
        return n;
      }
    }
    // fallback: any table inside frame
    const t = frame.querySelector("table");
    return t ? (t.closest("div,section") || frame) : null;
  }

  function makeChipsBar(onChange){
    const bar=document.createElement("div");
    bar.id="vsp_p481_bar";
    const state={ level:null, tool:null };

    function chip(label, key, val){
      const c=document.createElement("span");
      c.className="vsp_p481_chip";
      c.textContent=label;
      c.onclick=()=>{
        if(state[key]===val){ state[key]=null; c.classList.remove("on"); }
        else{
          // turn off other chips of same key
          bar.querySelectorAll(`.vsp_p481_chip[data-key="${key}"]`).forEach(x=>x.classList.remove("on"));
          state[key]=val; c.classList.add("on");
        }
        onChange({...state});
      };
      c.dataset.key=key;
      return c;
    }

    LEVELS.forEach(l=>bar.appendChild(chip(l,"level",l)));
    const sep=document.createElement("span"); sep.className="vsp_p481_sep"; sep.textContent="|";
    bar.appendChild(sep);

    const toolInput=document.createElement("input");
    toolInput.placeholder="Filter tool (e.g. grype, semgrep)...";
    toolInput.style.cssText="flex:1;min-width:220px;border-radius:12px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.02);color:rgba(255,255,255,0.9);padding:7px 10px;font-size:12px;";
    toolInput.oninput=()=>{
      state.tool = toolInput.value.trim() || null;
      onChange({...state});
    };
    bar.appendChild(toolInput);

    return {bar, state};
  }

  function wrapTableForSticky(table){
    const wrap=document.createElement("div");
    wrap.className="vsp_p481_table_wrap";
    const sc=document.createElement("div");
    sc.className="vsp_p481_table_scroller";
    table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(sc);
    sc.appendChild(table);
  }

  function openDrawer(rowObj){
    closeDrawer();
    const bd=document.createElement("div");
    bd.id="vsp_p481_drawer_backdrop";
    bd.onclick=closeDrawer;

    const dr=document.createElement("div");
    dr.id="vsp_p481_drawer";

    const t=document.createElement("div");
    t.className="t";
    t.textContent="Finding details";
    dr.appendChild(t);

    const btns=document.createElement("div");
    btns.className="btns";
    const b1=document.createElement("button");
    b1.textContent="Copy JSON";
    b1.onclick=()=>{
      try{ navigator.clipboard.writeText(JSON.stringify(rowObj,null,2)); }catch(e){}
    };
    const b2=document.createElement("button");
    b2.textContent="Close";
    b2.onclick=closeDrawer;
    btns.appendChild(b1); btns.appendChild(b2);
    dr.appendChild(btns);

    const x=document.createElement("div");
    x.className="x";
    x.textContent="Click outside to close. Use Copy JSON to attach evidence into ticket.";
    dr.appendChild(x);

    // render kv
    const keys=Object.keys(rowObj||{});
    keys.forEach(k=>{
      const kv=document.createElement("div");
      kv.className="kv";
      const kk=document.createElement("div");
      kk.className="k"; kk.textContent=k;
      const vv=document.createElement("div");
      vv.className="v"; vv.textContent=(rowObj[k]==null?"":String(rowObj[k]));
      kv.appendChild(kk); kv.appendChild(vv);
      dr.appendChild(kv);
    });

    document.body.appendChild(bd);
    document.body.appendChild(dr);
  }

  function closeDrawer(){
    const bd=document.getElementById("vsp_p481_drawer_backdrop");
    const dr=document.getElementById("vsp_p481_drawer");
    if(bd) bd.remove();
    if(dr) dr.remove();
  }

  function parseRow(tr){
    // build object from cells; prefer header names
    const table=tr.closest("table");
    if(!table) return null;
    const ths=Array.from(table.querySelectorAll("thead th")).map(x=>(x.innerText||"").trim()||"col");
    const tds=Array.from(tr.querySelectorAll("td")).map(x=>(x.innerText||"").trim());
    const obj={};
    for(let i=0;i<tds.length;i++){
      const key = ths[i] || ("col"+i);
      obj[key]=tds[i];
    }
    return obj;
  }

  function applyFilter(table, st){
    const rows=Array.from(table.querySelectorAll("tbody tr"));
    let shown=0;
    rows.forEach(tr=>{
      const txt=(tr.innerText||"").toUpperCase();
      let ok=true;
      if(st.level){
        ok = ok && txt.includes(st.level);
      }
      if(st.tool){
        ok = ok && txt.toLowerCase().includes(st.tool.toLowerCase());
      }
      tr.style.display = ok ? "" : "none";
      if(ok) shown++;
    });
    console.log("[P481] filter", st, "shown", shown);
  }

  function boot(){
    if(!onDS()) return;
    css();
    hideHugeRawDuplicate();

    const card=findMainCard();
    if(!card){ console.log("[P481] no ds card/table found"); return; }

    const table=card.querySelector("table");
    if(!table){ console.log("[P481] no table"); return; }

    // insert chips bar above table
    if(!document.getElementById("vsp_p481_bar")){
      const {bar} = makeChipsBar((st)=>applyFilter(table, st));
      table.parentNode.insertBefore(bar, table);
    }

    // wrap for sticky header
    if(!table.closest(".vsp_p481_table_wrap")){
      wrapTableForSticky(table);
    }

    // click row -> drawer
    const rows=Array.from(table.querySelectorAll("tbody tr"));
    rows.forEach(tr=>{
      tr.classList.add("vsp_p481_row");
      tr.addEventListener("click", ()=>{
        const obj=parseRow(tr) || {};
        openDrawer(obj);
      });
    });

    // ESC close
    document.addEventListener("keydown", (e)=>{ if(e.key==="Escape") closeDrawer(); });

    console.log("[P481] datasource polish ready");
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 350));
  else setTimeout(boot, 350);
})();


/* VSP_P481B_DS_FALLBACK_FORCE_VISIBLE_V1 */
(function(){
  if (window.__VSP_P481B__) return;
  window.__VSP_P481B__ = 1;

  const LEVELS=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function onDS(){ return location.pathname.includes("/c/data_source"); }

  function ensureCss(){
    if(document.getElementById("vsp_p481b_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p481b_css";
    st.textContent=`
#vsp_p481_bar{
  margin:10px 0 12px 0;
  display:flex;gap:8px;flex-wrap:wrap;align-items:center;
}
.vsp_p481_chip{
  border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.86);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
  user-select:none;
}
.vsp_p481_chip.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
.vsp_p481_sep{opacity:.35;margin:0 4px}

.vsp_p481_table_wrap{
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  overflow:hidden;
}
.vsp_p481_table_scroller{
  max-height: 66vh;
  overflow:auto;
}
.vsp_p481_table_scroller table{ width:100%; border-collapse:collapse; }
.vsp_p481_table_scroller thead th{
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(20,24,33,0.98);
  backdrop-filter: blur(6px);
  border-bottom:1px solid rgba(255,255,255,0.06);
}
.vsp_p481_table_scroller td, .vsp_p481_table_scroller th{
  padding:8px 10px;
  font-size:12px;
  text-align:left;
  border-bottom:1px solid rgba(255,255,255,0.05);
}
.vsp_p481_row{ cursor:pointer; }
.vsp_p481_row:hover{ background:rgba(255,255,255,0.03); }

#vsp_p481_drawer_backdrop{
  position:fixed; inset:0;
  background:rgba(0,0,0,0.55);
  z-index: 9998;
}
#vsp_p481_drawer{
  position:fixed; top:0; right:0;
  height:100vh; width: 520px; max-width: 92vw;
  z-index: 9999;
  border-left:1px solid rgba(255,255,255,0.08);
  background: rgba(12,16,24,0.98);
  backdrop-filter: blur(8px);
  padding:14px 14px;
  overflow:auto;
}
#vsp_p481_drawer .t{font-weight:900;font-size:14px;letter-spacing:.2px}
#vsp_p481_drawer .x{margin-top:10px;opacity:.86;font-size:12px;line-height:1.6}
#vsp_p481_drawer .kv{
  border:1px solid rgba(255,255,255,0.08);
  border-radius:14px;
  background:rgba(255,255,255,0.02);
  padding:10px 12px;
  margin-top:10px;
}
#vsp_p481_drawer .k{opacity:.65;font-size:11px}
#vsp_p481_drawer .v{margin-top:4px;font-size:12px;word-break:break-word}
#vsp_p481_drawer button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:7px 10px;
  font-size:12px;
}
#vsp_p481_drawer button:hover{background:rgba(255,255,255,0.06)}
#vsp_p481_drawer .btns{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
`;
    document.head.appendChild(st);
  }

  function closeDrawer(){
    const bd=document.getElementById("vsp_p481_drawer_backdrop");
    const dr=document.getElementById("vsp_p481_drawer");
    if(bd) bd.remove();
    if(dr) dr.remove();
  }

  function openDrawer(obj){
    closeDrawer();
    const bd=document.createElement("div");
    bd.id="vsp_p481_drawer_backdrop";
    bd.onclick=closeDrawer;

    const dr=document.createElement("div");
    dr.id="vsp_p481_drawer";

    const t=document.createElement("div");
    t.className="t";
    t.textContent="Finding details";
    dr.appendChild(t);

    const btns=document.createElement("div");
    btns.className="btns";

    const b1=document.createElement("button");
    b1.textContent="Copy JSON";
    b1.onclick=()=>{ try{ navigator.clipboard.writeText(JSON.stringify(obj,null,2)); }catch(e){} };

    const b2=document.createElement("button");
    b2.textContent="Close";
    b2.onclick=closeDrawer;

    btns.appendChild(b1); btns.appendChild(b2);
    dr.appendChild(btns);

    const x=document.createElement("div");
    x.className="x";
    x.textContent="Click outside to close. Copy JSON to attach evidence into ticket.";
    dr.appendChild(x);

    Object.keys(obj||{}).forEach(k=>{
      const kv=document.createElement("div"); kv.className="kv";
      const kk=document.createElement("div"); kk.className="k"; kk.textContent=k;
      const vv=document.createElement("div"); vv.className="v"; vv.textContent=(obj[k]==null?"":String(obj[k]));
      kv.appendChild(kk); kv.appendChild(vv);
      dr.appendChild(kv);
    });

    document.body.appendChild(bd);
    document.body.appendChild(dr);
  }

  function parseRow(tr){
    const table=tr.closest("table");
    if(!table) return {};
    const ths=[...table.querySelectorAll("thead th")].map(x=>(x.innerText||"").trim()||"col");
    const tds=[...tr.querySelectorAll("td")].map(x=>(x.innerText||"").trim());
    const obj={};
    for(let i=0;i<tds.length;i++){
      const key=ths[i] || ("col"+i);
      obj[key]=tds[i];
    }
    // also stash raw row text
    obj.__row_text__ = (tr.innerText||"").trim();
    return obj;
  }

  function chooseBestTable(){
    const tables=[...document.querySelectorAll("table")];
    let best=null, bestScore=0;
    for(const tb of tables){
      const rows=tb.querySelectorAll("tbody tr").length;
      const cols=Math.max(
        tb.querySelectorAll("thead th").length,
        tb.querySelectorAll("tbody tr td").length // rough
      );
      if(rows < 8) continue;
      const score = rows * Math.min(cols, 50);
      if(score > bestScore){
        bestScore = score;
        best = tb;
      }
    }
    return best;
  }

  function wrapSticky(table){
    if(table.closest(".vsp_p481_table_wrap")) return;
    const wrap=document.createElement("div");
    wrap.className="vsp_p481_table_wrap";
    const sc=document.createElement("div");
    sc.className="vsp_p481_table_scroller";
    table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(sc);
    sc.appendChild(table);
  }

  function applyFilter(table, st){
    const rows=[...table.querySelectorAll("tbody tr")];
    let shown=0;
    for(const tr of rows){
      const txt=(tr.innerText||"");
      let ok=true;
      if(st.level){
        ok = ok && txt.toUpperCase().includes(st.level);
      }
      if(st.tool){
        ok = ok && txt.toLowerCase().includes(st.tool.toLowerCase());
      }
      tr.style.display = ok ? "" : "none";
      if(ok) shown++;
    }
    console.log("[P481b] filter", st, "shown", shown);
  }

  function ensureBar(table){
    if(document.getElementById("vsp_p481_bar")) return;

    const bar=document.createElement("div");
    bar.id="vsp_p481_bar";

    const state={level:null, tool:null};

    function mkChip(level){
      const c=document.createElement("span");
      c.className="vsp_p481_chip";
      c.textContent=level;
      c.onclick=()=>{
        if(state.level===level){
          state.level=null; c.classList.remove("on");
        }else{
          [...bar.querySelectorAll('.vsp_p481_chip[data-k="level"]')].forEach(x=>x.classList.remove("on"));
          state.level=level; c.classList.add("on");
        }
        applyFilter(table, state);
      };
      c.dataset.k="level";
      return c;
    }

    LEVELS.forEach(l=>bar.appendChild(mkChip(l)));

    const sep=document.createElement("span");
    sep.className="vsp_p481_sep";
    sep.textContent="|";
    bar.appendChild(sep);

    const inp=document.createElement("input");
    inp.placeholder="Filter tool (e.g. grype, semgrep)...";
    inp.style.cssText="flex:1;min-width:220px;border-radius:12px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.02);color:rgba(255,255,255,0.9);padding:7px 10px;font-size:12px;";
    inp.oninput=()=>{
      state.tool = (inp.value||"").trim() || null;
      applyFilter(table, state);
    };
    bar.appendChild(inp);

    table.parentNode.insertBefore(bar, table);
  }

  function wireRows(table){
    const rows=[...table.querySelectorAll("tbody tr")];
    for(const tr of rows){
      if(tr.dataset.vspP481bWired==="1") continue;
      tr.dataset.vspP481bWired="1";
      tr.classList.add("vsp_p481_row");
      tr.addEventListener("click", ()=>openDrawer(parseRow(tr)));
    }
    document.addEventListener("keydown",(e)=>{ if(e.key==="Escape") closeDrawer(); });
  }

  function run(){
    if(!onDS()) return;
    ensureCss();

    // If already visible from P481, do nothing
    if(document.getElementById("vsp_p481_bar")) {
      console.log("[P481b] bar already present");
      return;
    }

    const tb=chooseBestTable();
    if(!tb){
      console.log("[P481b] no suitable table found yet, retrying...");
      setTimeout(run, 900);
      return;
    }

    ensureBar(tb);
    wrapSticky(tb);
    wireRows(tb);
    console.log("[P481b] datasource fallback applied");
  }

  function boot(){
    if(!onDS()) return;
    // wait a bit for tables to render
    setTimeout(run, 600);
    setTimeout(run, 1500);
    setTimeout(run, 2600);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();


// VSP_OPS_PANEL_SETTINGS_HOOK_P910C
(function(){
  function want(){
    try { return (location.pathname||"").indexOf("/c/settings")===0; } catch(e){ return false; }
  }
  function findContainer(){
    return document.querySelector("main")
        || document.querySelector("#vsp_main")
        || document.querySelector("#app")
        || document.querySelector(".vsp-main")
        || document.querySelector(".container")
        || document.body;
  }
  function ensureHost(){
    if(!want()) return;
    if(document.getElementById("vsp_ops_panel")) return;
    const c = findContainer(); if(!c) return;
    const host = document.createElement("div");
    host.id = "vsp_ops_panel";
    host.style.margin = "12px 0 18px 0";
    if(c.firstChild) c.insertBefore(host, c.firstChild);
    else c.appendChild(host);
  }
  function loadScript(cb){
    if(window.VSPOpsPanel) return cb();
    if(document.getElementById("VSP_OPS_PANEL_V1_LOADER")) return;
    const s=document.createElement("script");
    s.id="VSP_OPS_PANEL_V1_LOADER";
    s.src="/static/js/vsp_ops_panel_v1.js?v="+Date.now();
    s.onload=function(){ cb(); };
    document.head.appendChild(s);
  }
  function run(){
    if(!want()) return;
    ensureHost();
    loadScript(function(){
      try { window.VSPOpsPanel && window.VSPOpsPanel.ensureMounted(); } catch(e){}
    });
  }
  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", function(){ run(); setTimeout(run,300); setTimeout(run,1200); });
  } else {
    run(); setTimeout(run,300); setTimeout(run,1200);
  }
  window.addEventListener("popstate", function(){ setTimeout(run,50); });
})();

