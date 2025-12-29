// P923B_SETTINGS_FULL_COMMERCIAL_V1 (syntax-safe, commercial-grade)
// Goals:
// - Never throw SyntaxError (node --check must pass)
// - Render a full Settings page (CIO-friendly)
// - Keep mounting Ops Panel (P920): journal/log_tail/evidence
// - Be resilient if APIs change (show raw JSON)
(function(){
  "use strict";

  const TAG = "P923B_SETTINGS_FULL_COMMERCIAL_V1";
  const API = {
    run_status: "/api/vsp/run_status_v1",
    ops_latest: "/api/vsp/ops_latest_v1"
  };
  const OPS_JS = "/static/js/vsp_ops_panel_v1.js";

  function el(tag, attrs, ...children){
    const n = document.createElement(tag);
    if (attrs){
      for (const [k,v] of Object.entries(attrs)){
        if (v === null || v === undefined) continue;
        if (k === "class") n.className = String(v);
        else if (k === "style") n.setAttribute("style", String(v));
        else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
        else n.setAttribute(k, String(v));
      }
    }
    for (const c of children.flat()){
      if (c === null || c === undefined) continue;
      if (typeof c === "string") n.appendChild(document.createTextNode(c));
      else n.appendChild(c);
    }
    return n;
  }

  function safeJson(x){
    try { return JSON.stringify(x, null, 2); } catch(e){ return String(x); }
  }

  function collapse(title, bodyNode){
    const wrap = el("div", {class:"vsp-card vsp-card--collapse"});
    const btn = el("button", {class:"vsp-collapse-btn", type:"button"},
      el("span", {class:"vsp-collapse-title"}, title),
      el("span", {class:"vsp-collapse-icon"}, "▸")
    );
    const body = el("div", {class:"vsp-collapse-body", style:"display:none"});
    body.appendChild(bodyNode);

    let open = false;
    function setOpen(v){
      open = !!v;
      body.style.display = open ? "block" : "none";
      btn.querySelector(".vsp-collapse-icon").textContent = open ? "▾" : "▸";
    }
    btn.addEventListener("click", ()=>setOpen(!open));
    setOpen(false);

    wrap.appendChild(btn);
    wrap.appendChild(body);
    return wrap;
  }

  async function fetchJson(url, timeoutMs){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs || 8000);
    try{
      const r = await fetch(url, {signal: ctrl.signal, cache:"no-store"});
      const txt = await r.text();
      let j = null;
      try { j = JSON.parse(txt); } catch(e){ j = { raw: txt }; }
      return { ok: r.ok, status: r.status, json: j };
    } finally {
      clearTimeout(t);
    }
  }

  function ensureRoot(){
    // Prefer an existing app container if present; otherwise create one.
    let root =
      document.querySelector("#vsp_settings_root") ||
      document.querySelector("#vsp_main") ||
      document.querySelector("main") ||
      document.querySelector("#app") ||
      document.body;

    // Always render into a dedicated root to avoid clobbering other tabs.
    let host = document.querySelector("#vsp_settings_root");
    if (!host){
      host = el("div", {id:"vsp_settings_root", class:"vsp-settings-root"});
      root.appendChild(host);
    } else {
      host.innerHTML = "";
    }
    return host;
  }

  function ensureOpsPanelHost(container){
    let h = container.querySelector("#vsp_ops_panel_host");
    if (!h){
      h = el("div", {id:"vsp_ops_panel_host"});
      container.appendChild(h);
    }
    return h;
  }

  function loadOpsPanelJsOnce(cb){
    if (window.VSPOpsPanel && typeof window.VSPOpsPanel.ensureMounted === "function"){
      cb && cb();
      return;
    }
    const id = "vsp_ops_panel_js";
    if (document.getElementById(id)){
      cb && cb();
      return;
    }
    const s = el("script", {id, src: OPS_JS});
    s.onload = ()=>{ cb && cb(); };
    s.onerror = ()=>{ /* do not crash */ };
    document.head.appendChild(s);
  }

  function renderPlaybook(){
    return el("div", {},
      el("div", {class:"vsp-muted"},
        "Settings • Commercial Playbook (CIO/ISO-ready). ",
        "Mục tiêu: ổn định, có bằng chứng, không crash, degrade-graceful."
      ),
      el("div", {class:"vsp-muted", style:"margin-top:6px"},
        "Tabs chuẩn: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides."
      )
    );
  }

  function renderToolsBox(){
    const items = [
      ["Bandit (SAST)", "Python security checks → JSON."],
      ["Semgrep (SAST)", "Ruleset → JSON/SARIF."],
      ["Gitleaks (Secrets)", "Detect secrets → JSON."],
      ["KICS (IaC)", "Scan IaC → JSON/SARIF (timeout/degraded supported)."],
      ["Trivy (Vuln)", "Container/FS vuln → JSON."],
      ["Syft (SBOM)", "Generate SBOM → JSON."],
      ["Grype (SCA)", "Vuln from SBOM → JSON."],
      ["CodeQL (Deep SAST)", "SARIF (timeout/degraded supported)."]
    ];
    const grid = el("div", {class:"vsp-grid"});
    for (const [k, v] of items){
      grid.appendChild(el("div", {class:"vsp-mini-card"},
        el("div", {class:"vsp-mini-title"}, k),
        el("div", {class:"vsp-mini-desc"}, v)
      ));
    }
    return grid;
  }

  function renderNormBox(){
    return el("div", {},
      el("div", {class:"vsp-muted"}, "Severity normalization: CRITICAL / HIGH / MEDIUM / LOW / INFO / TRACE."),
      el("div", {class:"vsp-muted", style:"margin-top:6px"},
        "Gợi ý: mapping từ tool severity về 6 mức DevSecOps để gate & dashboard thống nhất."
      )
    );
  }

  function renderIsoBox(){
    return el("div", {},
      el("div", {class:"vsp-muted"},
        "ISO 27001 mapping (skeleton): mục tiêu là traceable controls → findings → evidence → report."
      )
    );
  }

  function renderEndpointProbes(runStatus){
    const wrap = el("div", {});
    const head = el("div", {class:"vsp-muted"}, "Endpoint probes & Raw JSON (stable, collapsible).");
    wrap.appendChild(head);

    const probes = (runStatus && runStatus.json && (runStatus.json.probes || runStatus.json.endpoints)) || null;

    // Table
    if (Array.isArray(probes) && probes.length){
      const table = el("table", {class:"vsp-table"});
      table.appendChild(el("thead", {},
        el("tr", {},
          el("th", {}, "Endpoint"),
          el("th", {}, "Status"),
          el("th", {}, "Time")
        )
      ));
      const tb = el("tbody", {});
      for (const it of probes){
        const ep = it.endpoint || it.path || it.url || "";
        const st = String(it.status || it.code || it.http_code || "");
        const ms = String(it.ms || it.time_ms || it.time || "");
        tb.appendChild(el("tr", {},
          el("td", {}, ep),
          el("td", {}, st),
          el("td", {}, ms)
        ));
      }
      table.appendChild(tb);
      wrap.appendChild(table);
    } else {
      wrap.appendChild(el("div", {class:"vsp-muted", style:"margin-top:8px"},
        "Schema probes chưa đúng dạng array → hiển thị Raw JSON bên dưới."
      ));
    }

    const raw = el("pre", {class:"vsp-pre"}, safeJson(runStatus && runStatus.json));
    wrap.appendChild(raw);
    return wrap;
  }

  function renderOpsStatus(runStatus, opsLatest){
    const okStatus = (runStatus && runStatus.ok) ? "OK" : "DEGRADED";
    const code = runStatus ? runStatus.status : 0;

    const box = el("div", {class:"vsp-ops-box"},
      el("div", {class:"vsp-ops-row"},
        el("div", {class:"vsp-ops-k"}, "service"),
        el("div", {class:"vsp-ops-v"}, (opsLatest && opsLatest.json && opsLatest.json.svc) ? opsLatest.json.svc : "(unknown)"),
        el("div", {class:"vsp-ops-badge " + (okStatus==="OK" ? "ok":"bad")}, okStatus)
      ),
      el("div", {class:"vsp-ops-row"},
        el("div", {class:"vsp-ops-k"}, "base"),
        el("div", {class:"vsp-ops-v"}, location.origin),
        el("div", {class:"vsp-ops-k"}, "http_code"),
        el("div", {class:"vsp-ops-v"}, String(code))
      ),
      el("div", {class:"vsp-ops-row"},
        el("button", {class:"vsp-btn", type:"button", onclick: ()=>location.reload()}, "Refresh"),
        el("button", {class:"vsp-btn vsp-btn-secondary", type:"button", onclick: ()=>{
          // open raw json in a new tab-like view: just alert pre text length safe
          const j = { run_status: runStatus && runStatus.json, ops_latest: opsLatest && opsLatest.json };
          const w = window.open("", "_blank");
          if (w){ w.document.write("<pre>"+safeJson(j).replace(/</g,"&lt;")+"</pre>"); }
        }}, "View JSON")
      )
    );

    return box;
  }

  function injectTinyStyle(){
    if (document.getElementById("vsp_settings_style_p923b")) return;
    const css = `
#vsp_settings_root{max-width:1100px;margin:18px auto;padding:6px 14px;color:#e8eefc}
.vsp-muted{opacity:.78;font-size:12px;line-height:1.4}
.vsp-card{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:12px;margin:10px 0}
.vsp-title{font-size:18px;font-weight:700;margin:0 0 6px}
.vsp-sub{font-size:12px;opacity:.75;margin:0 0 10px}
.vsp-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.vsp-mini-card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.07);border-radius:10px;padding:10px}
.vsp-mini-title{font-weight:700;font-size:12px;margin-bottom:4px}
.vsp-mini-desc{font-size:12px;opacity:.78}
.vsp-collapse-btn{width:100%;display:flex;justify-content:space-between;align-items:center;background:transparent;border:0;color:inherit;padding:0;font-weight:700;cursor:pointer}
.vsp-collapse-title{font-size:13px}
.vsp-collapse-body{margin-top:10px}
.vsp-pre{white-space:pre-wrap;word-break:break-word;background:rgba(0,0,0,.22);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:10px;font-size:12px}
.vsp-table{width:100%;border-collapse:collapse;margin-top:10px}
.vsp-table th,.vsp-table td{border-bottom:1px solid rgba(255,255,255,.08);padding:8px;font-size:12px;text-align:left}
.vsp-ops-box{background:rgba(0,0,0,.12);border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:10px}
.vsp-ops-row{display:flex;gap:10px;align-items:center;margin:6px 0;flex-wrap:wrap}
.vsp-ops-k{opacity:.7;font-size:12px;min-width:70px}
.vsp-ops-v{font-size:12px}
.vsp-ops-badge{margin-left:auto;padding:3px 10px;border-radius:999px;font-size:11px;border:1px solid rgba(255,255,255,.14)}
.vsp-ops-badge.ok{background:rgba(34,197,94,.15)}
.vsp-ops-badge.bad{background:rgba(239,68,68,.15)}
.vsp-btn{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);border-radius:10px;color:#e8eefc;padding:6px 10px;font-size:12px;cursor:pointer}
.vsp-btn:hover{background:rgba(255,255,255,.12)}
.vsp-btn-secondary{opacity:.9}
@media (max-width:820px){.vsp-grid{grid-template-columns:1fr}}
`;
    const st = document.createElement("style");
    st.id = "vsp_settings_style_p923b";
    st.textContent = css;
    document.head.appendChild(st);
  }

  async function main(){
    injectTinyStyle();

    const host = ensureRoot();
    const header = el("div", {class:"vsp-card"},
      el("div", {class:"vsp-title"}, "Settings"),
      el("div", {class:"vsp-sub"}, "Commercial • CIO/ISO-ready • " + TAG)
    );
    host.appendChild(header);

    const playbook = el("div", {class:"vsp-card"}, renderPlaybook());
    host.appendChild(playbook);

    const tools = el("div", {class:"vsp-card"},
      el("div", {class:"vsp-title", style:"font-size:14px"}, "8-tool suite & artifacts"),
      renderToolsBox()
    );
    host.appendChild(tools);

    host.appendChild(el("div", {class:"vsp-card"},
      collapse("Degraded / Timeout policy (commercial)", el("div", {class:"vsp-muted"},
        "KICS/CodeQL có thể timeout → pipeline không treo: đánh dấu degraded + vẫn xuất evidence/logs."
      ))
    ));

    host.appendChild(el("div", {class:"vsp-card"},
      collapse("Severity normalization (6 DevSecOps levels)", renderNormBox())
    ));

    host.appendChild(el("div", {class:"vsp-card"},
      collapse("ISO 27001 mapping (skeleton)", renderIsoBox())
    ));

    // Fetch API status
    const [rs, ops] = await Promise.all([
      fetchJson(API.run_status, 8000).catch(()=>({ok:false,status:0,json:{error:"fetch_failed"}})),
      fetchJson(API.ops_latest, 8000).catch(()=>({ok:false,status:0,json:{error:"fetch_failed"}})),
    ]);

    // Endpoint probes
    host.appendChild(el("div", {class:"vsp-card"},
      collapse("Endpoint probes (P405) + Raw JSON", renderEndpointProbes(rs))
    ));

    // Ops Panel Host + mount
    const opsCard = el("div", {class:"vsp-card"});
    opsCard.appendChild(el("div", {class:"vsp-title", style:"font-size:14px"}, "Ops Status (CIO)"));
    opsCard.appendChild(renderOpsStatus(rs, ops));

    const opsHost = ensureOpsPanelHost(opsCard);
    opsHost.appendChild(el("div", {class:"vsp-muted", style:"margin-top:8px"},
      "Ops panel details (journal / log tail / evidence.zip) will mount below if available."
    ));
    host.appendChild(opsCard);

    loadOpsPanelJsOnce(()=>{
      try{
        if (window.VSPOpsPanel && typeof window.VSPOpsPanel.ensureMounted === "function"){
          window.VSPOpsPanel.ensureMounted();
        }
      } catch(e){ /* never crash */ }
    });
  }

  // Only run on /c/settings (avoid accidental render on other tabs)
  function shouldRun(){
    const p = location.pathname || "";
    return (p === "/c/settings" || p.endsWith("/c/settings"));
  }

  if (!shouldRun()){
    // Do nothing on other pages.
    return;
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ main().catch(()=>{}); });
  } else {
    main().catch(()=>{});
  }
})();
