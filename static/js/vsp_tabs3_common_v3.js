
/* ===================== VSP_P0_NO_POLL_REFRESH_ON_RID_CHANGE_V1L =====================
   Purpose: stop timer polling that causes XHR spam; refresh only when RID changes.
   Strategy:
   - Wrap setInterval for known polling intervals (>=2000ms) to no-op.
   - Provide a lightweight rid-change notifier.
=============================================================================== */
(function(){
  try{
    if (window.__VSP_NO_POLL_V1L__) return;
    window.__VSP_NO_POLL_V1L__ = true;

    // 1) Disable long polling intervals (keep short UI animation timers)
    const _setInterval = window.setInterval.bind(window);
    window.setInterval = function(fn, ms){
      try{
        const t = Number(ms||0);
        if (t >= 2000){
          // no-op: return a fake id
          return 0;
        }
      }catch(e){}
      return _setInterval(fn, ms);
    };

    // 2) RID change detection
    function getRid(){
      try{ return (new URL(location.href)).searchParams.get("rid") || ""; }catch(e){ return ""; }
    }
    let last = getRid();

    function notify(){
      try{
        const cur = getRid();
        if (cur && cur !== last){
          last = cur;
          // fire a soft event so tabs can re-render if they want
          window.dispatchEvent(new CustomEvent("vsp:rid_changed", { detail: { rid: cur } }));
        }
      }catch(e){}
    }

    // Hook history changes + popstate
    const _push = history.pushState;
    history.pushState = function(){
      const r = _push.apply(this, arguments);
      notify();
      return r;
    };
    const _replace = history.replaceState;
    history.replaceState = function(){
      const r = _replace.apply(this, arguments);
      notify();
      return r;
    };
    window.addEventListener("popstate", notify);

  }catch(e){}
})();


