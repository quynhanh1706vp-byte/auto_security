#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_commercial_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2rid_${TS}"
echo "[BACKUP] ${JS}.bak_p2rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_GLOBAL_RID_PICKER_PIN_COPY_V1B"
if MARK in s:
  print("[SKIP] already installed")
  raise SystemExit(0)

tmpl = r"""
/* ===================== __MARK__ ===================== */
(()=> {
  if (window.__vsp_p2_global_rid_picker_v1b) return;
  window.__vsp_p2_global_rid_picker_v1b = true;

  const LS_PIN = "vsp.rid.pin";
  const LS_FOLLOW = "vsp_follow_latest";

  function followOn(){
    try { return (localStorage.getItem(LS_FOLLOW) ?? "on") !== "off"; }
    catch(e) { return true; }
  }
  function setFollow(on){
    try { localStorage.setItem(LS_FOLLOW, on ? "on" : "off"); } catch(e) {}
    try { window.dispatchEvent(new CustomEvent("vsp:follow_latest_changed", {detail:{value:on?"on":"off"}})); } catch(e) {}
  }

  async function jget(u){
    const r = await fetch(u, {credentials:"same-origin"});
    if (!r.ok) throw new Error("HTTP "+r.status);
    return await r.json();
  }

  async function getLatestRid(){
    try {
      const j = await jget("/api/vsp/rid_latest_gate_root");
      if (j && j.ok && j.rid) return j.rid;
    } catch(e) {}
    return null;
  }

  // Auto-discover: try multiple endpoints that might return run list
  async function getRunsList(){
    const cands = [
      "/api/vsp/runs",
      "/api/vsp/runs_v1",
      "/api/vsp/runs_index",
      "/api/vsp/runs_index_v1",
      "/api/vsp/run_history",
      "/api/vsp/run_history_v1",
      "/api/vsp/runs_reports",
      "/api/vsp/runs_reports_v1",
      "/api/vsp/run_status_v1",
      "/api/vsp/recent_runs",
      "/api/vsp/recent_runs_v1"
    ];
    for (const u of cands){
      try {
        const j = await jget(u);
        let arr = null;
        if (Array.isArray(j)) arr = j;
        else if (j && Array.isArray(j.runs)) arr = j.runs;
        else if (j && Array.isArray(j.items)) arr = j.items;
        else if (j && Array.isArray(j.data)) arr = j.data;
        if (!arr || !arr.length) continue;

        const out = [];
        for (const it of arr){
          if (!it) continue;
          const rid = it.rid || it.run_id || it.id || it.name || it.RUN_ID || it.RID;
          if (!rid || typeof rid !== "string") continue;
          const mt = it.mtime || it.modified || it.updated_at || it.ts || it.time || it.date || null;
          out.push({rid, mtime: mt});
        }
        if (out.length) return out;
      } catch(e) {}
    }
    return [];
  }

  function fmtTime(t){
    if (!t) return "";
    try {
      if (typeof t === "number") {
        const d = new Date(t > 1e12 ? t : (t*1000));
        return d.toISOString().replace("T"," ").slice(0,19);
      }
      if (typeof t === "string") {
        return t.length > 24 ? t.slice(0,24) : t;
      }
    } catch(e) {}
    return "";
  }

  function mount(){
    if (document.getElementById("vsp_rid_picker_v1b")) return;

    const host =
      document.querySelector("header") ||
      document.querySelector(".topbar") ||
      document.querySelector("#topbar") ||
      document.body;

    const wrap = document.createElement("div");
    wrap.id = "vsp_rid_picker_v1b";
    wrap.style.cssText = "display:flex;align-items:center;gap:8px;margin-left:auto";

    const fixed = (host === document.body);
    if (fixed){
      wrap.style.cssText = "position:fixed;z-index:99997;top:10px;right:150px;display:flex;align-items:center;gap:8px;background:rgba(10,18,32,.82);border:1px solid rgba(255,255,255,.10);backdrop-filter: blur(10px);padding:8px 10px;border-radius:12px;font:12px/1.2 system-ui,Segoe UI,Roboto;color:#cfe3ff;box-shadow:0 10px 30px rgba(0,0,0,.35)";
    }

    wrap.innerHTML = `
      <span style="opacity:.9;font-weight:700">RID</span>
      <select id="vsp_rid_sel_v1b" style="max-width:300px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);color:#d8ecff;border-radius:10px;padding:6px 10px;outline:none"></select>
      <button id="vsp_rid_pin_v1b" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(80,60,20,.35);color:#ffe7b7;cursor:pointer">Pin</button>
      <button id="vsp_rid_copy_v1b" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(30,60,110,.35);color:#d8ecff;cursor:pointer">Copy</button>
    `;

    if (!fixed) host.appendChild(wrap);
    else document.body.appendChild(wrap);

    const sel = document.getElementById("vsp_rid_sel_v1b");
    const btnPin = document.getElementById("vsp_rid_pin_v1b");
    const btnCopy = document.getElementById("vsp_rid_copy_v1b");

    function getPinned(){ try { return localStorage.getItem(LS_PIN); } catch(e) { return null; } }
    function setPinned(rid){ try { localStorage.setItem(LS_PIN, rid); } catch(e) {} }
    function clearPinned(){ try { localStorage.removeItem(LS_PIN); } catch(e) {} }

    function setPinBtn(){
      const pin = getPinned();
      btnPin.textContent = pin ? "Unpin" : "Pin";
      btnPin.style.background = pin ? "rgba(20,80,40,.35)" : "rgba(80,60,20,.35)";
      btnPin.style.color = pin ? "#c9ffe0" : "#ffe7b7";
    }

    async function populate(){
      const pin = getPinned();
      const latest = await getLatestRid();

      const opts = [];
      if (latest) opts.push({rid: latest, label: "Latest • " + latest});
      if (pin && (!latest || pin !== latest)) opts.push({rid: pin, label: "Pinned • " + pin});

      const runs = await getRunsList();
      const seen = new Set(opts.map(o=>o.rid));
      for (const it of runs){
        if (!it || !it.rid) continue;
        if (seen.has(it.rid)) continue;
        seen.add(it.rid);
        const t = fmtTime(it.mtime);
        opts.push({rid: it.rid, label: t ? (it.rid + " • " + t) : it.rid});
        if (opts.length >= 22) break;
      }

      sel.innerHTML = "";
      for (const o of opts){
        const op = document.createElement("option");
        op.value = o.rid;
        op.textContent = o.label;
        sel.appendChild(op);
      }

      const cur = (followOn() && latest) ? latest : (pin || latest || (opts[0]?.rid||""));
      if (cur) sel.value = cur;
      setPinBtn();
    }

    function dispatchRid(rid){
      try {
        const prev = window.__vsp_rid_latest || window.__vsp_rid_prev || null;
        window.__vsp_rid_prev = prev;
        window.__vsp_rid_latest = rid;
        window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid, prev}}));
      } catch(e) {}
    }

    sel.addEventListener("change", ()=> {
      const rid = sel.value;
      if (!rid) return;
      setFollow(false); // manual select => follow OFF
      dispatchRid(rid);
    });

    btnPin.addEventListener("click", async ()=> {
      const pin = getPinned();
      if (pin){
        clearPinned();
        setFollow(true);
        const latest = await getLatestRid();
        if (latest) dispatchRid(latest);
      } else {
        const rid = sel.value || await getLatestRid();
        if (!rid) return;
        setPinned(rid);
        setFollow(false);
        dispatchRid(rid);
      }
      await populate();
    });

    btnCopy.addEventListener("click", async ()=> {
      const rid = sel.value || getPinned() || await getLatestRid();
      if (!rid) return;
      try {
        await navigator.clipboard.writeText(rid);
      } catch(e) {
        const ta = document.createElement("textarea");
        ta.value = rid;
        ta.style.cssText="position:fixed;left:-10000px;top:-10000px";
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); } catch(_e) {}
        ta.remove();
      }
    });

    window.addEventListener("vsp:follow_latest_changed", ()=> { populate().catch(()=>{}); });
    populate().catch(()=>{});
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
/* ===================== /__MARK__ ===================== */
"""

addon = textwrap.dedent(tmpl).replace("__MARK__", MARK)
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P2 global rid picker v1b")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] P2 global RID picker v1b applied"
