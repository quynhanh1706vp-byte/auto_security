/* VSP_P1_DASH_TOPFIND_MODAL_DS_V1
   - Non-invasive dashboard enhancer:
     * hooks fetch to capture  (and other run_file_allow JSON)
     * builds a modal showing enriched finding details
     * provides "Open Data Source" deep-link
     * attempts to make "Top Findings" rows clickable via MutationObserver heuristics
*/
(()=> {
  const LOG = (...a)=>{ try{ console.log("[DashTopFindModalV1]", ...a);}catch(e){} };

  const SEV_ORDER = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4, TRACE:5};
  const DS_URL = "/data_source";
  const RID_LATEST_V2 = "/api/vsp/rid_latest_gate_root_v2";

  function sevRank(s){
    s = (s||"").toString().toUpperCase();
    return (s in SEV_ORDER) ? SEV_ORDER[s] : 99;
  }

  function safeStr(x, max=4000){
    try{
      let t = (x===undefined||x===null) ? "" : String(x);
      if(t.length>max) t = t.slice(0,max) + "…";
      return t;
    }catch(e){ return ""; }
  }

  function prettyJson(obj){
    try{ return JSON.stringify(obj, null, 2); }catch(e){ return String(obj); }
  }

  // ---- Modal UI ----
  let modalEl = null;
  function ensureModal(){
    if(modalEl) return modalEl;
    const wrap = document.createElement("div");
    wrap.id = "vspTopFindModalV1";
    wrap.style.cssText = [
      "position:fixed","inset:0","display:none","z-index:99999",
      "background:rgba(0,0,0,0.55)","backdrop-filter: blur(2px)"
    ].join(";");
    wrap.innerHTML = `
      <div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:16px;">
        <div style="width:min(1100px,96vw);max-height:92vh;overflow:auto;background:#0b1220;border:1px solid rgba(255,255,255,0.08);border-radius:14px;box-shadow:0 20px 50px rgba(0,0,0,0.5);">
          <div style="display:flex;align-items:center;justify-content:space-between;padding:12px 14px;border-bottom:1px solid rgba(255,255,255,0.07);">
            <div>
              <div id="vspTopFindTitleV1" style="font-weight:700;color:#e7eefc;font-size:14px;">Finding</div>
              <div id="vspTopFindSubV1" style="color:rgba(231,238,252,0.65);font-size:12px;margin-top:2px;"></div>
            </div>
            <div style="display:flex;gap:10px;align-items:center;">
              <a id="vspTopFindOpenDSV1" href="${DS_URL}" style="text-decoration:none;color:#0b1220;background:#7dd3fc;padding:8px 10px;border-radius:10px;font-weight:700;font-size:12px;">Open Data Source</a>
              <button id="vspTopFindCloseV1" style="cursor:pointer;background:transparent;border:1px solid rgba(255,255,255,0.14);color:#e7eefc;border-radius:10px;padding:8px 10px;font-weight:700;font-size:12px;">Close</button>
            </div>
          </div>

          <div style="padding:12px 14px;">
            <div id="vspTopFindKvV1" style="display:grid;grid-template-columns: 160px 1fr;gap:8px 12px;font-size:12px;color:#e7eefc;"></div>
            <div style="margin-top:12px;">
              <div style="font-weight:700;color:#e7eefc;font-size:12px;margin-bottom:6px;">Raw JSON</div>
              <pre id="vspTopFindRawV1" style="white-space:pre-wrap;word-break:break-word;background:#07101f;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:10px;color:#cfe3ff;font-size:11px;line-height:1.35;max-height:46vh;overflow:auto;"></pre>
            </div>
          </div>
        </div>
      </div>
    `;
    document.body.appendChild(wrap);
    wrap.addEventListener("click",(e)=>{
      if(e.target===wrap){ hideModal(); }
    });
    wrap.querySelector("#vspTopFindCloseV1").addEventListener("click", hideModal);
    modalEl = wrap;
    return wrap;
  }

  function hideModal(){
    if(!modalEl) return;
    modalEl.style.display = "none";
  }

  function showModalWithFinding(f, rid){
    ensureModal();
    const title = modalEl.querySelector("#vspTopFindTitleV1");
    const sub   = modalEl.querySelector("#vspTopFindSubV1");
    const kv    = modalEl.querySelector("#vspTopFindKvV1");
    const raw   = modalEl.querySelector("#vspTopFindRawV1");
    const ds    = modalEl.querySelector("#vspTopFindOpenDSV1");

    const sev = (f.severity||f.sev||"").toUpperCase();
    const rule = f.rule_id || f.rule || f.check_id || f.id || "";
    const tool = f.tool || f.engine || f.source || "";
    const file = f.file || f.path || (f.location && (f.location.path||f.location.file)) || "";
    const line = f.line || (f.location && (f.location.line||f.location.start_line)) || "";
    const titleTxt = f.title || f.message || f.name || rule || "Finding";

    title.textContent = `${sev ? ("["+sev+"] ") : ""}${safeStr(titleTxt, 160)}`;
    sub.textContent = safeStr([tool, rule, file ? (file + (line? ":"+line:"")) : ""].filter(Boolean).join(" • "), 240);

    // Deep-link to Data Source (best-effort)
    const ridQ = rid ? `rid=${encodeURIComponent(rid)}` : "";
    const q = rule ? `q=${encodeURIComponent(rule)}` : "";
    const fileQ = file ? `file=${encodeURIComponent(file)}` : "";
    const link = `${DS_URL}?${[ridQ,q,fileQ].filter(Boolean).join("&")}`;
    ds.setAttribute("href", link);

    // KV grid
    const rows = [
      ["RID", rid || ""],
      ["Severity", sev],
      ["Tool", tool],
      ["Rule", rule],
      ["Title/Message", titleTxt],
      ["File", file],
      ["Line", line],
      ["CWE/OWASP", (f.cwe||f.owasp||f.owasp_top10||"")],
      ["ISO/Control", (f.iso_control||f.iso27001||f.control||"")],
      ["Fingerprint", (f.fingerprint||f.sig||"")],
    ].filter(r => r[1] !== undefined && r[1] !== null && String(r[1]).length);

    kv.innerHTML = rows.map(([k,v])=>{
      return `<div style="color:rgba(231,238,252,0.65)">${safeStr(k,60)}</div><div style="color:#e7eefc">${safeStr(v,2000)}</div>`;
    }).join("");

    raw.textContent = prettyJson(f);
    modalEl.style.display = "block";
  }

  // ---- Capture findings from fetch ----
  const STORE = {
    rid: "",
    findings: [],
    meta: {},
    top: [],  // computed
    idxByRule: new Map(),
  };

  function rebuildIndex(){
    STORE.idxByRule.clear();
    for(const f of STORE.findings){
      const rule = (f.rule_id||f.rule||f.check_id||f.id||"").toString();
      if(rule && !STORE.idxByRule.has(rule)) STORE.idxByRule.set(rule, f);
    }
  }

  function computeTop(){
    const arr = (STORE.findings||[]).slice(0);
    arr.sort((a,b)=> sevRank(a.severity||a.sev) - sevRank(b.severity||b.sev));
    STORE.top = arr.slice(0, 30);
  }

  async function ensureRidLatest(){
    try{
      const r = await fetch(RID_LATEST_V2, {cache:"no-store"});
      const j = await r.json();
      if(j && j.rid) STORE.rid = j.rid;
    }catch(e){}
  }

  // patch fetch
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if(_fetch){
    window.fetch = async (...args)=>{
      const res = await _fetch(...args);
      try{
        const url = (args && args[0]) ? String(args[0]) : "";
        if(url.includes("")){
          const c = res.clone();
          c.json().then(j=>{
            if(j && (Array.isArray(j.findings) || Array.isArray(j))){
              const findings = Array.isArray(j) ? j : (j.findings||[]);
              STORE.findings = findings;
              STORE.meta = j.meta || {};
              rebuildIndex();
              computeTop();
              // export to global for debugging
              window.__VSP_FINDINGS_UNIFIED = {rid: STORE.rid, meta: STORE.meta, findings: STORE.findings};
              window.__VSP_TOP_FINDINGS = STORE.top;
              LOG("captured findings_unified", "findings=", STORE.findings.length);
              // try make panel clickable
              setTimeout(hookTopFindPanel, 50);
            }
          }).catch(()=>{});
        }
      }catch(e){}
      return res;
    };
  }

  // ---- Hook Top Findings panel: best-effort DOM heuristics ----
  function findTopFindPanel(){
    // heuristic: find element containing text "Top Findings"
    const all = Array.from(document.querySelectorAll("body *"));
    for(const el of all){
      const t = (el.textContent||"").trim();
      if(!t) continue;
      if(t === "Top Findings" || t.toLowerCase() === "top findings"){
        // prefer container card: go up a bit
        return el.closest("section,div,article") || el.parentElement;
      }
    }
    // fallback: try ids/classes
    return document.querySelector("#topFindings, #top_findings, .topFindings, .top-findings");
  }

  function markClickable(el){
    if(!el || el.__vsp_marked) return;
    el.__vsp_marked = true;
    el.style.cursor = "pointer";
    el.style.outline = "none";
    el.addEventListener("mouseenter", ()=>{ el.style.filter="brightness(1.06)"; });
    el.addEventListener("mouseleave", ()=>{ el.style.filter=""; });
  }

  function hookTopFindPanel(){
    const panel = findTopFindPanel();
    if(!panel) return;

    // find candidate rows: prefer list-like children
    const rows = panel.querySelectorAll("li, tr, .row, .item, .tf-row, .tf-item, div");
    let attached = 0;

    rows.forEach((r)=>{
      if(attached>120) return;
      const txt = (r.textContent||"").trim();
      if(!txt || txt.length < 6) return;

      // avoid whole page giant div: only smaller blocks
      if((r.innerText||"").length > 600) return;

      // try parse rule id token from text
      let rule = "";
      const m = txt.match(/\b([A-Za-z0-9_.-]{6,})\b/);
      if(m) rule = m[1];

      // choose a finding to show on click
      let chosen = null;
      if(rule && STORE.idxByRule.has(rule)) chosen = STORE.idxByRule.get(rule);
      if(!chosen && STORE.top && STORE.top.length){
        // fallback: pick first matching severity token
        const sev = (txt.match(/\b(CRITICAL|HIGH|MEDIUM|LOW|INFO|TRACE)\b/i)||[])[1];
        if(sev){
          chosen = STORE.top.find(x => (x.severity||"").toUpperCase()===sev.toUpperCase()) || STORE.top[0];
        }else{
          chosen = STORE.top[0];
        }
      }
      if(!chosen) return;

      // attach once
      if(r.__vsp_topfind_click) return;
      r.__vsp_topfind_click = true;
      markClickable(r);
      r.addEventListener("click",(e)=>{
        try{
          // ignore clicks on links/buttons inside
          const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : "";
          if(tag==="a" || tag==="button") return;
        }catch(_){}
        showModalWithFinding(chosen, STORE.rid || "");
      });
      attached++;
    });

    if(attached){
      LOG("hooked topfind rows:", attached);
    }
  }

  // observe DOM updates (dashboard often re-renders)
  const mo = new MutationObserver(()=>{ hookTopFindPanel(); });
  try{
    mo.observe(document.documentElement, {subtree:true, childList:true});
  }catch(e){}

  // init
  ensureRidLatest().finally(()=>{
    // in case dashboard renders before fetch capture
    setTimeout(hookTopFindPanel, 300);
  });

  // expose for manual test
  window.VSP_showTopFindingModal = (idx=0)=>{
    ensureRidLatest().finally(()=>{
      const f = (STORE.top && STORE.top[idx]) ? STORE.top[idx] : (STORE.findings[0]||null);
      if(f) showModalWithFinding(f, STORE.rid||"");
      else LOG("no findings captured yet");
    });
  };
})();
