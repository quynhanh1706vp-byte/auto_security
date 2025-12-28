/* VSP_P473_SIDEBAR_FRAME_ALL_TABS_V1 */
(function(){
  if (window.__VSP_SIDEBAR_FRAME_V1__) return;
  window.__VSP_SIDEBAR_FRAME_V1__ = 1;

  const W = 220;
  const LABELS = [
    ["Dashboard","/c/dashboard"],
    ["Runs & Reports","/c/runs"],
    ["Data Source","/c/data_source"],
    ["Settings","/c/settings"],
    ["Rule Overrides","/c/rule_overrides"],
  ];

  function ensureCss(){
    if (document.getElementById("vsp_p473_css")) return;
    const st = document.createElement("style");
    st.id = "vsp_p473_css";
    st.textContent = `
:root{--vsp_side_w:${W}px}
#vsp_side_menu_v1{position:fixed;top:0;left:0;bottom:0;width:var(--vsp_side_w);z-index:999999;
  background:rgba(10,14,22,0.98);border-right:1px solid rgba(255,255,255,0.08);
  padding:14px 12px;font-family:inherit}
#vsp_side_menu_v1 .vsp_brand{font-weight:800;letter-spacing:.3px;font-size:13px;margin:2px 0 12px 2px;opacity:.95}
#vsp_side_menu_v1 a{display:flex;align-items:center;gap:10px;text-decoration:none;
  color:rgba(255,255,255,0.84);padding:10px 10px;border-radius:12px;margin:6px 0;
  background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a:hover{background:rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a.active{background:rgba(99,179,237,0.14);border-color:rgba(99,179,237,0.35);color:#fff}

/* shift whole app */
html.vsp_p473_pad, body.vsp_p473_pad{padding-left:var(--vsp_side_w)}

/* shared commercial frame */
.vsp_p473_frame{
  max-width: 1440px;
  margin: 0 auto;
  padding: 16px 18px 26px;
}
`;
    document.head.appendChild(st);
  }

  function ensureMenu(){
    ensureCss();
    if (document.getElementById("vsp_side_menu_v1")) return;

    const menu = document.createElement("div");
    menu.id = "vsp_side_menu_v1";

    const brand = document.createElement("div");
    brand.className = "vsp_brand";
    brand.textContent = "VSP • Commercial";
    menu.appendChild(brand);

    const path = location.pathname || "";
    for (const [name, href] of LABELS){
      const a = document.createElement("a");
      a.href = href;
      a.textContent = name;
      if (path === href) a.classList.add("active");
      menu.appendChild(a);
    }
    document.body.appendChild(menu);

    document.documentElement.classList.add("vsp_p473_pad");
    document.body.classList.add("vsp_p473_pad");
  }

  function ensureFrame(){
    const root =
      document.querySelector("#vsp_app") ||
      document.querySelector("#app") ||
      document.querySelector("#root") ||
      document.querySelector("main") ||
      document.querySelector(".container") ||
      null;

    if (root) {
      root.classList.add("vsp_p473_frame");
      return;
    }

    // fallback: wrap body children
    if (document.getElementById("vsp_p473_wrap")) return;
    const wrap = document.createElement("div");
    wrap.id = "vsp_p473_wrap";
    wrap.className = "vsp_p473_frame";
    while (document.body.firstChild) wrap.appendChild(document.body.firstChild);
    document.body.appendChild(wrap);
  }

  function boot(){
    try{
      ensureMenu();
      ensureFrame();
      console && console.log && console.log("[P473] sidebar+frame ready");
    }catch(e){
      console && console.warn && console.warn("[P473] err", e);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 30));
  } else {
    setTimeout(boot, 30);
  }
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


/* VSP_P474_GLOBAL_POLISH_NO_RUN_V1 */
(function(){
  function addCss2(){
    if(document.getElementById("vsp_p474_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p474_css";
    st.textContent=`
/* ===== Commercial UI polish (global) ===== */
.vsp_p473_frame{max-width:1440px}
.vsp_p473_frame, #vsp_p473_wrap{min-height:calc(100vh - 10px)}
body{letter-spacing:.1px}
h1,h2,h3{font-weight:800}

/* Unified card */
.vsp_card{
  background:rgba(255,255,255,0.02);
  border:1px solid rgba(255,255,255,0.06);
  border-radius:16px;
  box-shadow:0 10px 30px rgba(0,0,0,0.25);
}

/* Tables */
table{border-collapse:separate;border-spacing:0;width:100%}
th,td{padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.06)}
th{font-size:12px;opacity:.85;text-transform:uppercase;letter-spacing:.7px}
tr:hover td{background:rgba(255,255,255,0.02)}
div[role="row"], .row{border-bottom:1px solid rgba(255,255,255,0.06)}

/* Inputs */
input,select,textarea{
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.9);
  border:1px solid rgba(255,255,255,0.08);
  border-radius:12px;
  padding:10px 12px;
  outline:none;
}
input:focus,select:focus,textarea:focus{
  border-color:rgba(99,179,237,0.40);
  box-shadow:0 0 0 3px rgba(99,179,237,0.14);
}

/* Buttons */
button, .btn, a.btn{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:8px 12px;
}
button:hover, .btn:hover, a.btn:hover{background:rgba(255,255,255,0.06)}
button:disabled{opacity:.5;cursor:not-allowed}

/* Badge */
.vsp_badge{
  display:inline-flex;align-items:center;gap:6px;
  padding:4px 10px;border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  font-size:12px;opacity:.92;
}

/* Title bar */
#vsp_p474_titlebar{
  display:flex;align-items:center;justify-content:space-between;
  gap:12px;margin:6px 0 14px;
  padding:12px 14px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_p474_titlebar .t{font-weight:900;font-size:14px;letter-spacing:.3px}
#vsp_p474_titlebar .sub{font-size:12px;opacity:.75;margin-top:2px}
#vsp_p474_titlebar .r{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
`;
    document.head.appendChild(st);
  }

  function inferTitle(){
    const a=document.querySelector("#vsp_side_menu_v1 a.active");
    return a ? (a.textContent||"").trim() : "VSP";
  }

  function injectTitlebar(){
    addCss2();
    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;
    if(document.getElementById("vsp_p474_titlebar")) return;

    const bar=document.createElement("div");
    bar.id="vsp_p474_titlebar";

    const left=document.createElement("div");
    const t=document.createElement("div"); t.className="t"; t.textContent=inferTitle();
    const sub=document.createElement("div"); sub.className="sub"; sub.textContent=location.pathname;
    left.appendChild(t); left.appendChild(sub);

    const right=document.createElement("div");
    right.className="r";
    const env=document.createElement("span");
    env.className="vsp_badge";
    env.textContent="LOCAL • 127.0.0.1";
    right.appendChild(env);

    bar.appendChild(left);
    bar.appendChild(right);

    if(root === document.body) document.body.insertBefore(bar, document.body.firstChild);
    else root.insertBefore(bar, root.firstChild);
  }

  function boot(){
    try{
      injectTitlebar();
      console && console.log && console.log("[P474] global polish applied");
    }catch(e){
      console && console.warn && console.warn("[P474] err", e);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 50));
  else setTimeout(boot, 50);
})();


/* VSP_P478_DEDUPE_INNER_NAV_ALL_TABS_V1 */
(function(){
  if (window.__VSP_P478__) return;
  window.__VSP_P478__ = 1;

  const TABN = ["Dashboard","Runs & Reports","Data Source","Settings","Rule Overrides"]
    .map(s=>s.toLowerCase());

  function ensureCss(){
    if(document.getElementById("vsp_p478_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p478_css";
    st.textContent=`
/* hide duplicate inner nav bars (best-effort) */
.vsp_p478_hide_dupnav{display:none!important}

/* slightly better top spacing inside frame */
.vsp_p473_frame{padding-top:14px}
`;
    document.head.appendChild(st);
  }

  function looksLikeDupNav(el){
    try{
      if(!el || el.id==="vsp_side_menu_v1") return false;
      const h = el.getBoundingClientRect ? el.getBoundingClientRect().height : 999;
      if(h > 140) return false; // nav row usually short
      const btns = el.querySelectorAll ? el.querySelectorAll("a,button") : [];
      if(btns.length < 3) return false;

      const txt = (el.innerText || "").toLowerCase();
      let hit = 0;
      for(const n of TABN){ if(txt.includes(n)) hit++; }
      return hit >= 3; // strong signal it's the 5-tab strip
    }catch(e){
      return false;
    }
  }

  function hideDuplicateNavBars(){
    // scan likely containers; hide the first strong match
    const nodes = Array.from(document.querySelectorAll("nav,header,section,div"));
    let hidden = 0;
    for(const el of nodes){
      if(hidden >= 2) break;
      if(looksLikeDupNav(el)){
        el.classList.add("vsp_p478_hide_dupnav");
        hidden++;
      }
    }
    if(hidden){
      console && console.log && console.log("[P478] hidden dup nav bars:", hidden);
    } else {
      console && console.log && console.log("[P478] no dup nav found");
    }
  }

  function boot(){
    try{
      ensureCss();
      setTimeout(hideDuplicateNavBars, 250);
      setTimeout(hideDuplicateNavBars, 900); // second pass after async render
    }catch(e){
      console && console.warn && console.warn("[P478] err", e);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();



/* VSP_P480_SETTINGS_CIO_DOCS_NO_RUN_V1 */
(function(){
  if (window.__VSP_P480__) return;
  window.__VSP_P480__ = 1;

  // hard policy: no demo in commercial build
  try{ localStorage.removeItem("VSP_DEMO_RUNS"); }catch(e){}

  function ensureCss(){
    if(document.getElementById("vsp_p480_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p480_css";
    st.textContent=`
#vsp_p480_docs{
  margin:14px 0;
  padding:16px 16px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_p480_docs .h{
  display:flex;align-items:flex-start;justify-content:space-between;gap:12px;
}
#vsp_p480_docs .t{font-weight:900;font-size:14px;letter-spacing:.25px}
#vsp_p480_docs .sub{opacity:.75;font-size:12px;margin-top:2px;line-height:1.5}
#vsp_p480_docs details{
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  border-radius:14px;
  padding:10px 12px;
  margin-top:10px;
}
#vsp_p480_docs summary{
  cursor:pointer;
  user-select:none;
  font-weight:800;
  letter-spacing:.2px;
}
#vsp_p480_docs .p{
  margin-top:8px;
  opacity:.88;
  font-size:12px;
  line-height:1.6;
}
#vsp_p480_docs code{
  background:rgba(0,0,0,0.25);
  border:1px solid rgba(255,255,255,0.08);
  padding:2px 6px;
  border-radius:8px;
}
#vsp_p480_docs .grid{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:10px;
  margin-top:10px;
}
@media (max-width: 1100px){
  #vsp_p480_docs .grid{grid-template-columns:1fr}
}
#vsp_p480_docs .k{
  border:1px solid rgba(255,255,255,0.06);
  border-radius:14px;
  padding:10px 12px;
  background:rgba(255,255,255,0.02);
}
#vsp_p480_docs .k .kt{font-weight:900;font-size:12px;opacity:.95}
#vsp_p480_docs .k .kd{margin-top:6px;opacity:.82;font-size:12px;line-height:1.55}
`;
    document.head.appendChild(st);
  }

  function mountDocs(){
    if(!location.pathname.includes("/c/settings")) return;

    ensureCss();

    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;

    if(document.getElementById("vsp_p480_docs")) return;

    const box=document.createElement("div");
    box.id="vsp_p480_docs";

    const head=document.createElement("div");
    head.className="h";
    const L=document.createElement("div");
    const t=document.createElement("div"); t.className="t"; t.textContent="Settings • Commercial Playbook (CIO/ISO-ready)";
    const sub=document.createElement("div");
    sub.className="sub";
    sub.innerHTML="Chuẩn thương mại: cấu hình, hành vi degraded/timeout, chuẩn severity 6 mức, và mapping ISO 27001.<br/>Không dùng DEMO — chỉ dữ liệu thật từ pipeline.";
    L.appendChild(t); L.appendChild(sub);

    head.appendChild(L);
    box.appendChild(head);

    // 1) Tools overview
    const d1=document.createElement("details"); d1.open=true;
    d1.innerHTML = `
<summary>8-tool suite & artifacts</summary>
<div class="p">
  Pipeline mặc định gồm: <b>Bandit</b>, <b>Semgrep</b>, <b>Gitleaks</b>, <b>KICS</b>, <b>Trivy</b>, <b>Syft</b>, <b>Grype</b>, <b>CodeQL</b>.
  Mỗi tool phải tạo raw output + summary, sau đó merge ra <code>findings_unified.{json,csv,sarif}</code> và <code>run_gate_summary.json</code>.
</div>
<div class="grid">
  <div class="k"><div class="kt">Bandit (SAST-Python)</div><div class="kd">Scan code Python. Output: JSON/text. Map severity → 6 levels.</div></div>
  <div class="k"><div class="kt">Semgrep (SAST)</div><div class="kd">Ruleset + custom overrides. Output: JSON/SARIF.</div></div>
  <div class="k"><div class="kt">Gitleaks (Secrets)</div><div class="kd">Secrets in repo. Output: JSON. Gate thường HIGH/CRITICAL.</div></div>
  <div class="k"><div class="kt">KICS (IaC)</div><div class="kd">Terraform/K8s/IaC misconfig. Output: JSON/SARIF. Cần timeout + degraded-graceful.</div></div>
  <div class="k"><div class="kt">Trivy (Vuln scan)</div><div class="kd">Config/SBOM/containers. Output: JSON. Nên normalize CVSS/severity.</div></div>
  <div class="k"><div class="kt">Syft (SBOM)</div><div class="kd">Generate SBOM. Output: JSON. Input cho Grype.</div></div>
  <div class="k"><div class="kt">Grype (SCA)</div><div class="kd">Vulnerability from SBOM. Output: JSON. Gate theo severity normalized.</div></div>
  <div class="k"><div class="kt">CodeQL (Deep SAST)</div><div class="kd">Chạy lâu → bắt buộc timeout + degraded status nếu thiếu tool/index.</div></div>
</div>
`;
    box.appendChild(d1);

    // 2) Degraded / timeout policy
    const d2=document.createElement("details");
    d2.innerHTML = `
<summary>Degraded / Timeout policy (commercial)</summary>
<div class="p">
  Nguyên tắc: pipeline <b>không được treo</b>. Tool thiếu/timeout → đánh dấu <b>DEGRADED</b> và vẫn xuất report + evidence.
  Ví dụ: KICS/CodeQL timeout thì status tool = degraded, tổng run vẫn có <code>run_status_v1</code> + <code>SUMMARY.txt</code>.
</div>
<div class="p">
  Checklist:
  <ul>
    <li>Mỗi tool có <code>timeout</code> wrapper.</li>
    <li>Missing binary → degraded (không crash cả pipeline).</li>
    <li>Log path rõ ràng + tail parser cập nhật <code>run_status_v1</code>.</li>
    <li>Artifacts tối thiểu: raw + summary + stdout/stderr + timestamps.</li>
  </ul>
</div>
`;
    box.appendChild(d2);

    // 3) Severity normalization
    const d3=document.createElement("details");
    d3.innerHTML = `
<summary>Severity normalization (6 DevSecOps levels)</summary>
<div class="p">
  Chuẩn hoá severity bắt buộc đúng 6 mức: <b>CRITICAL</b>, <b>HIGH</b>, <b>MEDIUM</b>, <b>LOW</b>, <b>INFO</b>, <b>TRACE</b>.
  Mọi findings từ tools phải map về đúng 6 mức này trước khi merge.
</div>
<div class="p">
  Gợi ý rule:
  <ul>
    <li>CVSS ≥ 9.0 → CRITICAL</li>
    <li>7.0–8.9 → HIGH</li>
    <li>4.0–6.9 → MEDIUM</li>
    <li>0.1–3.9 → LOW</li>
    <li>informational → INFO</li>
    <li>noise/telemetry → TRACE</li>
  </ul>
</div>
`;
    box.appendChild(d3);

    // 4) ISO 27001 mapping skeleton
    const d4=document.createElement("details");
    d4.innerHTML = `
<summary>ISO 27001 mapping (skeleton)</summary>
<div class="p">
  Mapping dùng để chứng minh tuân thủ: findings → control family. Tối thiểu nên map:
  <ul>
    <li>Secrets / key management → A.5 / A.8 (tuỳ phiên bản control set)</li>
    <li>Vuln management / patching → A.8</li>
    <li>Secure development / SDLC controls → A.8</li>
    <li>Access control issues → A.5</li>
    <li>Logging/monitoring gaps → A.8</li>
  </ul>
  (Tuỳ bộ ISO 27001:2022 control list nội bộ của bạn, mình sẽ “đóng khung mapping” chuẩn theo danh mục control của công ty.)
</div>
`;
    box.appendChild(d4);

    // insert after titlebar if possible
    const tb=document.getElementById("vsp_p474_titlebar");
    if(tb && tb.parentNode) tb.parentNode.insertBefore(box, tb.nextSibling);
    else root.insertBefore(box, root.firstChild);

    console && console.log && console.log("[P480] settings CIO docs mounted");
  }

  function boot(){
    // mount a bit later (settings page sometimes renders async)
    setTimeout(mountDocs, 250);
    setTimeout(mountDocs, 900);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
