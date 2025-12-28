
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = function(){ return document.visibilityState === "visible"; };
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.backoff = async function(fn, opt){
      opt = opt || {};
      let delay = opt.delay || 800;
      const maxDelay = opt.maxDelay || 8000;
      const maxTries = opt.maxTries || 6;
      for(let i=0;i<maxTries;i++){
        if(!window.__VSP_CIO.visible()){
          await window.__VSP_CIO.sleep(600);
          continue;
        }
        try { return await fn(); }
        catch(e){
          if(window.__VSP_CIO.debug) console.warn("[VSP] backoff retry", i+1, e);
          await window.__VSP_CIO.sleep(delay);
          delay = Math.min(maxDelay, delay*2);
        }
      }
      throw new Error("backoff_exhausted");
    };
    window.__VSP_CIO.api = {
      ridLatest: ()=>"/api/vsp/rid_latest_v3",
      runs: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gate: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsPage: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifact: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();


/* VSP_TABS3_V2 Data Source */
(() => {
  if(window.__vsp_ds_v2) return; window.__vsp_ds_v2=true;
  const { $, esc, api, ensure } = window.__vsp_tabs3_v2 || {};
  if(!ensure) return;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Findings table (latest run) · filter/search/pagination</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="ds_refresh">Refresh</button>
        </div>
      </div>

      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-row">
          <input class="vsp-in" id="ds_q" placeholder="search (tool/rule/message/file/cwe)..." style="flex:1;min-width:240px">
          <select class="vsp-in" id="ds_sev">
            <option value="">Overall: ALL</option>
            <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
          </select>
          <input class="vsp-in" id="ds_tool" placeholder="tool (exact)" style="min-width:160px">
          <select class="vsp-in" id="ds_limit">
            <option value="10">10/page</option>
            <option value="20" selected>20/page</option>
            <option value="50">50/page</option>
          </select>
        </div>
        <div class="vsp-muted" id="ds_meta" style="margin-top:8px;font-size:12px"></div>
      </div>

      <div class="vsp-card">
        <table class="vsp-t">
          <thead><tr><th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th></tr></thead>
          <tbody id="ds_tb"></tbody>
        </table>
        <div class="vsp-row" style="justify-content:flex-end;margin-top:8px">
          <button class="vsp-btn" id="ds_prev">Prev</button>
          <div class="vsp-muted" id="ds_page" style="min-width:110px;text-align:center">1/1</div>
          <button class="vsp-btn" id="ds_next">Next</button>
        </div>
      </div>
    `;

    const st = { offset:0, limit:20, total:0 };

    const q=$("#ds_q"), sev=$("#ds_sev"), tool=$("#ds_tool"), lim=$("#ds_limit");
    const tb=$("#ds_tb"), meta=$("#ds_meta"), page=$("#ds_page");

    function debounce(fn, ms=250){ let t=null; return ()=>{ clearTimeout(t); t=setTimeout(fn,ms); }; }

    async function load(){
      st.limit = parseInt(lim.value||"20",10)||20;
      const url = `/api/vsp/ui_findings_v2?limit=${encodeURIComponent(st.limit)}&offset=${encodeURIComponent(st.offset)}&q=${encodeURIComponent((q.value||"").trim())}&severity=${encodeURIComponent((sev.value||"").trim())}&tool=${encodeURIComponent((tool.value||"").trim().toLowerCase())}`;
      const j = await api(url);
      st.total = j.total||0;
      meta.textContent = `run_dir: ${j.run_dir||""} · total=${st.total} · showing ${Math.min(st.limit, Math.max(0, st.total-st.offset))}/${st.total}`;
      const items = j.items||[];
      tb.innerHTML = items.map(it=>`
        <tr>
          <td><span class="vsp-badge">${esc(it.severity||"")}</span></td>
          <td>${esc(it.tool||"")}</td>
          <td>${esc(it.rule_id||"")}</td>
          <td style="max-width:360px;word-break:break-word">${esc(it.file||"")}</td>
          <td>${esc(it.line||"")}</td>
          <td style="max-width:520px;word-break:break-word">${esc(it.message||"")}</td>
        </tr>`).join("");
      const pages = Math.max(1, Math.ceil((st.total||0)/st.limit));
      const cur = Math.min(pages, Math.floor((st.offset||0)/st.limit)+1);
      page.textContent = `${cur}/${pages}`;
      $("#ds_prev").disabled = (st.offset<=0);
      $("#ds_next").disabled = (st.offset + st.limit >= st.total);
    }

    const reload = debounce(()=>{ st.offset=0; load().catch(console.error); }, 250);
    q.addEventListener("input", reload);
    sev.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });
    tool.addEventListener("input", reload);
    lim.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });

    $("#ds_refresh").onclick = ()=>load().catch(console.error);
    $("#ds_prev").onclick = ()=>{ st.offset=Math.max(0, st.offset-st.limit); load().catch(console.error); };
    $("#ds_next").onclick = ()=>{ st.offset=st.offset+st.limit; load().catch(console.error); };

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