(() => {
  









/* VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1
   - Poll latest RID but ONLY accept RID that has  ok=true
   - Emit event: vsp:rid_changed
   - Auto refresh pages on RID change (safe: don't reload while typing)
*/
(()=> {
  try {
    if (window.__vsp_rid_latest_verified_autorefresh_v1) return;
    window.__vsp_rid_latest_verified_autorefresh_v1 = true;

    const STATE_KEY = "vsp_rid_state_v1";
    const saved = (()=>{ try { return JSON.parse(localStorage.getItem(STATE_KEY)||"{}"); } catch(e){ return {}; } })();

    window.__vsp_rid_state = window.__vsp_rid_state || {
      currentRid: saved.currentRid || "",
      followLatest: (saved.followLatest !== undefined) ? !!saved.followLatest : true,
      lastLatestRid: "",
      lastOkRid: saved.lastOkRid || "",
      pendingReload: false,
    };

    function saveState(){
      try{
        localStorage.setItem(STATE_KEY, JSON.stringify({
          currentRid: window.__vsp_rid_state.currentRid || "",
          followLatest: !!window.__vsp_rid_state.followLatest,
          lastOkRid: window.__vsp_rid_state.lastOkRid || ""
        }));
      }catch(e){}
    }

    function isTyping(){
      const a = document.activeElement;
      if(!a) return false;
      const tag = (a.tagName||"").toLowerCase();
      if(tag === "input" || tag === "textarea" || tag === "select") return true;
      if(a.isContentEditable) return true;
      // common editors
      const cls = (a.className||"").toString();
      if(cls.includes("cm-content") || cls.includes("monaco")) return true;
      return false;
    }

    function emitRidChanged(newRid, prevRid, reason){
      try{
        window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid:newRid, prevRid, reason}}));
      }catch(e){}
    }

    function setRid(newRid, reason){
      const st = window.__vsp_rid_state;
      if(!newRid || typeof newRid !== "string") return;
      if(newRid === st.currentRid) return;
      const prev = st.currentRid;
      st.currentRid = newRid;
      saveState();
      emitRidChanged(newRid, prev, reason || "set");
    }

    window.__vsp_getRid = function(){
      const st = window.__vsp_rid_state;
      if(st && st.currentRid) return st.currentRid;
      // fallback: query param rid
      try{
        const u = new URL(location.href);
        return u.searchParams.get("rid") || "";
      }catch(e){ return ""; }
    };
    window.__vsp_setRid = setRid;

    async function verifyRidHasGateSummary(rid){
      try{
        const url = `/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`;
        const r = await fetch(url);
        if(!r.ok) return false;
        const j = await r.json();
        return !!(j && j.ok);
      }catch(e){
        return false;
      }
    }

    async function pollLatestVerified(){
      const st = window.__vsp_rid_state;
      if(!st.followLatest) return;

      try{
        const r = await fetch("/api/vsp/rid_latest_v3");
        if(!r.ok) return;
        const j = await r.json();
        const runs = (j && (j.runs || j.items || j.data)) || [];
        const cands = [];
        for(const it of runs){
          const rid = (it && (it.rid || it.run_id || it.id)) || "";
          if(rid && typeof rid === "string") cands.push(rid);
        }
        if(!cands.length) return;

        // try candidates until one passes verify
        for(const rid of cands){
          st.lastLatestRid = rid;
          const ok = await verifyRidHasGateSummary(rid);
          if(ok){
            st.lastOkRid = rid;
            saveState();
            setRid(rid, "poll_latest_verified");
            return;
          }
        }

        // if none ok, do nothing (keep current rid)
      }catch(e){}
    }

    // Auto refresh on rid change (ALL tabs)
    const refreshable = new Set(["/vsp5","/data_source","/rule_overrides","/settings"]);
    function maybeReload(){
      if(!refreshable.has(location.pathname)) return;
      if(isTyping()){
        window.__vsp_rid_state.pendingReload = true;
        return;
      }
      setTimeout(()=>{ try{ location.reload(); }catch(e){} }, 250);
    }

    window.addEventListener("vsp:rid_changed", (ev)=>{
      try{
        // only reload when followLatest is on
        if(window.__vsp_rid_state && window.__vsp_rid_state.followLatest){
          maybeReload();
        }
      }catch(e){}
    });

    // If user stopped typing and we had pending reload, reload on blur/focusout
    window.addEventListener("focusout", ()=>{
      try{
        const st = window.__vsp_rid_state;
        if(st && st.pendingReload && !isTyping()){
          st.pendingReload = false;
          setTimeout(()=>{ try{ location.reload(); }catch(e){} }, 200);
        }
      }catch(e){}
    });

    // Hotkey: Alt+L toggle followLatest
    window.addEventListener("keydown", (ev)=>{
      if(ev.altKey && (ev.key==="l" || ev.key==="L")){
        ev.preventDefault();
        const st = window.__vsp_rid_state;
        st.followLatest = !st.followLatest;
        saveState();
        try{ console.log("[VSP] followLatest =", st.followLatest); }catch(e){}
        if(st.followLatest) pollLatestVerified();
      }
    }, {passive:false});

    // Start
    pollLatestVerified();
    setInterval(pollLatestVerified, 15000);

  } catch(e) {}
})();

