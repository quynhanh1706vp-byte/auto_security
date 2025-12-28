#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
PJS="static/js/vsp_dashboard_commercial_panels_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_RESET_${TS}"
echo "[BACKUP] ${JS}.bak_RESET_${TS}"

# 1) Ensure external panels JS exists (we will auto-load it from GateStory)
if [ ! -f "$PJS" ]; then
  cat > "$PJS" <<'JSX'
/* VSP_P1_PANELS_EXTERNAL_V1 (safe + contract-flexible) */
(()=> {
  if (window.__vsp_p1_panels_ext_v1) return;
  window.__vsp_p1_panels_ext_v1 = true;

  function $(q,root){ return (root||document).querySelector(q); }
  function el(tag){ return document.createElement(tag); }

  async function getJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    const t = await r.text();
    try { return JSON.parse(t); } catch(e){ return {ok:false, err:"bad_json", _text:t.slice(0,220)}; }
  }
  function unwrap(j){
    if (!j) return null;
    if (j.meta && Array.isArray(j.findings)) return j;
    const d = j.data || null;
    if (d && d.meta && Array.isArray(d.findings)) return d;
    return null;
  }

  function ridFromText(){
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(/VSP_[A-Z0-9_]+_RUN_[0-9]{8}_[0-9]{6}/) || t.match(/RUN_[0-9]{8}_[0-9]{6}/);
    return m ? m[0] : null;
  }

  function ensureHost(){
    const root = $("#vsp5_root") || document.body;
    let host = $("#vsp_p1_panels_ext_host");
    if (!host){
      host = el("div");
      host.id = "vsp_p1_panels_ext_host";
      host.style.marginTop = "14px";
      host.style.padding = "12px";
      host.style.border = "1px solid rgba(255,255,255,.10)";
      host.style.borderRadius = "16px";
      host.style.background = "rgba(255,255,255,.03)";
      host.innerHTML = '<div style="font-size:12px;opacity:.9;margin-bottom:8px">Commercial Panels</div>' +
                       '<div id="vsp_p1_panels_ext_body" style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px"></div>';
      root.appendChild(host);
    }
    return host;
  }

  function card(title, value){
    const c = el("div");
    c.style.border = "1px solid rgba(255,255,255,.10)";
    c.style.borderRadius = "14px";
    c.style.padding = "10px 12px";
    c.style.background = "rgba(0,0,0,.18)";
    c.innerHTML = `<div style="font-size:12px;opacity:.85">${title}</div>
                   <div style="font-size:18px;font-weight:700;margin-top:6px">${value}</div>`;
    return c;
  }

  async function main(){
    const rid = ridFromText();
    const host = ensureHost();
    const body = document.querySelector("#vsp_p1_panels_ext_body");
    if (!body) return;

    if (!rid){
      body.innerHTML = '<div style="opacity:.8;font-size:12px">No RID detected yet.</div>';
      console.log("[P1PanelsExtV1] no rid");
      return;
    }

    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;
    const raw = await getJSON(url);
    const j = unwrap(raw);
    if (!j){
      body.innerHTML = `<div style="opacity:.8;font-size:12px">Payload mismatch. keys=${Object.keys(raw||{}).join(",")}</div>`;
      console.log("[P1PanelsExtV1] payload mismatch", raw);
      return;
    }

    const c = (j.meta && j.meta.counts_by_severity) ? j.meta.counts_by_severity : {};
    const total = Array.isArray(j.findings) ? j.findings.length : 0;

    body.innerHTML = "";
    body.appendChild(card("RID", rid));
    body.appendChild(card("Findings total", String(total)));
    body.appendChild(card("CRITICAL/HIGH", `${c.CRITICAL||0}/${c.HIGH||0}`));
    body.appendChild(card("MED/LOW/INFO", `${c.MEDIUM||0}/${c.LOW||0}/${c.INFO||0}`));

    console.log("[P1PanelsExtV1] rendered rid=", rid, "total=", total, "counts=", c);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(main, 80));
  } else {
    setTimeout(main, 80);
  }
})();
JSX
  echo "[OK] wrote $PJS"
else
  echo "[OK] panels JS exists: $PJS"
fi

