#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep

JS="static/js/vsp_runs_quick_actions_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relcardv2_${TS}"
echo "[BACKUP] ${JS}.bak_relcardv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RELEASE_CARD_RUNS_V2" in s:
    print("[SKIP] release card v2 already present")
    raise SystemExit(0)

prefix = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_RUNS_V2_INTERCEPTOR_V1 =====================
   Goal: stop old noisy release card from spamming /api/vsp/release_latest.json 404 + poller.
   Safe: only intercept that exact endpoint + block intervals whose fn source mentions release_latest/ReleaseCard.
===================================================================================== */
(()=> {
  try {
    if (window.__vsp_relcard_interceptor_v1) return;
    window.__vsp_relcard_interceptor_v1 = true;

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch) {
      window.fetch = async function(resource, init){
        try{
          const url = (typeof resource === 'string') ? resource : (resource && resource.url) ? resource.url : '';
          if (url && url.includes('/api/vsp/release_latest.json')) {
            // prefer static release file (no backend dependency)
            try {
              const r = await _fetch('/out_ci/releases/release_latest.json', init);
              if (r && r.ok) return r;
            } catch(e) {}
            try {
              const r2 = await _fetch('/out/releases/release_latest.json', init);
              if (r2 && r2.ok) return r2;
            } catch(e) {}
            return new Response(JSON.stringify({ok:false, err:'RELEASE_LATEST_NOT_FOUND', source:'interceptor_v1'}), {
              status: 200, headers: {'Content-Type':'application/json'}
            });
          }
        } catch(e) {}
        return _fetch(resource, init);
      };
    }

    const _si = window.setInterval ? window.setInterval.bind(window) : null;
    if (_si) {
      window.setInterval = function(fn, ms, ...args){
        try{
          const src = fn && fn.toString ? String(fn.toString()) : '';
          if (src && (src.includes('release_latest') || src.includes('ReleaseCard')) && ms >= 5000 && ms <= 120000) {
            return 0; // block noisy pollers only
          }
        } catch(e) {}
        return _si(fn, ms, ...args);
      };
    }
  } catch(e) {}
})();
""").lstrip()

append = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_RUNS_V2 =====================
   Runs-only release card (no spam):
   - Copy package link / Copy sha
   - STALE if release_latest.json points to missing package
   - Fixed overlay; independent from rerender
========================================================================= */
(()=> {
  if (window.__vsp_release_card_runs_v2) return;
  window.__vsp_release_card_runs_v2 = true;

  const $ = (sel, root=document) => root.querySelector(sel);

  function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }

  function el(tag, attrs={}, children=[]){
    const n = document.createElement(tag);
    for (const [k,v] of Object.entries(attrs||{})){
      if (k === "class") n.className = v;
      else if (k === "style") n.setAttribute("style", v);
      else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
      else if (v !== undefined && v !== null) n.setAttribute(k, String(v));
    }
    for (const c of (children||[])){
      if (c === null || c === undefined) continue;
      n.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    }
    return n;
  }

  function normPkgUrl(pkg){
    if (!pkg) return "";
    let x = String(pkg).trim();
    if (!x) return "";
    if (x.startsWith("http://") || x.startsWith("https://")) return x;
    x = x.replace(/^\.\//,'');
    if (x.startsWith("/")) return x;
    // allow "out_ci/..." style
    if (x.startsWith("out_ci/") || x.startsWith("out/")) return "/" + x;
    // fallback: assume releases folder
    return "/out_ci/releases/" + x;
  }

  async function fetchJson(url, timeoutMs=8000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, cache:"no-store"});
      if (!r.ok) return {ok:false, _http:r.status, _url:url};
      const j = await r.json();
      return {ok:true, j, _url:url};
    }catch(e){
      return {ok:false, _err:String(e||"ERR"), _url:url};
    }finally{
      clearTimeout(t);
    }
  }

  async function headExists(url, timeoutMs=6000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {method:"HEAD", signal: ctrl.signal, cache:"no-store"});
      return {ok:true, status:r.status, exists: r.status>=200 && r.status<400};
    }catch(e){
      // if HEAD blocked, try GET small
      try{
        const r2 = await fetch(url, {method:"GET", signal: ctrl.signal, cache:"no-store"});
        return {ok:true, status:r2.status, exists: r2.status>=200 && r2.status<400};
      }catch(e2){
        return {ok:false, status:0, exists:false, err:String(e2||e||"ERR")};
      }
    }finally{
      clearTimeout(t);
    }
  }

  function pill(status){
    const map = {
      "OK":      {bg:"#0f2a1b", bd:"#1f6f4a", fg:"#86f3b3"},
      "STALE":   {bg:"#2a1f0f", bd:"#9b6a1b", fg:"#ffd08a"},
      "NO PKG":  {bg:"#1b1b1b", bd:"#666",   fg:"#ddd"},
      "CHECK":   {bg:"#0f1b2a", bd:"#1b4f9b", fg:"#9fd0ff"},
      "ERR":     {bg:"#2a0f14", bd:"#9b1b2c", fg:"#ff9fb0"},
    };
    const s = map[status] || map["NO PKG"];
    return el("span", {style:`display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;border:1px solid ${s.bd};background:${s.bg};color:${s.fg};font-size:12px;letter-spacing:.2px;`}, [status]);
  }

  async function copyText(txt){
    try{
      await navigator.clipboard.writeText(txt);
      return true;
    }catch(e){
      try{
        const ta = el("textarea",{style:"position:fixed;left:-9999px;top:-9999px;opacity:0;"},[txt]);
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        ta.remove();
        return true;
      }catch(e2){ return false; }
    }
  }

  const css = el("style", {}, [`
    .vsp-relcardv2{position:fixed;right:18px;bottom:18px;z-index:99999;width:340px;
      background:rgba(10,14,20,.92);border:1px solid rgba(255,255,255,.08);border-radius:14px;
      box-shadow:0 10px 30px rgba(0,0,0,.45);backdrop-filter: blur(8px); color:#e9eef7;
      font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial;
    }
    .vsp-relcardv2 .hd{display:flex;align-items:center;justify-content:space-between;padding:10px 12px 6px 12px;}
    .vsp-relcardv2 .ttl{font-weight:700;font-size:13px;opacity:.95}
    .vsp-relcardv2 .bd{padding:6px 12px 12px 12px;}
    .vsp-relcardv2 .row{display:flex;gap:10px;align-items:flex-start;margin:6px 0;}
    .vsp-relcardv2 .k{width:72px;opacity:.7;font-size:12px}
    .vsp-relcardv2 .v{flex:1;word-break:break-all;font-size:12px;opacity:.95}
    .vsp-relcardv2 .btns{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
    .vsp-relcardv2 button{cursor:pointer;border-radius:10px;border:1px solid rgba(255,255,255,.10);
      background:rgba(255,255,255,.06);color:#e9eef7;padding:6px 10px;font-size:12px}
    .vsp-relcardv2 button:hover{background:rgba(255,255,255,.10)}
    .vsp-relcardv2 button:disabled{opacity:.45;cursor:not-allowed}
    .vsp-relcardv2 .ft{margin-top:8px;font-size:11px;opacity:.6}
  `]);

  function ensure(){
    if ($("#vsp_release_card_v2")) return $("#vsp_release_card_v2");
    document.head.appendChild(css);

    const state = {status:"CHECK", ts:"", pkg:"", sha:"", note:"", checkedAt:0, exists:null};

    const statusSlot = el("span", {}, [pill("CHECK")]);

    const card = el("div", {id:"vsp_release_card_v2", class:"vsp-relcardv2"}, [
      el("div", {class:"hd"}, [
        el("div", {class:"ttl"}, ["Current Release"]),
        el("div", {}, [statusSlot])
      ]),
      el("div", {class:"bd"}, [
        el("div", {class:"row"}, [el("div",{class:"k"},["ts"]),  el("div",{class:"v", id:"vsp_rel_ts"},["-"])]),
        el("div", {class:"row"}, [el("div",{class:"k"},["package"]), el("div",{class:"v", id:"vsp_rel_pkg"},["-"])]),
        el("div", {class:"row"}, [el("div",{class:"k"},["sha"]), el("div",{class:"v", id:"vsp_rel_sha"},["-"])]),
        el("div", {class:"btns"}, [
          el("button", {id:"vsp_rel_copy_pkg"}, ["Copy package link"]),
          el("button", {id:"vsp_rel_copy_sha"}, ["Copy sha"]),
          el("button", {id:"vsp_rel_refresh"}, ["Refresh"]),
          el("button", {id:"vsp_rel_hide"}, ["Hide"]),
        ]),
        el("div",{class:"ft", id:"vsp_rel_ft"},["loading..."])
      ])
    ]);

    function setStatus(x){
      state.status = x;
      statusSlot.replaceChildren(pill(x));
    }

    function setText(id, v){
      const n = $("#"+id);
      if (n) n.textContent = (v && String(v).trim()) ? String(v) : "-";
    }

    async function run(force=false){
      const now = Date.now();
      if (!force && (now - state.checkedAt) < 30000) return; // cache 30s
      state.checkedAt = now;

      setStatus("CHECK");
      $("#vsp_rel_ft").textContent = "checking release_latest.json ...";

      // try in order: out_ci -> out -> backend (if any)
      const sources = [
        "/out_ci/releases/release_latest.json",
        "/out/releases/release_latest.json",
        "/api/vsp/release_latest",
      ];

      let meta = null, srcOk = null;
      for (const u of sources){
        const r = await fetchJson(u, 7000);
        if (r.ok && r.j && (typeof r.j === "object")){
          meta = r.j; srcOk = u; break;
        }
        await sleep(120);
      }

      if (!meta){
        setStatus("NO PKG");
        setText("vsp_rel_ts","-");
        setText("vsp_rel_pkg","-");
        setText("vsp_rel_sha","-");
        $("#vsp_rel_ft").textContent = "release_latest.json not found (no spam).";
        $("#vsp_rel_copy_pkg").disabled = true;
        $("#vsp_rel_copy_sha").disabled = true;
        return;
      }

      const ts = meta.ts || meta.timestamp || "";
      const sha = meta.sha || meta.sha256 || "";
      const pkg = meta.package || meta.pkg || meta.file || meta.path || "";

      const pkgUrl = normPkgUrl(pkg);

      setText("vsp_rel_ts", ts || "-");
      setText("vsp_rel_pkg", pkgUrl || "-");
      setText("vsp_rel_sha", sha || "-");

      $("#vsp_rel_copy_pkg").disabled = !pkgUrl;
      $("#vsp_rel_copy_sha").disabled = !sha;

      $("#vsp_rel_ft").textContent = `source=${srcOk || "?"}`;

      if (!pkgUrl){
        setStatus("NO PKG");
        $("#vsp_rel_ft").textContent = `source=${srcOk || "?"} • missing package field`;
        return;
      }

      // probe file existence
      $("#vsp_rel_ft").textContent = `source=${srcOk || "?"} • probing package...`;
      const probe = await headExists(pkgUrl, 6000);
      if (probe.ok && probe.exists){
        setStatus("OK");
        $("#vsp_rel_ft").textContent = `OK • source=${srcOk || "?"}`;
      } else {
        setStatus("STALE");
        const st = probe.status ? `http=${probe.status}` : "net-err";
        $("#vsp_rel_ft").textContent = `STALE • ${st} • source=${srcOk || "?"}`;
      }
    }

    card.addEventListener("click", async (e)=>{
      const t = e.target;
      if (!t) return;

      if (t.id === "vsp_rel_hide"){
        card.remove();
        return;
      }
      if (t.id === "vsp_rel_refresh"){
        await run(true);
        return;
      }
      if (t.id === "vsp_rel_copy_pkg"){
        const pkg = $("#vsp_rel_pkg")?.textContent || "";
        if (pkg && pkg !== "-"){
          const full = pkg.startsWith("http") ? pkg : (location.origin + pkg);
          const ok = await copyText(full);
          $("#vsp_rel_ft").textContent = ok ? "copied package link" : "copy failed";
        }
        return;
      }
      if (t.id === "vsp_rel_copy_sha"){
        const sha = $("#vsp_rel_sha")?.textContent || "";
        if (sha && sha !== "-"){
          const ok = await copyText(sha);
          $("#vsp_rel_ft").textContent = ok ? "copied sha" : "copy failed";
        }
        return;
      }
    });

    document.body.appendChild(card);
    run(true);
    return card;
  }

  function boot(){
    try{ ensure(); } catch(e){}
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
""").lstrip()

# add interceptor at very top + append v2 at end
s2 = prefix + "\n" + s.rstrip() + "\n\n" + append + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", p, "(added interceptor + release card v2)")
PY

echo "== restart UI (best-effort) =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== sanity marker =="
grep -n "VSP_P1_RELEASE_CARD_RUNS_V2" -n "$JS" | head -n 5 || true
echo "[DONE] release card v2 applied. Reload /runs in browser."