/* VSP_NOISE_PANEL_ALLTABS_V1
   Alt+N: toggle panel
   Alt+Shift+N: clear log
*/
(()=> {
  try {
    if (window.__vsp_noise_panel_alltabs_v1) return;
    window.__vsp_noise_panel_alltabs_v1 = true;

    const KEY = "vsp_noise_log_v1";
    const MAX = 300;

    function now(){ return new Date().toISOString(); }
    function load(){
      try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch(e){ return []; }
    }
    function save(arr){
      try { localStorage.setItem(KEY, JSON.stringify(arr.slice(-MAX))); } catch(e){}
    }
    function push(item){
      const arr = load();
      arr.push(item);
      save(arr);
    }
    function clear(){
      try { localStorage.removeItem(KEY); } catch(e){}
    }

    function record(kind, data){
      push({
        t: now(),
        tab: location.pathname,
        kind,
        ...data
      });
    }

    // fetch hook
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch){
      window.fetch = async function(input, init){
        const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        try{
          const res = await _fetch(input, init);
          if (!res.ok){
            record("fetch", {status: res.status, url});
          }
          return res;
        }catch(e){
          record("fetch_exc", {status: 0, url, err: String(e && e.message || e)});
          throw e;
        }
      };
    }

    // XHR hook
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      const _send = XHR.prototype.send;
      XHR.prototype.open = function(method, url){
        this.__vsp_url = (typeof url === "string") ? url : "";
        return _open.apply(this, arguments);
      };
      XHR.prototype.send = function(){
        try{
          this.addEventListener("loadend", ()=>{
            try{
              const st = this.status || 0;
              if (st >= 400 || st === 0){
                record("xhr", {status: st, url: this.__vsp_url || ""});
              }
            }catch(e){}
          });
        }catch(e){}
        return _send.apply(this, arguments);
      };
    }

    // JS errors
    window.addEventListener("error", (ev)=>{
      try{
        record("js_error", {msg: String(ev.message||""), src: String(ev.filename||""), line: ev.lineno||0, col: ev.colno||0});
      }catch(e){}
    });

    window.addEventListener("unhandledrejection", (ev)=>{
      try{
        record("promise_rej", {msg: String(ev.reason && (ev.reason.message||ev.reason) || "unhandled")});
      }catch(e){}
    });

    // Panel UI
    function ensurePanel(){
      if (document.getElementById("vspNoisePanelV1")) return;
      const d = document.createElement("div");
      d.id = "vspNoisePanelV1";
      d.style.cssText = "position:fixed;right:12px;bottom:12px;z-index:999999;background:rgba(0,0,0,.85);color:#d6e0ff;border:1px solid rgba(255,255,255,.15);border-radius:12px;width:520px;max-height:60vh;overflow:auto;font:12px/1.4 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;box-shadow:0 12px 30px rgba(0,0,0,.35);display:none;";
      d.innerHTML = `
        <div style="padding:10px 10px 6px;display:flex;gap:8px;align-items:center;position:sticky;top:0;background:rgba(0,0,0,.9);">
          <div style="font-weight:700">VSP Noise</div>
          <div style="opacity:.7">Alt+N toggle • Alt+Shift+N clear</div>
          <div style="margin-left:auto;display:flex;gap:6px">
            <button id="vspNoiseRefreshV1" style="all:unset;cursor:pointer;padding:4px 8px;border:1px solid rgba(255,255,255,.2);border-radius:8px;">Refresh</button>
            <button id="vspNoiseClearV1" style="all:unset;cursor:pointer;padding:4px 8px;border:1px solid rgba(255,255,255,.2);border-radius:8px;">Clear</button>
          </div>
        </div>
        <div id="vspNoiseBodyV1" style="padding:8px 10px 10px;"></div>
      `;
      document.body.appendChild(d);
      document.getElementById("vspNoiseRefreshV1").onclick = render;
      document.getElementById("vspNoiseClearV1").onclick = ()=>{ clear(); render(); };
      render();
    }

    function render(){
      ensurePanel();
      const body = document.getElementById("vspNoiseBodyV1");
      const arr = load().slice().reverse();
      if (!arr.length){
        body.innerHTML = `<div style="opacity:.7">No noise 🎉</div>`;
        return;
      }
      body.innerHTML = arr.map(x=>{
        const u = (x.url||"").replace(location.origin,"");
        return `<div style="padding:6px 0;border-bottom:1px dashed rgba(255,255,255,.12)">
          <div><b>${x.kind}</b> <span style="opacity:.7">${x.t}</span> <span style="opacity:.7">(${x.tab})</span></div>
          ${x.status!==undefined?`<div>status: <b>${x.status}</b></div>`:""}
          ${u?`<div style="word-break:break-all">url: ${u}</div>`:""}
          ${x.msg?`<div style="word-break:break-word">msg: ${String(x.msg).slice(0,200)}</div>`:""}
        </div>`;
      }).join("");
    }

    function toggle(){
      ensurePanel();
      const el = document.getElementById("vspNoisePanelV1");
      el.style.display = (el.style.display === "none") ? "block" : "none";
      if (el.style.display === "block") render();
    }

    window.__vsp_noise = {render, toggle, clear};

    window.addEventListener("keydown", (ev)=>{
      if (ev.altKey && !ev.shiftKey && (ev.key==="n" || ev.key==="N")) { ev.preventDefault(); toggle(); }
      if (ev.altKey && ev.shiftKey && (ev.key==="n" || ev.key==="N")) { ev.preventDefault(); clear(); render(); }
    }, {passive:false});

  } catch(e) {}
})();

