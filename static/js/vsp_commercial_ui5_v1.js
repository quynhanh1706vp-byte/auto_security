/* VSP Commercial UI5 (freeze-safe, 5 tabs) */
(function(){
  if (window.__VSP_UI5_LOADED) return;
  window.__VSP_UI5_LOADED = true;

  const LS_PIN = "vsp_pin_mode_v2";   // auto|global|rid
  const PINS = ["auto","global","rid"];
  const now = () => new Date().toISOString();

  const qs = new URLSearchParams(location.search);
  const getRid = () => (qs.get("rid") || "").trim();
  const setQS = (k,v) => { const u=new URL(location.href); if (v==null||v==="") u.searchParams.delete(k); else u.searchParams.set(k,v); location.href=u.toString(); };

  const safePin = () => {
    try{
      const v=(localStorage.getItem(LS_PIN)||"auto").toLowerCase();
      return PINS.includes(v)?v:"auto";
    }catch(_){ return "auto"; }
  };
  const setPin = (m) => {
    try{ localStorage.setItem(LS_PIN, m); }catch(_){}
  };

  const el = (tag, cls, txt) => {
    const e=document.createElement(tag);
    if (cls) e.className=cls;
    if (txt!=null) e.textContent=txt;
    return e;
  };

  const toast = (msg, ms=2200) => {
    try{
      const t=el("div","toast", msg);
      document.body.appendChild(t);
      setTimeout(()=>{ try{ t.remove(); }catch(_){} }, ms);
    }catch(_){}
  };

  const fetchJson = async (path, timeoutMs=12000) => {
    const ctl = new AbortController();
    const t = setTimeout(()=>ctl.abort(), timeoutMs);
    try{
      const r = await fetch(path, {signal: ctl.signal, credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      const text = await r.text();
      let j=null;
      if (ct.includes("application/json")) {
        try{ j=JSON.parse(text); }catch(_){}
      } else {
        // still try parse if looks like json
        const s=text.trim();
        if (s.startsWith("{") || s.startsWith("[")) { try{ j=JSON.parse(s); }catch(_){ } }
      }
      return { ok: r.ok, status: r.status, json: j, text };
    } finally { clearTimeout(t); }
  };

  // tab routing
  const TAB = (() => {
    const p = location.pathname || "";
    if (p.startsWith("/c/runs")) return "runs";
    if (p.startsWith("/c/data_source")) return "data_source";
    if (p.startsWith("/c/settings")) return "settings";
    if (p.startsWith("/c/rule_overrides")) return "rule_overrides";
    return "dashboard";
  })();

  // take over only on /c/*
  try{
    if (!location.pathname.startsWith("/c/")) return;
  }catch(_){ return; }

  // wipe body, render full UI (freeze-safe)
  try{ document.body.innerHTML=""; }catch(_){}

  const rootTop = el("div","vsp5-topbar");
  const topInner = el("div","vsp5-topbar-inner");
  rootTop.appendChild(topInner);
  document.body.appendChild(rootTop);

  const wrap = el("div","vsp5-wrap");
  document.body.appendChild(wrap);

  const brand = el("div","vsp5-brand");
  brand.appendChild(el("div","vsp5-dot"));
  const brandText = el("div");
  brandText.appendChild(el("div","vsp5-title","VSP • Commercial"));
  brandText.appendChild(el("div","vsp5-sub","5 tabs • API-driven • freeze-safe"));
  brand.appendChild(brandText);
  topInner.appendChild(brand);

  const pills = el("div","vsp5-pillrow");
  topInner.appendChild(pills);

  // nav row under topbar
  const navRow = el("div","navrow");
  const navHost = el("div","vsp5-wrap");
  navHost.style.paddingTop = "10px";
  navHost.appendChild(navRow);
  rootTop.appendChild(navHost);

  const mkNav = (label, tab, href) => {
    const b=el("button","navbtn"+(TAB===tab?" active":""), label);
    b.addEventListener("click", ()=>{
      const rid=getRid();
      const pin=safePin();
      const u=new URL(location.origin + href);
      if (rid) u.searchParams.set("rid", rid);
      if (pin && pin!=="auto") u.searchParams.set("pin", pin);
      location.href = u.toString();
    });
    return b;
  };

  navRow.appendChild(mkNav("Dashboard","dashboard","/c/dashboard"));
  navRow.appendChild(mkNav("Runs & Reports","runs","/c/runs"));
  navRow.appendChild(mkNav("Data Source","data_source","/c/data_source"));
  navRow.appendChild(mkNav("Settings","settings","/c/settings"));
  navRow.appendChild(mkNav("Rule Overrides","rule_overrides","/c/rule_overrides"));

  const chipRID = el("span","chip");
  const chipDS  = el("span","chip");
  const chipPIN = el("span","chip");
  const chipTS  = el("span","chip");

  const btnRefresh = el("button","btn primary","Refresh");
  const btnAuto = el("button","btn ghost","AUTO");
  const btnPinG = el("button","btn ghost","PIN GLOBAL");
  const btnUseR = el("button","btn ghost","USE RID");

  pills.appendChild(chipRID);
  pills.appendChild(chipDS);
  pills.appendChild(chipPIN);
  pills.appendChild(chipTS);
  pills.appendChild(btnAuto);
  pills.appendChild(btnPinG);
  pills.appendChild(btnUseR);
  pills.appendChild(btnRefresh);

  const applyPinButtons = () => {
    const p=safePin();
    btnAuto.className = "btn"+(p==="auto"?" primary":" ghost");
    btnPinG.className = "btn"+(p==="global"?" primary":" ghost");
    btnUseR.className = "btn"+(p==="rid"?" primary":" ghost");
    chipPIN.innerHTML = "";
    chipPIN.appendChild(el("span",null,"PIN: "));
    chipPIN.appendChild(el("b",null,p.toUpperCase()));
  };

  btnAuto.addEventListener("click", ()=>{ setPin("auto"); applyPinButtons(); toast("PIN = AUTO"); });
  btnPinG.addEventListener("click", ()=>{ setPin("global"); applyPinButtons(); toast("PIN = GLOBAL"); });
  btnUseR.addEventListener("click", ()=>{ setPin("rid"); applyPinButtons(); toast("PIN = RID"); });

  btnRefresh.addEventListener("click", ()=>{ location.reload(); });

  const state = {
    rid: getRid(),
    data_source: "UNKNOWN",
    from_path: "",
    total_findings: null,
    top_total: null,
    top_items: [],
    trend_points: [],
    runs: [],
    probe: {}
  };

  const setChips = () => {
    chipRID.innerHTML="";
    chipRID.appendChild(el("span",null,"RID: "));
    chipRID.appendChild(el("b",null, state.rid || "(none)"));

    chipDS.innerHTML="";
    chipDS.appendChild(el("span",null,"DATA SOURCE: "));
    chipDS.appendChild(el("b",null, state.data_source || "UNKNOWN"));

    chipTS.innerHTML="";
    chipTS.appendChild(el("span",null,"LIVE: "));
    chipTS.appendChild(el("b",null, new Date().toLocaleString()));
  };

  const api = {
    findings_page_v3: (rid, limit=1, offset=0) => `/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit}&offset=${offset}`,
    top_findings_v3c: (rid, limit=200) => `/api/vsp/top_findings_v3c?rid=${encodeURIComponent(rid||"")}&limit=${limit}`,
    trend_v1: (rid) => rid ? `/api/vsp/trend_v1?rid=${encodeURIComponent(rid)}` : `/api/vsp/trend_v1`,
    runs: (limit=80, offset=0) => `/api/vsp/runs?limit=${limit}&offset=${offset}`,
    export_csv: (rid) => `/api/vsp/export_csv?rid=${encodeURIComponent(rid||"")}`,
    export_reports_tgz: (rid) => `/api/vsp/reports_tgz?rid=${encodeURIComponent(rid||"")}`
  };

  // helper: severity dot class
  const sevDot = (sev) => {
    const s=(sev||"").toUpperCase();
    if (s==="CRITICAL") return "dot crit";
    if (s==="HIGH") return "dot high";
    if (s==="MEDIUM") return "dot med";
    if (s==="LOW") return "dot low";
    if (s==="INFO") return "dot info";
    return "dot trace";
  };

  const mkTable = (cols, rows) => {
    const t=el("table","table");
    const thead=el("thead");
    const trh=el("tr");
    cols.forEach(c=>{ const th=el("th",null,c); trh.appendChild(th); });
    thead.appendChild(trh);
    t.appendChild(thead);
    const tb=el("tbody");
    const frag=document.createDocumentFragment();
    rows.forEach(r=>frag.appendChild(r));
    tb.appendChild(frag);
    t.appendChild(tb);
    return t;
  };

  // -------- TAB renderers --------
  const clearWrap = () => { wrap.innerHTML=""; };

  const renderDashboard = async () => {
    clearWrap();

    const g = el("div","grid kpi");
    const cTotal = el("div","card");
    const cTop = el("div","card");
    const cTrend = el("div","card");
    const cStatus = el("div","card");

    cTotal.appendChild(el("h3",null,"Total Findings"));
    const totalRow=el("div","kpiRow");
    const totalVal=el("div","kpiVal","—");
    const totalMini=el("div","kpiMini","from_path: —");
    totalRow.appendChild(totalVal);
    totalRow.appendChild(el("div","meta",""));
    cTotal.appendChild(totalRow);
    cTotal.appendChild(totalMini);

    cTop.appendChild(el("h3",null,"Top Findings"));
    const topRow=el("div","kpiRow");
    const topVal=el("div","kpiVal","—");
    const topMini=el("div","kpiMini","source: top_findings_v3c");
    topRow.appendChild(topVal);
    topRow.appendChild(el("div","meta","limit 200"));
    cTop.appendChild(topRow);
    cTop.appendChild(topMini);

    cTrend.appendChild(el("h3",null,"Trend"));
    const trRow=el("div","kpiRow");
    const trVal=el("div","kpiVal","—");
    const trMini=el("div","kpiMini","source: trend_v1");
    trRow.appendChild(trVal);
    trRow.appendChild(el("div","meta","points"));
    cTrend.appendChild(trRow);
    cTrend.appendChild(trMini);

    cStatus.appendChild(el("h3",null,"Status"));
    cStatus.appendChild(el("div","meta","Commercial suite: /c/*"));
    cStatus.appendChild(el("div","meta","No heavy DOM • freeze-safe"));

    g.appendChild(cTotal);
    g.appendChild(cTop);
    g.appendChild(cTrend);
    g.appendChild(cStatus);

    wrap.appendChild(g);

    const row2 = el("div","row2");
    const left = el("div","card");
    const right = el("div","card");
    left.appendChild(el("h3",null,"Top Findings"));
    right.appendChild(el("h3",null,"Trend (mini)"));

    const hint = el("div","meta","Tip: dùng PIN GLOBAL khi cần cố định dataset, AUTO cho chế độ thương mại.");
    right.appendChild(hint);

    row2.appendChild(left);
    row2.appendChild(right);
    wrap.appendChild(row2);

    // load data (freeze-safe)
    const rid = state.rid;

    // findings_page_v3
    const a1 = await fetchJson(api.findings_page_v3(rid, 1, 0), 15000);
    if (a1.ok && a1.json){
      state.from_path = a1.json.from_path || "";
      state.total_findings = a1.json.total_findings ?? a1.json.total ?? null;
      state.data_source = a1.json.data_source || (state.from_path.includes("/out/") ? "GLOBAL_BEST" : "RID");
      totalVal.textContent = (state.total_findings==null ? "—" : String(state.total_findings));
      totalMini.textContent = "from_path: " + (state.from_path || "—");
      setChips();
    } else {
      totalVal.textContent = "ERR";
      totalMini.textContent = "findings_page_v3 failed ("+a1.status+")";
    }

    // top_findings_v3c
    const a2 = await fetchJson(api.top_findings_v3c(rid, 200), 20000);
    if (a2.ok && a2.json){
      const items = a2.json.items || [];
      state.top_items = items;
      state.top_total = a2.json.total ?? items.length;
      topVal.textContent = String(items.length);
      // render table
      const rows = items.slice(0,200).map(it=>{
        const tr=el("tr");
        const tdSev=el("td");
        const s=el("span","badgeSev");
        s.appendChild(el("span",sevDot(it.severity)));
        s.appendChild(el("span",null,(it.severity||"TRACE").toUpperCase()));
        tdSev.appendChild(s);

        const tdTitle=el("td",null,(it.title || it.component || it.rule_id || "(no title)"));
        const tdTool=el("td",null,(it.tool || it.source || ""));
        const tdFile=el("td",null,(it.file || ""));
        tr.appendChild(tdSev); tr.appendChild(tdTitle); tr.appendChild(tdTool); tr.appendChild(tdFile);
        return tr;
      });
      left.appendChild(mkTable(["SEVERITY","TITLE","TOOL","FILE"], rows));
      left.appendChild(el("div","meta",`items=${items.length} limit=200`));
    } else {
      topVal.textContent = "ERR";
      left.appendChild(el("div","meta","top_findings_v3c failed ("+a2.status+")"));
    }

    // trend_v1
    const a3 = await fetchJson(api.trend_v1(rid), 15000);
    if (a3.ok && a3.json){
      const pts = a3.json.points || a3.json.data || [];
      state.trend_points = pts;
      trVal.textContent = String(Array.isArray(pts)?pts.length:0);
      const latest = (Array.isArray(pts) && pts.length) ? (pts[0].label || pts[0].ts || "") : "";
      right.appendChild(el("div","chip","latest: " + (latest || "—")));
    } else {
      trVal.textContent = "ERR";
      right.appendChild(el("div","meta","trend_v1 failed ("+a3.status+")"));
    }
  };

  const renderRuns = async () => {
    clearWrap();
    const card = el("div","card");
    card.appendChild(el("h3",null,"Runs & Reports"));
    card.appendChild(el("div","meta","Real list from /api/vsp/runs • actions open Dashboard/Data Source"));
    const filter = el("input","input");
    filter.placeholder = "Filter by RID / label (client-side)";
    card.appendChild(filter);
    const holder = el("div");
    card.appendChild(holder);
    wrap.appendChild(card);

    const a = await fetchJson(api.runs(80,0), 15000);
    const runs = (a.ok && a.json && Array.isArray(a.json.runs)) ? a.json.runs : [];
    state.runs = runs;

    const render = () => {
      holder.innerHTML="";
      const q=(filter.value||"").toLowerCase();
      const list = runs.filter(r=>{
        const s = (r.rid||r.id||"") + " " + (r.label||"") + " " + (r.ts||"");
        return s.toLowerCase().includes(q);
      });

      const rows = list.map(r=>{
        const rid = r.rid || r.id || "";
        const tr=el("tr");
        const tdRid=el("td",null,rid);
        const tdLabel=el("td",null,(r.label||r.ts||""));
        const tdAct=el("td");
        const b1=el("button","btn","Open Dashboard");
        const b2=el("button","btn","Data Source");
        b1.addEventListener("click", ()=>location.href=`/c/dashboard?rid=${encodeURIComponent(rid)}`);
        b2.addEventListener("click", ()=>location.href=`/c/data_source?rid=${encodeURIComponent(rid)}`);
        tdAct.appendChild(b1); tdAct.appendChild(el("span",null," ")); tdAct.appendChild(b2);
        tr.appendChild(tdRid); tr.appendChild(tdLabel); tr.appendChild(tdAct);
        return tr;
      });

      holder.appendChild(mkTable(["RID","LABEL/TS","ACTIONS"], rows));
      holder.appendChild(el("div","meta",`rows=${list.length}/${runs.length}`));
    };

    filter.addEventListener("input", ()=>render());
    render();
  };

  const renderDataSource = async () => {
    clearWrap();
    const card = el("div","card");
    card.appendChild(el("h3",null,"Data Source"));
    card.appendChild(el("div","meta","Preview unified findings (paged 200) • client filter applies on current page only"));

    const controls = el("div","navrow");
    const btnNext = el("button","btn","Next +200");
    const chipOff = el("span","chip","offset=0");
    controls.appendChild(btnNext);
    controls.appendChild(chipOff);

    const filter = el("input","input");
    filter.placeholder = "Filter by severity/tool/title/file (client-side on loaded page)";
    card.appendChild(controls);
    card.appendChild(filter);

    const holder = el("div");
    card.appendChild(holder);
    wrap.appendChild(card);

    let offset = 0;
    let page = [];

    const load = async () => {
      holder.innerHTML = "";
      chipOff.innerHTML = "";
      chipOff.appendChild(el("span",null,"offset="));
      chipOff.appendChild(el("b",null,String(offset)));

      const rid = state.rid;
      const a = await fetchJson(api.findings_page_v3(rid, 200, offset), 20000);
      const items = (a.ok && a.json && Array.isArray(a.json.items)) ? a.json.items : [];
      page = items;

      const q=(filter.value||"").toLowerCase();
      const list = items.filter(it=>{
        const s = (it.severity||"")+" "+(it.tool||"")+" "+(it.title||"")+" "+(it.file||"");
        return s.toLowerCase().includes(q);
      });

      const rows = list.map(it=>{
        const tr=el("tr");
        const tdSev=el("td");
        const s=el("span","badgeSev");
        s.appendChild(el("span",sevDot(it.severity)));
        s.appendChild(el("span",null,(it.severity||"TRACE").toUpperCase()));
        tdSev.appendChild(s);
        const tdTitle=el("td",null,(it.title||"(no title)"));
        const tdTool=el("td",null,(it.tool||""));
        const tdFile=el("td",null,(it.file||""));
        tr.appendChild(tdSev); tr.appendChild(tdTitle); tr.appendChild(tdTool); tr.appendChild(tdFile);
        return tr;
      });

      holder.appendChild(mkTable(["SEVERITY","TITLE","TOOL","FILE"], rows));
      holder.appendChild(el("div","meta",`loaded=${items.length} showing=${list.length}`));
    };

    btnNext.addEventListener("click", ()=>{ offset += 200; load(); });
    filter.addEventListener("input", ()=>load());
    load();
  };

  const renderSettings = async () => {
    clearWrap();
    const row = el("div","row2");
    const left = el("div","card");
    const right = el("div","card");
    left.appendChild(el("h3",null,"Settings"));
    const p = safePin().toUpperCase();
    left.appendChild(el("div","meta","PIN default (stored local): " + p));

    const btns = el("div","navrow");
    const bA=el("button","btn","Set AUTO");
    const bG=el("button","btn","Set PIN GLOBAL");
    const bR=el("button","btn","Set USE RID");
    btns.appendChild(bA); btns.appendChild(bG); btns.appendChild(bR);
    left.appendChild(btns);

    const notes = el("div","meta");
    notes.innerHTML = [
      "• DATA SOURCE là “effective” dựa trên from_path (GLOBAL_BEST vs RID).",
      "• Suite /c/* tách khỏi UI cũ để rollback dễ."
    ].join("<br>");
    left.appendChild(notes);

    right.appendChild(el("h3",null,"Endpoint Probes"));
    const tblHost = el("div");
    right.appendChild(tblHost);

    row.appendChild(left);
    row.appendChild(right);
    wrap.appendChild(row);

    bA.addEventListener("click", ()=>{ setPin("auto"); applyPinButtons(); toast("PIN set AUTO"); });
    bG.addEventListener("click", ()=>{ setPin("global"); applyPinButtons(); toast("PIN set GLOBAL"); });
    bR.addEventListener("click", ()=>{ setPin("rid"); applyPinButtons(); toast("PIN set RID"); });

    const rid = state.rid;
    const probes = [
      ["findings_page_v3", api.findings_page_v3(rid,1,0)],
      ["top_findings_v3c", api.top_findings_v3c(rid,200)],
      ["trend_v1", api.trend_v1(rid)],
      ["runs", api.runs(5,0)]
    ];

    const rows = [];
    for (const [name,url] of probes){
      const r = await fetchJson(url, 12000);
      const tr=el("tr");
      tr.appendChild(el("td",null,name));
      tr.appendChild(el("td",null,String(r.status)));
      rows.push(tr);
    }
    tblHost.appendChild(mkTable(["API","Status"], rows));
  };

  const renderRuleOverrides = async () => {
    clearWrap();
    const card = el("div","card");
    card.appendChild(el("h3",null,"Rule Overrides"));
    card.appendChild(el("div","meta","Prefer backend, fallback localStorage"));

    const actions = el("div","navrow");
    const bLoad = el("button","btn","LOAD");
    const bSave = el("button","btn primary","SAVE");
    const bExport = el("button","btn","EXPORT");
    actions.appendChild(bLoad); actions.appendChild(bSave); actions.appendChild(bExport);
    card.appendChild(actions);

    const ta = el("textarea","input");
    ta.style.minHeight = "320px";
    ta.style.fontFamily = "var(--mono)";
    ta.value = "{\n  \"enabled\": true,\n  \"overrides\": []\n}\n";
    card.appendChild(ta);

    const meta = el("div","meta","source=unknown");
    card.appendChild(meta);
    wrap.appendChild(card);

    const LS_OVR = "vsp_rule_overrides_v1";

    const tryGet = async () => {
      // try a few endpoints that your tree may have
      const cand = [
        "/api/vsp/rule_overrides_v1",
        "/api/vsp/rule_overrides",
        "/api/vsp/rule_overrides_v0"
      ];
      for (const u of cand){
        const r = await fetchJson(u, 12000);
        if (r.ok && r.json){
          meta.textContent = "source=backend ("+u+")";
          return r.json;
        }
      }
      // fallback local
      try{
        const s=localStorage.getItem(LS_OVR);
        if (s){ meta.textContent="source=localStorage"; return JSON.parse(s); }
      }catch(_){}
      meta.textContent="source=default";
      return { enabled:true, overrides:[] };
    };

    const trySave = async (obj) => {
      const body = JSON.stringify(obj);
      const cand = [
        {u:"/api/vsp/rule_overrides_v1", m:"POST"},
        {u:"/api/vsp/rule_overrides", m:"POST"},
        {u:"/api/vsp/rule_overrides_v1", m:"PUT"},
        {u:"/api/vsp/rule_overrides", m:"PUT"},
      ];
      for (const c of cand){
        try{
          const r = await fetch(c.u, {method:c.m, headers:{"content-type":"application/json"}, body, credentials:"same-origin"});
          if (r.ok){ meta.textContent = "saved=backend ("+c.u+" "+c.m+")"; return true; }
        }catch(_){}
      }
      try{ localStorage.setItem(LS_OVR, body); meta.textContent="saved=localStorage"; return true; }catch(_){}
      meta.textContent="save failed";
      return false;
    };

    bLoad.addEventListener("click", async ()=>{
      const j = await tryGet();
      ta.value = JSON.stringify(j, null, 2);
      toast("Loaded overrides");
    });

    bSave.addEventListener("click", async ()=>{
      try{
        const j = JSON.parse(ta.value);
        const ok = await trySave(j);
        toast(ok?"Saved":"Save failed");
      }catch(e){
        toast("JSON invalid: " + (e && e.message ? e.message : "parse error"), 4000);
      }
    });

    bExport.addEventListener("click", ()=>{
      const blob = new Blob([ta.value], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "rule_overrides.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 2000);
    });

    // auto load once
    bLoad.click();
  };

  // init chips & pin
  applyPinButtons();
  setChips();

  // ensure rid exists for commercial suite; if not -> keep but warn
  if (!state.rid){
    toast("RID missing — append ?rid=VSP_CI_... for best experience", 4500);
  }

  // add quick export buttons via keyboard-free actions (optional)
  const addExports = () => {
    // keep it minimal; rely on backend routes if exist
    const rid = state.rid;
    const expCSV = el("button","btn","Download findings.csv");
    const expTGZ = el("button","btn","Download reports.tgz");
    expCSV.addEventListener("click", ()=>{
      if (!rid) return toast("RID missing", 2500);
      window.open(api.export_csv(rid), "_blank");
    });
    expTGZ.addEventListener("click", ()=>{
      if (!rid) return toast("RID missing", 2500);
      window.open(api.export_reports_tgz(rid), "_blank");
    });
    pills.insertBefore(expTGZ, btnAuto);
    pills.insertBefore(expCSV, btnAuto);
  };
  addExports();

  // render selected tab
  (async ()=>{
    try{
      if (TAB==="runs") return await renderRuns();
      if (TAB==="data_source") return await renderDataSource();
      if (TAB==="settings") return await renderSettings();
      if (TAB==="rule_overrides") return await renderRuleOverrides();
      return await renderDashboard();
    }catch(e){
      clearWrap();
      const c=el("div","card");
      c.appendChild(el("h3",null,"UI error"));
      c.appendChild(el("div","meta", String(e && e.stack ? e.stack : e)));
      wrap.appendChild(c);
    }
  })();

})();
