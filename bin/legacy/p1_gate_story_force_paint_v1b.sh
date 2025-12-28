#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need ss; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_force_paint_${TS}"
echo "[BACKUP] ${JS}.bak_force_paint_${TS}"

cat > "$JS" <<'JS'
/* VSP_P1_GATE_STORY_FORCE_PAINT_V1B */
(() => {
  // NOTE: do NOT early-return even if previous version set a flag;
  // we want "self-healing" behavior on blank pages.
  if (window.__vsp_gate_story_force_paint_v1b) return;
  window.__vsp_gate_story_force_paint_v1b = true;

  const CFG = {
    runsUrl: "/api/vsp/runs?limit=1",
    fileUrl: (rid) => `/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`,
    timeoutMs: 8000,
    tools: ["bandit","semgrep","gitleaks","kics","trivy","syft","grype","codeql"],
    refreshMs: 15000,      // refresh data
    healEveryMs: 600,      // re-insert panel if removed
    healMaxMs: 20000,      // keep healing for 20s after load
  };

  const now = () => Date.now();
  const log = (...a) => console.log("[GateStoryV1B]", ...a);

  function esc(s){
    return String(s ?? "")
      .replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;")
      .replaceAll('"',"&quot;").replaceAll("'","&#39;");
  }

  function pick(obj, path, defv){
    try{
      const ps = path.split(".");
      let cur = obj;
      for (const k of ps){
        if (!cur) return defv;
        cur = cur[k];
      }
      return (cur === undefined || cur === null) ? defv : cur;
    } catch { return defv; }
  }

  function normOverall(v){
    const s = String(v ?? "").toUpperCase().trim();
    if (["RED","FAIL","FAILED","BLOCK","BLOCKED","CRITICAL"].includes(s)) return "RED";
    if (["AMBER","WARN","WARNING","DEGRADED","YELLOW"].includes(s)) return "AMBER";
    if (["GREEN","PASS","PASSED","OK"].includes(s)) return "GREEN";
    return s || "UNKNOWN";
  }

  function tone(overall){
    if (overall === "RED") return "tone-red";
    if (overall === "AMBER") return "tone-amber";
    if (overall === "GREEN") return "tone-green";
    return "tone-unk";
  }

  function toolTone(st){
    const s = String(st ?? "").toUpperCase();
    if (["PASS","OK","GREEN"].includes(s)) return "t-ok";
    if (["FAIL","RED","BLOCKED"].includes(s)) return "t-bad";
    if (["DEGRADED","AMBER","WARN","TIMEOUT"].includes(s)) return "t-warn";
    if (["MISSING","SKIP","SKIPPED","N/A","NA"].includes(s)) return "t-mute";
    return "t-unk";
  }

  function ensureStyle(){
    if (document.getElementById("vsp_gate_story_v1b_style")) return;
    const st = document.createElement("style");
    st.id = "vsp_gate_story_v1b_style";
    st.textContent = `
      body{ background:#0b1220; }
      .vspgs-wrap{ margin:14px; }
      .vspgs-card{
        border:1px solid rgba(255,255,255,.10);
        background: linear-gradient(180deg, rgba(255,255,255,.06), rgba(255,255,255,.03));
        border-radius:16px;
        padding:14px;
        box-shadow: 0 14px 34px rgba(0,0,0,.45);
        color: rgba(226,232,240,.96);
        font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
      }
      .vspgs-top{display:flex; justify-content:space-between; gap:12px; flex-wrap:wrap; align-items:flex-start;}
      .vspgs-title{display:flex; gap:10px; align-items:flex-start;}
      .vspgs-dot{width:10px;height:10px;border-radius:50%;background:rgba(255,255,255,.25);margin-top:4px;}
      .vspgs-h{font-weight:800; letter-spacing:.3px; font-size:14px;}
      .vspgs-sub{font-size:12px; opacity:.74; margin-top:2px;}
      .vspgs-kpis{display:flex; gap:10px; flex-wrap:wrap; justify-content:flex-end;}
      .pill{border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.22); border-radius:999px; padding:6px 10px; font-size:12px; display:flex; gap:8px; align-items:center;}
      .ov{font-weight:900; letter-spacing:1px; padding:6px 12px; border-radius:999px; border:1px solid rgba(255,255,255,.16);}
      .tone-red{background: rgba(255,73,73,.16); color: rgba(255,165,165,.98);}
      .tone-amber{background: rgba(255,193,7,.14); color: rgba(255,228,141,.98);}
      .tone-green{background: rgba(46,204,113,.12); color: rgba(165,255,205,.98);}
      .tone-unk{background: rgba(148,163,184,.12); color: rgba(226,232,240,.95);}
      .mid{display:flex; gap:14px; margin-top:10px; flex-wrap:wrap;}
      .left{flex:1 1 460px; min-width:320px;}
      .right{flex:0 0 360px; min-width:320px;}
      .muted{opacity:.72;}
      .small{font-size:12px; opacity:.82; line-height:1.25rem;}
      .reasons{margin:8px 0 0 0; padding:0 0 0 18px;}
      .reasons li{margin:6px 0; font-size:13px; line-height:1.25rem;}
      .strip{display:flex; gap:8px; flex-wrap:wrap; margin-top:10px;}
      .tool{font-size:11px; padding:6px 8px; border-radius:10px; border:1px solid rgba(255,255,255,.10); background:rgba(0,0,0,.22); display:flex; gap:6px; align-items:center;}
      .tool b{letter-spacing:.3px;}
      .t-ok{color: rgba(165,255,205,.98);}
      .t-warn{color: rgba(255,228,141,.98);}
      .t-bad{color: rgba(255,165,165,.98);}
      .t-mute{color: rgba(203,213,225,.72);}
      .t-unk{color: rgba(226,232,240,.92);}
      .actions{display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; margin-top:10px;}
      .btn{cursor:pointer; border:1px solid rgba(255,255,255,.16); background: rgba(0,0,0,.22); color: rgba(226,232,240,.95);
           border-radius:12px; padding:8px 10px; font-size:12px; text-decoration:none;}
      .btn:hover{background: rgba(255,255,255,.06);}
      .hr{height:1px; background: rgba(255,255,255,.08); margin-top:10px;}
    `;
    document.head.appendChild(st);
  }

  function ensurePanel(){
    ensureStyle();
    let wrap = document.getElementById("vsp_gate_story_panel_v1b");
    if (wrap) return wrap;

    wrap = document.createElement("div");
    wrap.id = "vsp_gate_story_panel_v1b";
    wrap.className = "vspgs-wrap";
    wrap.innerHTML = `
      <div class="vspgs-card">
        <div class="vspgs-top">
          <div class="vspgs-title">
            <div class="vspgs-dot"></div>
            <div>
              <div class="vspgs-h">Gate Story</div>
              <div class="vspgs-sub muted">overall + top reasons + degraded/tools (latest)</div>
            </div>
          </div>
          <div class="vspgs-kpis">
            <div class="pill"><span class="muted">Overall</span> <span id="gs_overall" class="ov tone-unk">…</span></div>
            <div class="pill"><span class="muted">Degraded</span> <b id="gs_degraded">…</b></div>
            <div class="pill"><span class="muted">Total</span> <b id="gs_total">…</b></div>
          </div>
        </div>

        <div class="mid">
          <div class="left">
            <div class="small muted">Top reasons (3)</div>
            <ol class="reasons" id="gs_reasons"><li class="muted">Loading gate…</li></ol>
            <div class="hr"></div>
            <div class="small muted">Tool strip (8)</div>
            <div class="strip" id="gs_strip"></div>
          </div>
          <div class="right">
            <div class="small muted">Latest run</div>
            <div class="small" id="gs_meta">…</div>
            <div class="actions" id="gs_actions"></div>
          </div>
        </div>
      </div>
    `;

    // Force insert at body top even if other scripts wipe containers
    if (document.body.firstChild) document.body.insertBefore(wrap, document.body.firstChild);
    else document.body.appendChild(wrap);

    return wrap;
  }

  function setOverall(v){
    const el = document.getElementById("gs_overall");
    if (!el) return;
    const o = normOverall(v);
    el.textContent = o;
    el.classList.remove("tone-red","tone-amber","tone-green","tone-unk");
    el.classList.add(tone(o));
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if (el) el.textContent = String(v ?? "");
  }

  function renderStrip(toolState){
    const box = document.getElementById("gs_strip");
    if (!box) return;
    box.innerHTML = "";
    for (const t of CFG.tools){
      const st = String(toolState[t] ?? "UNKNOWN").toUpperCase();
      const chip = document.createElement("div");
      chip.className = `tool ${toolTone(st)}`;
      chip.innerHTML = `<b>${esc(t.toUpperCase())}</b><span class="muted">•</span><span>${esc(st)}</span>`;
      box.appendChild(chip);
    }
  }

  function renderReasons(arr){
    const ol = document.getElementById("gs_reasons");
    if (!ol) return;
    const rs = (arr && arr.length) ? arr.slice(0,3) : ["No reasons available (fallback)."];
    ol.innerHTML = rs.map(x => `<li>${esc(x)}</li>`).join("");
  }

  function renderMeta(rid, run, sevText){
    const el = document.getElementById("gs_meta");
    if (!el) return;
    const started = (run && (run.started_at || run.created_at || run.ts || run.time)) || "";
    const ro = normOverall((run && (run.overall || run.overall_status || run.status || run.verdict)) || "");
    el.innerHTML =
      `<div><b>RID</b>: <span class="muted">${esc(rid)}</span></div>` +
      (started ? `<div><b>Time</b>: <span class="muted">${esc(started)}</span></div>` : "") +
      `<div><b>Run overall</b>: <span class="muted">${esc(ro || "UNKNOWN")}</span></div>` +
      (sevText ? `<div><b>Sev</b>: <span class="muted">${esc(sevText)}</span></div>` : "");
  }

  function renderActions(rid){
    const box = document.getElementById("gs_actions");
    if (!box) return;
    const url = CFG.fileUrl(rid);
    box.innerHTML = `
      <a class="btn" href="${esc(url)}" target="_blank" rel="noopener">Open run_gate_summary.json</a>
      <a class="btn" href="/runs" target="_blank" rel="noopener">Runs &amp; Reports</a>
      <a class="btn" href="/data_source" target="_blank" rel="noopener">Data Source</a>
    `;
  }

  async function fetchJson(url){
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), CFG.timeoutMs);
    try{
      const r = await fetch(url, {signal: ac.signal, headers: {"Accept":"application/json"}});
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return await r.json();
    } finally { clearTimeout(t); }
  }

  function normalizeTools(summary){
    const byTool = summary.by_tool || summary.tools || summary.tool_results || {};
    const toolState = {};
    let degradedCount = 0;

    for (const t of CFG.tools){
      let ent = byTool[t] || byTool[t.toUpperCase()] || byTool[t.toLowerCase()];
      let st = "UNKNOWN";
      let dg = false;

      if (ent && typeof ent === "object"){
        st = String(ent.status || ent.state || ent.verdict || ent.result || "UNKNOWN").toUpperCase();
        dg = !!(ent.degraded || ent.is_degraded || ent.timeout || ent.timed_out);
        if (dg && (st === "PASS" || st === "OK" || st === "GREEN")) st = "DEGRADED";
      } else {
        // fallback flat fields
        const st2 = summary[`${t}_status`];
        const dg2 = summary[`${t}_degraded`];
        if (st2) st = String(st2).toUpperCase();
        if (dg2 !== undefined) dg = !!dg2;
        if (dg && (st === "PASS" || st === "OK")) st = "DEGRADED";
      }

      toolState[t] = st;
      if (dg) degradedCount++;
    }
    return {toolState, degradedCount};
  }

  function extractTotals(summary){
    const sev = summary.counts_by_severity || summary.severity_counts || summary.by_severity || null;
    if (sev && typeof sev === "object"){
      const c = Number(sev.CRITICAL ?? sev.critical ?? 0) || 0;
      const h = Number(sev.HIGH ?? sev.high ?? 0) || 0;
      const m = Number(sev.MEDIUM ?? sev.medium ?? 0) || 0;
      const l = Number(sev.LOW ?? sev.low ?? 0) || 0;
      const i = Number(sev.INFO ?? sev.info ?? 0) || 0;
      const t = Number(sev.TRACE ?? sev.trace ?? 0) || 0;
      const total = Number(summary.total_findings ?? summary.findings_total ?? (c+h+m+l+i+t)) || (c+h+m+l+i+t);
      return { total, sevText: `C/H/M/L/I/T = ${c}/${h}/${m}/${l}/${i}/${t}` };
    }
    // best-effort
    const total = Number(summary.total_findings ?? summary.findings_total ?? summary.total ?? 0) || 0;
    return total ? { total, sevText: "" } : null;
  }

  function extractReasons(summary, rid, degradedCount, totals){
    let rs = summary.top_reasons || summary.reasons || summary.why || summary.verdict_reasons || [];
    if (typeof rs === "string") rs = rs.split("\n").map(x=>x.trim()).filter(Boolean);
    if (Array.isArray(rs)) rs = rs.map(x => typeof x === "string" ? x : (x && x.text ? x.text : JSON.stringify(x)));

    rs = (rs || []).filter(Boolean).slice(0,3);
    if (rs.length < 3){
      if (totals && totals.total) rs.push(`Tổng findings: ${totals.total}.`);
      if (degradedCount > 0) rs.push(`Degraded tools: ${degradedCount}/${CFG.tools.length}.`);
      rs.push(`RID: ${rid}.`);
      rs = rs.slice(0,3);
    }
    return rs;
  }

  async function refreshOnce(){
    ensurePanel();

    const runs = await fetchJson(CFG.runsUrl);
    const run = (runs && Array.isArray(runs.items) && runs.items[0]) ? runs.items[0] : null;
    const rid = (run && (run.run_id || run.rid || run.id)) || null;

    if (!rid){
      setOverall("UNKNOWN");
      renderReasons(["Không lấy được RID từ /api/vsp/runs?limit=1."]);
      renderStrip(Object.fromEntries(CFG.tools.map(t=>[t,"UNKNOWN"])));
      setText("gs_degraded", `0/${CFG.tools.length}`);
      setText("gs_total", "—");
      return;
    }

    let summary = null;
    try { summary = await fetchJson(CFG.fileUrl(rid)); } catch { summary = null; }

    const overall = normOverall(
      (summary && (summary.overall || summary.overall_status || summary.status || summary.verdict)) ||
      (run && (run.overall || run.overall_status || run.status || run.verdict)) ||
      "UNKNOWN"
    );
    setOverall(overall);

    const totals = summary ? extractTotals(summary) : null;
    setText("gs_total", totals ? String(totals.total) : "—");

    const {toolState, degradedCount} = summary ? normalizeTools(summary) : {toolState: Object.fromEntries(CFG.tools.map(t=>[t,"UNKNOWN"])), degradedCount: 0};
    setText("gs_degraded", `${degradedCount}/${CFG.tools.length}`);
    renderStrip(toolState);

    const reasons = summary ? extractReasons(summary, rid, degradedCount, totals) : [
      "Không đọc được reports/run_gate_summary.json (fallback).",
      `Degraded tools: ${degradedCount}/${CFG.tools.length}.`,
      `RID: ${rid}.`,
    ];
    renderReasons(reasons);

    renderMeta(rid, run || {}, totals ? totals.sevText : "");
    renderActions(rid);
  }

  function start(){
    // Always paint immediately so page is not blank
    ensurePanel();
    setOverall("UNKNOWN");
    renderStrip(Object.fromEntries(CFG.tools.map(t=>[t,"…"])));
    renderReasons(["Loading…"]);

    // Data refresh
    refreshOnce().catch(e => {
      log("refresh error:", e?.message || e);
      renderReasons([`Lỗi tải gate: ${String(e?.message || e).slice(0,120)}`]);
    });

    // Heal loop: if any legacy script wipes DOM, reinsert panel
    const t0 = now();
    const heal = setInterval(() => {
      if (now() - t0 > CFG.healMaxMs) { clearInterval(heal); return; }
      if (!document.getElementById("vsp_gate_story_panel_v1b")) {
        log("heal: panel missing -> reinsert");
        ensurePanel();
      }
    }, CFG.healEveryMs);

    // Periodic refresh
    setInterval(() => refreshOnce().catch(()=>{}), CFG.refreshMs);

    log("loaded + running");
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, {once:true});
  else start();
})();
JS

echo "[OK] wrote force-paint JS: $JS"

# restart clean :8910 (reuse your standard)
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE js size =="
curl -fsS "$BASE/static/js/vsp_dashboard_gate_story_v1.js" | wc -c
echo "== PROBE include =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 3 || true
echo "[DONE] Gate Story force-paint v1b applied."