/* VSP_FOLLOW_LATEST_RID_POLL_V1
   - maintain a single RID state shared across tabs
   - optional follow-latest mode (poll /api/vsp/rid_latest_v3)
   - dispatch event: vsp:rid_changed {rid, prevRid, reason}
*/
(()=> {
  try {
    if (window.__vsp_follow_latest_rid_poll_v1) return;
    window.__vsp_follow_latest_rid_poll_v1 = true;

    const STATE_KEY = "vsp_follow_latest_rid";
    const saved = (()=>{ try { return JSON.parse(localStorage.getItem(STATE_KEY)||"{}"); } catch(e){ return {}; } })();

    window.__vsp_rid_state = window.__vsp_rid_state || {
      currentRid: saved.currentRid || "",
      followLatest: (saved.followLatest !== undefined) ? !!saved.followLatest : true,
      lastLatestRid: "",
      lastPollAt: 0,
    };

    function saveState(){
      try {
        localStorage.setItem(STATE_KEY, JSON.stringify({
          currentRid: window.__vsp_rid_state.currentRid || "",
          followLatest: !!window.__vsp_rid_state.followLatest
        }));
      } catch(e) {}
    }

    function setRid(newRid, reason){
      const st = window.__vsp_rid_state;
      if(!newRid || typeof newRid !== "string") return;
      if(newRid === st.currentRid) return;
      const prev = st.currentRid;
      st.currentRid = newRid;
      saveState();
      try{
        window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid:newRid, prevRid:prev, reason:reason||"set"}}));
      }catch(e){}
    }

    // Expose helper for other JS
    window.__vsp_set_rid = setRid;
    window.__vsp_save_rid_state = saveState;

    async function pollLatest(){
      const st = window.__vsp_rid_state;
      st.lastPollAt = Date.now();
      try{
        const r = await fetch("/api/vsp/rid_latest_v3");
        if(!r.ok) return;
        const j = await r.json();
        const runs = j && (j.runs || j.items || j.data) || [];
        const latest = runs && runs[0] && (runs[0].rid || runs[0].run_id || runs[0].id) || "";
        if(latest && typeof latest === "string"){
          st.lastLatestRid = latest;
          if(st.followLatest){
            setRid(latest, "poll_latest");
          }
        }
      }catch(e){}
    }

    // UI toggle (no HTML edits): Alt+L to toggle followLatest
    window.addEventListener("keydown", (ev)=>{
      if(ev.altKey && (ev.key === "l" || ev.key === "L")){
        window.__vsp_rid_state.followLatest = !window.__vsp_rid_state.followLatest;
        saveState();
        try{ console.log("[VSP] followLatest =", window.__vsp_rid_state.followLatest); }catch(e){}
        if (!window.__vsp_rid_latest_verified_autorefresh_v1 && window.__vsp_rid_state.followLatest) pollLatest(); }
    }, {passive:true});

    // Start polling
    /* VSP_DISABLE_OLD_FOLLOW_LATEST_POLL_V1 */
    if (!window.__vsp_rid_latest_verified_autorefresh_v1) {
      pollLatest();
      setInterval(pollLatest, 15000);
    }
  } catch(e) {}
})();

