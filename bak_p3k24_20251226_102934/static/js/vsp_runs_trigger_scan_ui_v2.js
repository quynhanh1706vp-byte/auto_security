(function () {

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_trigger_scan_ui_v2.js", "hash=", location.hash); } catch(_){}
    return;
  }

  if (window.VSP_RUN_SCAN_UI_V2_LOADED) return;
  window.VSP_RUN_SCAN_UI_V2_LOADED = true;

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    attrs = attrs || {};
    Object.keys(attrs).forEach(function (k) {
      if (k === "class") n.className = attrs[k];
      else if (k === "html") n.innerHTML = attrs[k];
      else if (k === "text") n.textContent = attrs[k];
      else n.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) {
      if (c == null) return;
      if (typeof c === "string") n.appendChild(document.createTextNode(c));
      else n.appendChild(c);
    });
    return n;
  }
  function qs(sel, root) { return (root || document).querySelector(sel); }
  function qsa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function installStylesOnce() {
    if (document.getElementById("vsp-runscan-ui-style-v2")) return;
    var css = `
      .vsp-runscan-wrap{margin:16px 0;padding:16px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.03)}
      .vsp-runscan-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}
      .vsp-runscan-title{font-weight:700;font-size:14px;letter-spacing:.3px}
      .vsp-runscan-sub{opacity:.72;font-size:12px;margin-top:4px}
      .vsp-runscan-grid{display:grid;grid-template-columns:repeat(12,1fr);gap:10px}
      .vsp-field{grid-column:span 4;display:flex;flex-direction:column;gap:6px}
      .vsp-field label{font-size:12px;opacity:.8}
      .vsp-field input,.vsp-field select{padding:10px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.25);color:inherit;outline:none}
      .vsp-field input:focus,.vsp-field select:focus{border-color:rgba(99,102,241,.55)}
      .vsp-field.wide{grid-column:span 8}
      .vsp-runscan-actions{grid-column:span 12;display:flex;gap:10px;align-items:center;margin-top:6px}
      .vsp-btn{padding:10px 12px;border-radius:12px;border:1px solid rgba(255,255,255,.10);background:rgba(99,102,241,.18);color:inherit;cursor:pointer;font-weight:650}
      .vsp-btn:hover{background:rgba(99,102,241,.28)}
      .vsp-btn.secondary{background:rgba(255,255,255,.06)}
      .vsp-btn.secondary:hover{background:rgba(255,255,255,.10)}
      .vsp-btn:disabled{opacity:.5;cursor:not-allowed}
      .vsp-hline{height:1px;background:rgba(255,255,255,.08);margin:14px 0}
      .vsp-kv{display:grid;grid-template-columns:140px 1fr;gap:6px 12px;font-size:12px}
      .vsp-kv .k{opacity:.72}
      .vsp-box{padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,.08);background:rgba(0,0,0,.18)}
      .vsp-badge{padding:4px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-size:11px;opacity:.95}
      .vsp-badge-ok{background:rgba(16,185,129,.15);border-color:rgba(16,185,129,.35)}
      .vsp-badge-bad{background:rgba(239,68,68,.15);border-color:rgba(239,68,68,.35)}
      .vsp-badge-info{background:rgba(59,130,246,.15);border-color:rgba(59,130,246,.35)}
      .vsp-badge-warn{background:rgba(245,158,11,.15);border-color:rgba(245,158,11,.35)}
      .vsp-mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
      .vsp-log{white-space:pre-wrap;font-size:11px;line-height:1.45;max-height:220px;overflow:auto}
      @media (max-width: 1100px){ .vsp-field{grid-column:span 6} .vsp-field.wide{grid-column:span 12} }
    `;
    var st = document.createElement("style");
    st.id = "vsp-runscan-ui-style-v2";
    st.textContent = css;
    document.head.appendChild(st);
  }

  function badge(status) {
    var map = {PENDING:"vsp-badge vsp-badge-warn",RUNNING:"vsp-badge vsp-badge-info",DONE:"vsp-badge vsp-badge-ok",FAILED:"vsp-badge vsp-badge-bad",UNKNOWN:"vsp-badge"};
    return el("span", { class: map[status] || "vsp-badge", text: status || "UNKNOWN" });
  }

  async function postJson(url, data) {
    var r = await fetch(url, { method:"POST", headers:{ "Content-Type":"application/json" }, body: JSON.stringify(data) });
    var t = await r.text();
    var j; try { j = JSON.parse(t); } catch(e) { j = { ok:false, error:"Non-JSON response", raw:t }; }
    if (!r.ok) { j.ok=false; j.http_status=r.status; }
    return j;
  }
  async function getJson(url) {
    var r = await fetch(url);
    var t = await r.text();
    var j; try { j = JSON.parse(t); } catch(e) { j = { ok:false, error:"Non-JSON response", raw:t }; }
    if (!r.ok) { j.ok=false; j.http_status=r.status; }
    return j;
  }

  function isVisible(node) {
    if (!node) return false;
    var s = window.getComputedStyle(node);
    if (s.display === "none" || s.visibility === "hidden" || Number(s.opacity) === 0) return false;
    if (node.offsetParent === null && s.position !== "fixed") return false;
    return true;
  }

  function findRunsPaneSmart() {
    // 1) direct known ids
    var direct = document.getElementById("vsp-tab-runs") || document.querySelector("[data-tab='runs']") || document.querySelector("#tab-runs");
    if (direct) return direct;

    // 2) look for active pane by hash/router (common patterns)
    var hash = (location.hash || "").toLowerCase();
    var candidates = qsa("[id*='run'], [class*='run'], [data-tab], section, main, div");
    // Prefer visible nodes whose text hints "Runs" or contains a Runs table header
    var best = null, bestScore = -1;
    for (var i=0;i<candidates.length;i++){
      var n = candidates[i];
      if (!isVisible(n)) continue;
      var id = (n.id || "").toLowerCase();
      var cls = (n.className || "").toLowerCase();
      var txt = (n.textContent || "").toLowerCase();

      var score = 0;
      if (hash.includes("run") || hash.includes("report")) score += 1;
      if (id.includes("run")) score += 3;
      if (cls.includes("run")) score += 2;
      if (txt.includes("runs") || txt.includes("reports")) score += 2;
      if (txt.includes("run id") || txt.includes("export") || txt.includes("report")) score += 1;
      // penalize huge containers (avoid mounting into whole page)
      if (txt.length > 20000) score -= 2;

      if (score > bestScore) { bestScore = score; best = n; }
    }
    return best;
  }

  function ensureMount(pane) {
    var mp = qs("#vsp-runscan-ui-v2", pane);
    if (mp) return mp;
    mp = el("div", { id: "vsp-runscan-ui-v2" });
    pane.insertBefore(mp, pane.firstChild);
    return mp;
  }

  async function poll(reqId, ui) {
    ui.reqId.textContent = reqId;
    ui.status.innerHTML = ""; ui.status.appendChild(badge("RUNNING"));
    var stopped = false;
    ui.stopBtn.disabled = false;
    ui.stopBtn.onclick = function(){ stopped=true; ui.status.innerHTML=""; ui.status.appendChild(badge("UNKNOWN")); ui.note.textContent="Polling stopped."; ui.stopBtn.disabled=true; };

    async function tick(){
      if (stopped) return;
      var j = await getJson("/api/vsp/run_status/" + encodeURIComponent(reqId));
      if (!j || !j.ok){
        ui.note.textContent = "Status API error: " + (j && (j.error || j.raw || j.http_status) || "unknown");
        return setTimeout(tick, 3000);
      }
      ui.status.innerHTML = ""; ui.status.appendChild(badge(j.status));
      ui.ciRunId.textContent = j.ci_run_id || "-";
      ui.hasFindings.textContent = (j.flag && typeof j.flag.has_findings !== "undefined") ? String(j.flag.has_findings) : "-";
      ui.gate.textContent = j.gate || "-";
      ui.finalRc.textContent = (typeof j.final !== "undefined") ? String(j.final) : "-";
      ui.log.textContent = (j.tail || []).join("\n");
      if (j.status === "DONE" || j.status === "FAILED") { ui.note.textContent = "Run finished."; ui.stopBtn.disabled=true; return; }
      setTimeout(tick, 3000);
    }
    tick();
  }

  async function onRun(ui) {
    ui.err.textContent = "";
    ui.note.textContent = "";
    ui.runBtn.disabled = true;

    var payload = { mode: ui.mode.value, profile: ui.profile.value, target_type: "path", target: ui.target.value };
    ui.payload.textContent = JSON.stringify(payload, null, 2);

    try{
      var j = await postJson("/api/vsp/run", payload);
      if (!j || !j.ok) { ui.err.textContent = "Run API failed: " + JSON.stringify(j, null, 2); return; }
      if (!j.request_id) { ui.err.textContent = "No request_id returned: " + JSON.stringify(j, null, 2); return; }
      ui.note.textContent = j.message || "Scan accepted.";
      await poll(j.request_id, ui);
    } finally {
      ui.runBtn.disabled = false;
    }
  }

  function render(pane) {
    installStylesOnce();
    var mount = ensureMount(pane);
    if (mount.dataset.mounted === "1") return;
    mount.dataset.mounted = "1";

    var ui = {};
    ui.mode = el("select", {}, [
      el("option", { value: "local", text: "local (LOCAL_UI)" }),
      el("option", { value: "github_ci", text: "github_ci" }),
      el("option", { value: "jenkins_ci", text: "jenkins_ci" })
    ]);
    ui.profile = el("select", {}, [
      el("option", { value: "FULL_EXT", text: "FULL_EXT" }),
      el("option", { value: "EXT", text: "EXT" })
    ]);
    ui.target = el("input", { value: "/home/test/Data/SECURITY-10-10-v4", spellcheck:"false" });

    ui.runBtn = el("button", { class:"vsp-btn", text:"Run Scan Now" });
    ui.stopBtn = el("button", { class:"vsp-btn secondary", text:"Stop Poll" }); ui.stopBtn.disabled = true;
    ui.status = el("div", {}, [badge("UNKNOWN")]);

    ui.reqId = el("span", { class:"vsp-mono", text:"-" });
    ui.ciRunId = el("span", { class:"vsp-mono", text:"-" });
    ui.hasFindings = el("span", { class:"vsp-mono", text:"-" });
    ui.gate = el("span", { class:"vsp-mono", text:"-" });
    ui.finalRc = el("span", { class:"vsp-mono", text:"-" });

    ui.note = el("div", { style:"margin-top:10px;font-size:12px;opacity:.8" });
    ui.err  = el("div", { style:"margin-top:8px;font-size:12px;color:rgba(239,68,68,.95)" });

    ui.payload = el("div", { class:"vsp-box vsp-mono vsp-log", text:"" });
    ui.log     = el("div", { class:"vsp-box vsp-mono vsp-log", text:"" });

    ui.runBtn.onclick = function(){ onRun(ui); };

    mount.innerHTML = "";
    mount.appendChild(el("div", { class:"vsp-runscan-wrap" }, [
      el("div", { class:"vsp-runscan-head" }, [
        el("div", {}, [
          el("div", { class:"vsp-runscan-title", text:"RUN SCAN NOW" }),
          el("div", { class:"vsp-runscan-sub", text:"Trigger FULL_EXT pipeline and track status (UIREQ → VSP_CI_*)." })
        ]),
        el("div", { style:"display:flex;gap:10px;align-items:center" }, [
          el("div", { class:"vsp-mono", text:"Status:" }),
          ui.status
        ])
      ]),
      el("div", { class:"vsp-runscan-grid" }, [
        el("div", { class:"vsp-field" }, [ el("label",{text:"Mode"}), ui.mode ]),
        el("div", { class:"vsp-field" }, [ el("label",{text:"Profile"}), ui.profile ]),
        el("div", { class:"vsp-field wide" }, [ el("label",{text:"Target path"}), ui.target ]),
        el("div", { class:"vsp-runscan-actions" }, [ ui.runBtn, ui.stopBtn ])
      ]),
      el("div", { class:"vsp-hline" }),
      el("div", { class:"vsp-kv vsp-box" }, [
        el("div",{class:"k",text:"request_id"}), ui.reqId,
        el("div",{class:"k",text:"ci_run_id"}), ui.ciRunId,
        el("div",{class:"k",text:"has_findings"}), ui.hasFindings,
        el("div",{class:"k",text:"gate"}), ui.gate,
        el("div",{class:"k",text:"final_rc"}), ui.finalRc
      ]),
      ui.note, ui.err,
      el("div", { class:"vsp-hline" }),
      el("div", { class:"vsp-runscan-sub", text:"Request payload" }),
      ui.payload,
      el("div", { style:"height:10px" }),
      el("div", { class:"vsp-runscan-sub", text:"Status log tail (from /api/vsp/run_status/<req_id>)" }),
      ui.log
    ]));

    console.log("[VSP_RUNSCAN_UI_V2] mounted into:", pane);
  }

  function bootOnce() {
    var pane = findRunsPaneSmart();
    if (!pane) {
      console.warn("[VSP_RUNSCAN_UI_V2] runs pane not found yet");
      return false;
    }
    render(pane);
    return true;
  }

  // retry + also on hashchange (tab router)
  var tries = 0;
  var iv = setInterval(function(){
    tries++;
    if (bootOnce()) clearInterval(iv);
    if (tries > 80) clearInterval(iv);
  }, 250);

  window.addEventListener("hashchange", function(){ setTimeout(bootOnce, 200); });
})();