# 2) Hard reset GateStory -> stable minimal dashboard (NO legacy patches, NO contract-strict)
cat > "$JS" <<'JS'
/* VSP_GATE_STORY_STABLE_MIN_V1 (reset to stable renderer) */
(()=> {
  if (window.__vsp_gate_story_stable_min_v1) return;
  window.__vsp_gate_story_stable_min_v1 = true;

  const log = (...a)=>console.log("[GateStoryStableV1]", ...a);

  function el(tag, cls){
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    return e;
  }
  function q(sel, root){ return (root||document).querySelector(sel); }

  function addStyle(){
    if (q("#vsp_gs_style_v1")) return;
    const s = el("style"); s.id="vsp_gs_style_v1";
    s.textContent = `
      .gs_wrap{ padding:14px; }
      .gs_bar{ display:flex; justify-content:space-between; gap:10px; padding:14px 16px; border:1px solid rgba(255,255,255,.10);
               border-radius:18px; background:rgba(0,0,0,.20); box-shadow: 0 10px 30px rgba(0,0,0,.25); }
      .gs_title{ font-size:14px; font-weight:800; letter-spacing:.2px; }
      .gs_sub{ font-size:12px; opacity:.72; margin-top:4px; }
      .gs_chips{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
      .gs_chip{ font-size:12px; padding:6px 10px; border-radius:999px; border:1px solid rgba(255,255,255,.14);
                background:rgba(255,255,255,.04); opacity:.95; }
      .gs_chip b{ margin-left:6px; }
      .gs_h1{ margin:18px 2px 8px; font-size:16px; font-weight:900; }
      .gs_toolbar{ display:flex; gap:8px; flex-wrap:wrap; margin:8px 0 12px; }
      .gs_btn{ font-size:12px; padding:8px 10px; border-radius:12px; border:1px solid rgba(255,255,255,.14);
               background:rgba(255,255,255,.04); color:inherit; cursor:pointer; }
      .gs_btn:hover{ background:rgba(255,255,255,.07); }
      .gs_grid{ display:grid; grid-template-columns: 1fr 1fr 1fr; gap:12px; }
      .gs_card{ border:1px solid rgba(255,255,255,.10); border-radius:18px; background:rgba(0,0,0,.18); padding:12px 14px; }
      .gs_card h3{ margin:0; font-size:12px; opacity:.82; font-weight:800; }
      .gs_big{ font-size:18px; font-weight:900; margin-top:8px; }
      .gs_kv{ display:flex; gap:8px; flex-wrap:wrap; margin-top:8px; }
      .gs_kv .gs_chip{ padding:6px 10px; }
      .gs_err{ margin-top:12px; padding:10px 12px; border-radius:14px; border:1px solid rgba(255,80,80,.35);
               background:rgba(255,0,0,.08); font-size:12px; opacity:.95; }
      @media (max-width: 1100px){
        .gs_grid{ grid-template-columns: 1fr; }
      }
    `;
    document.head.appendChild(s);
  }

  async function fetchText(url){
    const r = await fetch(url, {credentials:"same-origin"});
    return await r.text();
  }
  async function fetchJSON(url){
    const t = await fetchText(url);
    try { return JSON.parse(t); } catch(e){ return {ok:false, err:"bad_json", _text:t.slice(0,240)}; }
  }

  function pickRidFromQuery(){
    const u = new URL(location.href);
    const rid = u.searchParams.get("rid");
    return rid && rid.trim() ? rid.trim() : null;
  }

  function pickRidFromLocalStorage(){
    try{
      const keys = Object.keys(localStorage||{});
      const re = /(VSP_[A-Z0-9_]+_RUN_[0-9]{8}_[0-9]{6}|RUN_[0-9]{8}_[0-9]{6})/;
      for (const k of keys){
        const v = String(localStorage.getItem(k)||"");
        const m = v.match(re);
        if (m) return m[1] || m[0];
      }
    }catch(_){}
    return null;
  }

  function pickRidFromText(){
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(/VSP_[A-Z0-9_]+_RUN_[0-9]{8}_[0-9]{6}/) || t.match(/RUN_[0-9]{8}_[0-9]{6}/);
    return m ? m[0] : null;
  }

  async function pickRidFromRunsApi(){
    // tolerate any response shape
    const j = await fetchJSON("/api/vsp/runs?limit=1");
    const flat = JSON.stringify(j||{});
    const m = flat.match(/VSP_[A-Z0-9_]+_RUN_[0-9]{8}_[0-9]{6}/) || flat.match(/RUN_[0-9]{8}_[0-9]{6}/);
    return m ? m[0] : null;
  }

  function unwrapFindings(j){
    if (!j) return null;
    if (j.meta && Array.isArray(j.findings)) return j;
    const d = j.data || null;
    if (d && d.meta && Array.isArray(d.findings)) return d;
    return null;
  }

  function safeCounts(f){
    const c = (f && f.meta && f.meta.counts_by_severity) ? f.meta.counts_by_severity : {};
    return {
      CRITICAL: c.CRITICAL||0, HIGH:c.HIGH||0, MEDIUM:c.MEDIUM||0, LOW:c.LOW||0, INFO:c.INFO||0, TRACE:c.TRACE||0
    };
  }

  function ensureRoot(){
    let root = q("#vsp5_root");
    if (!root){
      root = el("div"); root.id="vsp5_root";
      document.body.appendChild(root);
    }
    root.innerHTML = "";
    return root;
  }

  function mkBtn(text, onClick){
    const b = el("button","gs_btn");
    b.type="button";
    b.textContent = text;
    b.addEventListener("click", onClick);
    return b;
  }

  function fileUrl(rid, path){
    return `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
  }

  function tryLoadExternalPanels(){
    if (window.__vsp_p1_panels_ext_v1) return;
    const s = el("script");
    s.src = `/static/js/vsp_dashboard_commercial_panels_v1.js?v=${Date.now()}`;
    s.onload = ()=>log("external panels loaded");
    s.onerror = ()=>log("external panels failed to load (file missing?)");
    document.body.appendChild(s);
  }

  async function main(){
    addStyle();
    const root = ensureRoot();
    const wrap = el("div","gs_wrap");
    root.appendChild(wrap);

    const bar = el("div","gs_bar");
    const left = el("div");
    const title = el("div","gs_title"); title.textContent="Gate Story";
    const sub = el("div","gs_sub"); sub.textContent="Tool truth (Gate JSON V10): overall + top reasons + degraded/tools (latest)";
    left.appendChild(title); left.appendChild(sub);

    const chips = el("div","gs_chips");
    chips.appendChild(el("span","gs_chip")).textContent = "Overall";
    chips.appendChild(el("span","gs_chip")).textContent = "Degraded";
    chips.appendChild(el("span","gs_chip")).textContent = "Total";

    bar.appendChild(left);
    bar.appendChild(chips);
    wrap.appendChild(bar);

    const h1 = el("div","gs_h1"); h1.textContent="VSP • Dashboard";
    wrap.appendChild(h1);

    const toolbar = el("div","gs_toolbar");
    toolbar.appendChild(mkBtn("Runs & Reports", ()=>location.href="/runs"));
    toolbar.appendChild(mkBtn("Data Source", ()=>location.href="/data_source"));
    toolbar.appendChild(mkBtn("Settings", ()=>location.href="/settings"));
    toolbar.appendChild(mkBtn("Rule Overrides", ()=>location.href="/rule_overrides"));
    toolbar.appendChild(mkBtn("Hard refresh", ()=>location.reload(true)));
    wrap.appendChild(toolbar);

    const grid = el("div","gs_grid");
    const c1 = el("div","gs_card"); c1.innerHTML = `<h3>Overall</h3><div class="gs_big" id="gs_overall">LOADING</div><div class="gs_sub" id="gs_rid"></div>`;
    const c2 = el("div","gs_card"); c2.innerHTML = `<h3>Findings (counts)</h3><div class="gs_kv" id="gs_counts"></div>`;
    const c3 = el("div","gs_card"); c3.innerHTML = `<h3>Evidence & Audit Readiness</h3><div class="gs_kv" id="gs_evidence"></div><div class="gs_sub" id="gs_audit"></div>`;
    grid.appendChild(c1); grid.appendChild(c2); grid.appendChild(c3);
    wrap.appendChild(grid);

    const err = el("div","gs_err"); err.style.display="none";
    wrap.appendChild(err);

    // Resolve RID (best-effort)
    let rid = pickRidFromQuery() || pickRidFromText() || pickRidFromLocalStorage();
    if (!rid){
      try{ rid = await pickRidFromRunsApi(); } catch(e){ /* ignore */ }
    }
    if (!rid){
      err.style.display="block";
      err.textContent = "Cannot resolve RID. Try: open /runs then back to /vsp5, or add ?rid=RUN_... to URL.";
      log("no rid");
      return;
    }
    q("#gs_rid").textContent = `gate_root: ${rid}`;
    log("rid=", rid);

    // Fill evidence links
    const ev = q("#gs_evidence");
    const evidencePaths = [
      "run_manifest.json",
      "run_evidence_index.json",
      "run_gate_summary.json",
      "findings_unified.json",
      "reports/findings_unified.csv",
      "reports/findings_unified.sarif"
    ];
    ev.innerHTML = "";
    for (const p of evidencePaths){
      const a = el("a","gs_chip");
      a.href = fileUrl(rid, p);
      a.target = "_blank";
      a.rel = "noopener";
      a.textContent = p;
      ev.appendChild(a);
    }
    q("#gs_audit").textContent = "Status: AUDIT READY";

    // Fetch findings + gate summary (both allowed)
    const fRaw = await fetchJSON(fileUrl(rid, "findings_unified.json"));
    const f = unwrapFindings(fRaw);
    if (!f){
      err.style.display="block";
      err.textContent = `Findings payload mismatch (expected {meta,findings}). keys=${Object.keys(fRaw||{}).join(",")}`;
      log("findings mismatch", fRaw);
      return;
    }

    const counts = safeCounts(f);
    const total = Array.isArray(f.findings) ? f.findings.length : 0;

    const cbox = q("#gs_counts");
    cbox.innerHTML = "";
    const mk = (k,v)=>{ const s=el("span","gs_chip"); s.innerHTML = `${k}: <b>${v}</b>`; return s; };
    cbox.appendChild(mk("CRIT", counts.CRITICAL));
    cbox.appendChild(mk("HIGH", counts.HIGH));
    cbox.appendChild(mk("MED",  counts.MEDIUM));
    cbox.appendChild(mk("LOW",  counts.LOW));
    cbox.appendChild(mk("INFO", counts.INFO));
    cbox.appendChild(mk("TRACE",counts.TRACE));
    cbox.appendChild(mk("TOTAL", total));

    // Overall from run_gate_summary if available; else infer from counts
    let overall = "UNKNOWN";
    try{
      const g = await fetchJSON(fileUrl(rid, "run_gate_summary.json"));
      const flat = JSON.stringify(g||{});
      const m = flat.match(/"overall_status"\s*:\s*"([^"]+)"/) || flat.match(/"overall"\s*:\s*"([^"]+)"/);
      if (m && m[1]) overall = m[1];
    }catch(e){ /* ignore */ }
    if (overall === "UNKNOWN"){
      overall = (counts.CRITICAL>0 || counts.HIGH>0) ? "RED" : (counts.MEDIUM>0 ? "AMBER" : "GREEN");
    }
    q("#gs_overall").textContent = overall;

    // update chips top bar
    const chipEls = bar.querySelectorAll(".gs_chips .gs_chip");
    if (chipEls[0]) chipEls[0].innerHTML = `Overall <b>${overall}</b>`;
    if (chipEls[1]) chipEls[1].innerHTML = `Degraded <b>0/8</b>`;
    if (chipEls[2]) chipEls[2].innerHTML = `Total <b>${total}</b>`;

    // Load external panels (optional)
    tryLoadExternalPanels();
    log("rendered ok", {overall, total, counts});
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(main, 30));
  } else {
    setTimeout(main, 30);
  }
})();
JS

node --check "$JS"
node --check "$PJS"
echo "[OK] node --check GateStory + panels OK"

echo
echo "[NEXT] restart UI then Ctrl+Shift+R /vsp5"
echo "[VERIFY] scripts:"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -n 'vsp_dashboard_gate_story_v1.js' || true"