/* VSP_RUNFILEALLOW_FETCH_GUARD_V3C
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
   - covers fetch + XMLHttpRequest
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v3c) return;
    window.__vsp_runfileallow_fetch_guard_v3c = true;

    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\-]+$/.test(rid);
    }

    function _fix(url0){
      try{
        if(!url0 || typeof url0 !== "string") return {action:"pass"};
        if(!url0.includes("/api/vsp/_INTERNAL_DO_NOT_USE_run_file_allow")) return {action:"pass"};
        const u = new URL(url0, window.location.origin);
        const rid = u.searchParams.get("rid") || "";
        const path = u.searchParams.get("path") || "";
        if(!_isLikelyRid(rid)) return {action:"skip"};
        if(!path){
          u.searchParams.set("path","");
          return {action:"rewrite", url: u.toString().replace(window.location.origin,"")};
        }
        return {action:"pass"};
      }catch(e){
        return {action:"pass"};
      }
    }

    // fetch
    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (_origFetch){
      window.fetch = function(input, init){
        try{
          const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          const fx = _fix(url0);
          if (fx.action === "skip"){
            const body = JSON.stringify({ok:false, skipped:true, reason:"no rid"});
            return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json; charset=utf-8"}}));
          }
          if (fx.action === "rewrite"){
            if (typeof input === "string") input = fx.url;
            else input = new Request(fx.url, input);
          }
        }catch(e){}
        return _origFetch(input, init);
      };
    }

    // XHR
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      XHR.prototype.open = function(method, url, async, user, password){
        try{
          const url0 = (typeof url === "string") ? url : "";
          const fx = _fix(url0);
          if (fx.action === "skip"){
            const body = encodeURIComponent(JSON.stringify({ok:false, skipped:true, reason:"no rid"}));
            url = "data:application/json;charset=utf-8," + body;
          } else if (fx.action === "rewrite"){
            url = fx.url;
          }
        }catch(e){}
        return _open.call(this, method, url, async, user, password);
      };
    }
  } catch(e) {}
})();

/* VSP_RUNFILEALLOW_FETCH_GUARD_V1
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v1) return;
    window.__vsp_runfileallow_fetch_guard_v1 = true;

    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_origFetch) return;

    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\-]+$/.test(rid);
    }

    window.fetch = function(input, init){
      try {
        const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        if (url0 && url0.includes("/api/vsp/_INTERNAL_DO_NOT_USE_run_file_allow")) {
          const u = new URL(url0, window.location.origin);
          const rid = u.searchParams.get("rid") || "";
          const path = u.searchParams.get("path") || "";

          if (!_isLikelyRid(rid)) {
            const body = JSON.stringify({ok:false, skipped:true, reason:"no rid"});
            return Promise.resolve(new Response(body, {
              status: 200,
              headers: {"Content-Type":"application/json; charset=utf-8"}
            }));
          }

          if (!path) {
            u.searchParams.set("path", "");
            const fixed = u.toString().replace(window.location.origin, "");
            if (typeof input === "string") input = fixed;
            else input = new Request(fixed, input);
          }
        }
      } catch (e) {}
      return _origFetch(input, init);
    };
  } catch(e) {}
})();

if (window.__vsp_tabs3_v3) return;
  const $ = (s, r=document) => r.querySelector(s);
  const esc = (x)=> (x==null?'':String(x)).replace(/[&<>"']/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  async function api(url, opt){
    const r = await fetch(url, opt);
    const t = await r.text();
    let j; try{ j=JSON.parse(t); }catch(e){ j={ok:false, err:"non-json", raw:t.slice(0,800)}; }
    if(!r.ok) throw Object.assign(new Error("HTTP "+r.status), {status:r.status, body:j});
    return j;
  }
  function ensure(){
    if(document.getElementById("vsp_tabs3_v3_style")) return;
    const st=document.createElement("style");
    st.id="vsp_tabs3_v3_style";
    st.textContent=`
      .vsp-nav{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-bottom:12px}
      .vsp-nav-left{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
      .vsp-link{color:#cbd5e1;text-decoration:none;padding:6px 10px;border:1px solid rgba(148,163,184,.18);border-radius:999px;background:#0b1324}
      .vsp-link:hover{border-color:rgba(148,163,184,.45)}
      .vsp-active{border-color:rgba(99,102,241,.65)}
      .vsp-card{background:#0f1b2d;border:1px solid rgba(148,163,184,.18);border-radius:14px;padding:14px}
      .vsp-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
      .vsp-btn{background:#111c30;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;cursor:pointer}
      .vsp-btn:hover{border-color:rgba(148,163,184,.45)}
      .vsp-in{background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;outline:none}
      .vsp-muted{color:#94a3b8}
      .vsp-badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(148,163,184,.22);font-size:12px}
      table.vsp-t{width:100%;border-collapse:separate;border-spacing:0 8px}
      table.vsp-t th{font-weight:600;text-align:left;color:#cbd5e1;font-size:12px;padding:0 10px}
      table.vsp-t td{background:#0b1324;border-top:1px solid rgba(148,163,184,.18);border-bottom:1px solid rgba(148,163,184,.18);padding:10px;font-size:13px;vertical-align:top}
      table.vsp-t tr td:first-child{border-left:1px solid rgba(148,163,184,.18);border-top-left-radius:12px;border-bottom-left-radius:12px}
      table.vsp-t tr td:last-child{border-right:1px solid rgba(148,163,184,.18);border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-code{width:100%;min-height:320px;resize:vertical;font-family:ui-monospace,Menlo,Monaco,Consolas,monospace;background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:12px;padding:12px}
      .vsp-ok{color:#86efac}.vsp-err{color:#fca5a5}
    `;
    document.head.appendChild(st);
  }
  function mountNav(active){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    const nav = document.createElement("div");
    nav.className = "vsp-nav";
    nav.innerHTML = `
      <div class="vsp-nav-left">
        <a class="vsp-link ${active==='dashboard'?'vsp-active':''}" href="/vsp5">Dashboard</a>
        <a class="vsp-link ${active==='runs'?'vsp-active':''}" href="/runs">Runs & Reports</a>
        <a class="vsp-link ${active==='data_source'?'vsp-active':''}" href="/data_source">Data Source</a>
        <a class="vsp-link ${active==='settings'?'vsp-active':''}" href="/settings">Settings</a>
        <a class="vsp-link ${active==='rule_overrides'?'vsp-active':''}" href="/rule_overrides">Rule Overrides</a>
      </div>
      <div class="vsp-muted" style="font-size:12px">VSP UI</div>
    `;
    root.prepend(nav);
  }
  window.__vsp_tabs3_v3 = { $, esc, api, ensure, mountNav };
})();

/* VSP_P1_TABS3_COMMON_RELOAD_HOOKS_V1 */
(function(){
  function _clickRefreshHeuristic(){
    try{
      const btns = Array.from(document.querySelectorAll("button,a"));
      const keys = ["refresh","reload","tải lại","làm mới","update","sync"];
      for(const b of btns){
        const tx = (b.textContent||"").trim().toLowerCase();
        if(!tx) continue;
        if(keys.some(k=>tx.includes(k))){
          b.click();
          return true;
        }
      }
    }catch(e){}
    return false;
  }

  async function _emitReloadEvent(kind){
    try{
      window.dispatchEvent(new CustomEvent("vsp:reload-request", {detail:{kind, rid: window.VSP_CURRENT_RID||null}}));
    }catch(e){}
  }

  window.VSP_reloadSettings = async function(){
    await _emitReloadEvent("settings");
    if(_clickRefreshHeuristic()) return;
  };

  window.VSP_reloadDataSource = async function(){
    await _emitReloadEvent("data_source");
    if(_clickRefreshHeuristic()) return;
  };

  window.VSP_reloadRuleOverrides = async function(){
    await _emitReloadEvent("rule_overrides");
    if(_clickRefreshHeuristic()) return;
  };

  // umbrella
  window.VSP_reloadAll = async function(){
    try{ await window.VSP_reloadSettings(); }catch(e){}
    try{ await window.VSP_reloadDataSource(); }catch(e){}
    try{ await window.VSP_reloadRuleOverrides(); }catch(e){}
  };
})();


/* VSP_P1_TABS3_LISTEN_RID_CHANGED_V1 */
(()=>{
  try{
    window.addEventListener('VSP_RID_CHANGED',(ev)=>{
      try{
        // call reload hooks if present
        if(typeof window.VSP_reloadDataSource==='function') window.VSP_reloadDataSource(ev.detail||{});
        if(typeof window.VSP_reloadRuleOverrides==='function') window.VSP_reloadRuleOverrides(ev.detail||{});
        if(typeof window.VSP_reloadSettings==='function') window.VSP_reloadSettings(ev.detail||{});
      }catch(e){}
    });
  }catch(e){}
})();
