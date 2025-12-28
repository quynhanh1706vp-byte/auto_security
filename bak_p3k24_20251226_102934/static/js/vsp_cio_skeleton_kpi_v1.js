(function(){
  "use strict";
  const $ = (s,r)=> (r||document).querySelector(s);

  function ensureStyle(){
    if ($("#vspCioSkeletonStyle")) return;
    const css = `
      :root{
        --vsp-bg:#070a12;
        --vsp-card:#0b1220;
        --vsp-line:rgba(255,255,255,.08);
        --vsp-txt:rgba(255,255,255,.92);
        --vsp-dim:rgba(255,255,255,.72);
      }
      body{background:var(--vsp-bg)}
      .vspCioFadeIn{opacity:0;transform:translateY(2px);transition:opacity .18s ease,transform .18s ease}
      .vspCioFadeIn.vspCioOn{opacity:1;transform:none}
      .vspCioSkWrap{max-width:1400px;margin:0 auto;padding:14px}
      .vspCioGrid{display:grid;grid-template-columns:repeat(12,1fr);gap:12px}
      .vspCioCard{background:var(--vsp-card);border:1px solid var(--vsp-line);border-radius:16px;box-shadow:0 12px 30px rgba(0,0,0,.25)}
      .vspCioPad{padding:14px}
      .vspCioH{font-weight:700;letter-spacing:.2px;color:var(--vsp-txt);font-size:14px}
      .vspCioSub{color:var(--vsp-dim);font-size:12px}
      .vspCioMono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;font-size:12px;color:var(--vsp-dim)}
      .vspCioSk{position:relative;overflow:hidden;background:rgba(255,255,255,.04);border-radius:10px}
      .vspCioSk::after{
        content:"";position:absolute;inset:0;
        transform:translateX(-60%);
        background:linear-gradient(90deg,transparent,rgba(255,255,255,.07),transparent);
        animation:vspShimmer 1.1s infinite;
      }
      @keyframes vspShimmer{to{transform:translateX(60%)}}
      .vspCioSkRow{height:10px;margin-top:10px}
      .vspCioKpiRow{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px}
      .vspCioKpi{min-width:160px;flex:1;background:rgba(255,255,255,.03);border:1px solid var(--vsp-line);border-radius:14px;padding:12px}
      .vspCioKpiVal{font-weight:800;font-size:18px;color:var(--vsp-txt)}
      .vspCioKpiLab{font-size:11px;color:var(--vsp-dim);margin-top:3px}
    `;
    const st=document.createElement("style");
    st.id="vspCioSkeletonStyle";
    st.textContent=css;
    document.head.appendChild(st);
  }

  function mountSkeleton(){
    ensureStyle();
    if ($("#vspCioSkeleton")) return;
    const wrap=document.createElement("div");
    wrap.id="vspCioSkeleton";
    wrap.className="vspCioSkWrap vspCioFadeIn";
    wrap.innerHTML = `
      <div class="vspCioGrid">
        <div class="vspCioCard vspCioPad" style="grid-column:span 12">
          <div class="vspCioH">Loading dashboard…</div>
          <div class="vspCioSub">Preparing KPIs / charts / top findings</div>
          <div class="vspCioKpiRow">
            <div class="vspCioKpi"><div class="vspCioSk" style="height:18px;width:80px"></div><div class="vspCioSk vspCioSkRow" style="width:120px"></div></div>
            <div class="vspCioKpi"><div class="vspCioSk" style="height:18px;width:80px"></div><div class="vspCioSk vspCioSkRow" style="width:120px"></div></div>
            <div class="vspCioKpi"><div class="vspCioSk" style="height:18px;width:80px"></div><div class="vspCioSk vspCioSkRow" style="width:120px"></div></div>
            <div class="vspCioKpi"><div class="vspCioSk" style="height:18px;width:80px"></div><div class="vspCioSk vspCioSkRow" style="width:120px"></div></div>
          </div>
          <div class="vspCioSk vspCioSkRow" style="width:55%"></div>
          <div class="vspCioSk vspCioSkRow" style="width:70%"></div>
          <div class="vspCioSk vspCioSkRow" style="width:62%"></div>
        </div>

        <div class="vspCioCard vspCioPad" style="grid-column:span 7">
          <div class="vspCioH">Trends</div>
          <div class="vspCioSub">severity timeline</div>
          <div class="vspCioSk" style="height:220px;margin-top:12px"></div>
        </div>

        <div class="vspCioCard vspCioPad" style="grid-column:span 5">
          <div class="vspCioH">Top Findings</div>
          <div class="vspCioSub">largest impact first</div>
          <div style="margin-top:12px">
            <div class="vspCioSk vspCioSkRow" style="width:90%"></div>
            <div class="vspCioSk vspCioSkRow" style="width:86%"></div>
            <div class="vspCioSk vspCioSkRow" style="width:92%"></div>
            <div class="vspCioSk vspCioSkRow" style="width:84%"></div>
            <div class="vspCioSk vspCioSkRow" style="width:88%"></div>
          </div>
        </div>
      </div>
    `;
    document.body.insertBefore(wrap, document.body.children[1] || null); // after topbar
    requestAnimationFrame(()=>wrap.classList.add("vspCioOn"));
  }

  function unmountSkeleton(){
    const sk=$("#vspCioSkeleton");
    if (!sk) return;
    sk.classList.remove("vspCioOn");
    setTimeout(()=>{ try{ sk.remove(); }catch(_e){} }, 120);
  }

  function wrapMainContent(){
    // try common containers; fallback to body children
    const c = $("#vsp-dashboard-main") || $("#vsp-dashboard") || $("#vsp-root") || $("#main") || null;
    if (c && !c.classList.contains("vspCioFadeIn")) {
      c.classList.add("vspCioFadeIn");
      requestAnimationFrame(()=>c.classList.add("vspCioOn"));
    }
  }

  // Heuristic: remove skeleton after first meaningful API returns
  async function waitFirstData(){
    const rid = (typeof window.__vspGetRid==="function" ? (window.__vspGetRid()||"") : (new URLSearchParams(location.search).get("rid")||"")).trim();
    const url = "/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=1&offset=0";
    try{
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) throw new Error("api not ok");
      await r.json().catch(()=>({}));
      unmountSkeleton();
      wrapMainContent();
    }catch(_e){
      // still unmount after timeout to avoid stuck
      setTimeout(()=>{ unmountSkeleton(); wrapMainContent(); }, 1200);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>{
      mountSkeleton();
      waitFirstData();
    });
  } else {
    mountSkeleton();
    waitFirstData();
  }
})();
