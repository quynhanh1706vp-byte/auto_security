#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_release_v2_${TS}"
echo "[BACKUP] ${JS}.bak_release_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

js = Path("static/js/vsp_runs_quick_actions_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_CARD_V2_RUNS_ONLY_V2"
if marker in s:
    print("[OK] release card v2 already present:", marker)
    raise SystemExit(0)

block = r"""
/* ===================== %s =====================
   - runs-only (never touches Dashboard)
   - no spam: refresh default 120s, single json fetch + single HEAD/Range check
   - STALE (amber) if release_latest.json points to missing package (404)
   - fixed overlay independent of rerender
   - buttons: Copy package link / Copy sha
================================================= */
(() => {
  if (window.__vsp_p1_release_card_v2_runs_only_v2) return;
  window.__vsp_p1_release_card_v2_runs_only_v2 = true;

  const CFG = {
    refreshMs: 120000,
    headTimeoutMs: 6000,
    jsonUrls: [
      "/api/vsp/release_latest.json",
      "/api/vsp/release_latest",
      "/release_latest.json",
      "/static/release_latest.json",
    ],
  };

  const nowIso = () => new Date().toISOString().replace("T"," ").replace("Z","Z");

  function isRunsLikePage(){
    const p = (location.pathname || "").toLowerCase();
    // hard guard: never show on dashboard-ish
    if (p.includes("dashboard") || p === "/vsp5" || p === "/") return false;
    if (p.includes("runs") || p.includes("reports")) return true;
    // fallback to DOM hints if routing is custom
    return !!document.querySelector(
      "#vsp_runs_root,#vsp_runs_reports_root,[data-vsp-page='runs'],[data-vsp-page='runs_reports'],.vsp-runs-root"
    );
  }

  if (!isRunsLikePage()) return;

  function ensureStyle(){
    if (document.getElementById("vsp_release_card_v2_style")) return;
    const st = document.createElement("style");
    st.id = "vsp_release_card_v2_style";
    st.textContent = `
#vsp_release_card_v2{
  position:fixed; right:16px; bottom:16px; z-index:999999;
  width:360px; max-width:calc(100vw - 28px);
  background:rgba(8,14,26,.92);
  border:1px solid rgba(255,255,255,.10);
  box-shadow:0 14px 40px rgba(0,0,0,.55);
  border-radius:14px; overflow:hidden;
  font: 13px/1.35 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial;
  color:rgba(255,255,255,.88);
  backdrop-filter: blur(8px);
}
#vsp_release_card_v2 .h{
  display:flex; align-items:center; justify-content:space-between;
  padding:10px 12px; background:rgba(255,255,255,.03);
  border-bottom:1px solid rgba(255,255,255,.08);
}
#vsp_release_card_v2 .t{
  font-weight:700; letter-spacing:.2px; color:rgba(255,255,255,.92);
}
#vsp_release_card_v2 .badge{
  display:inline-flex; align-items:center; gap:6px;
  border-radius:999px; padding:3px 9px; font-weight:700;
  border:1px solid rgba(255,255,255,.10);
}
#vsp_release_card_v2 .dot{ width:8px; height:8px; border-radius:999px; background:rgba(255,255,255,.5); }
#vsp_release_card_v2 .b-ok{ background:rgba(0,255,170,.08); color:rgba(140,255,220,.96); border-color:rgba(0,255,170,.20); }
#vsp_release_card_v2 .b-amber{ background:rgba(255,200,0,.08); color:rgba(255,216,106,.96); border-color:rgba(255,200,0,.22); }
#vsp_release_card_v2 .b-red{ background:rgba(255,80,80,.08); color:rgba(255,160,160,.96); border-color:rgba(255,80,80,.22); }
#vsp_release_card_v2 .c{ padding:10px 12px 12px; }
#vsp_release_card_v2 .row{ display:flex; justify-content:space-between; gap:10px; padding:4px 0; }
#vsp_release_card_v2 .k{ color:rgba(255,255,255,.60); }
#vsp_release_card_v2 .v{ color:rgba(255,255,255,.90); text-align:right; word-break:break-word; }
#vsp_release_card_v2 a{ color:rgba(140,205,255,.95); text-decoration:none; }
#vsp_release_card_v2 a:hover{ text-decoration:underline; }
#vsp_release_card_v2 .btns{ display:flex; flex-wrap:wrap; gap:8px; margin-top:10px; }
#vsp_release_card_v2 button{
  border:1px solid rgba(255,255,255,.12);
  background:rgba(255,255,255,.04);
  color:rgba(255,255,255,.88);
  border-radius:10px; padding:7px 10px;
  cursor:pointer; font-weight:700;
}
#vsp_release_card_v2 button:hover{ background:rgba(255,255,255,.07); }
#vsp_release_card_v2 .mini{ font-size:12px; color:rgba(255,255,255,.55); margin-top:8px; }
#vsp_release_card_v2 .toast{
  position:absolute; left:12px; bottom:10px;
  font-size:12px; color:rgba(255,255,255,.75);
  opacity:0; transform:translateY(6px);
  transition:opacity .18s ease, transform .18s ease;
}
#vsp_release_card_v2.showtoast .toast{ opacity:1; transform:translateY(0); }
`;
    document.head.appendChild(st);
  }

  function ensureCard(){
    let card = document.getElementById("vsp_release_card_v2");
    if (card) return card;
    card = document.createElement("div");
    card.id = "vsp_release_card_v2";
    card.innerHTML = `
      <div class="h">
        <div class="t">Current Release</div>
        <div class="badge"><span class="dot"></span><span class="lbl">…</span></div>
      </div>
      <div class="c">
        <div class="row"><div class="k">ts</div><div class="v" data-k="ts">-</div></div>
        <div class="row"><div class="k">package</div><div class="v" data-k="pkg">-</div></div>
        <div class="row"><div class="k">sha</div><div class="v" data-k="sha">-</div></div>
        <div class="btns">
          <button type="button" data-act="copy_pkg">Copy package link</button>
          <button type="button" data-act="copy_sha">Copy sha</button>
          <button type="button" data-act="refresh">Refresh</button>
          <button type="button" data-act="hide">Hide</button>
        </div>
        <div class="mini" data-k="hint">updated: -</div>
      </div>
      <div class="toast" data-k="toast">copied</div>
    `;
    document.body.appendChild(card);
    return card;
  }

  function setBadge(card, kind, text){
    const b = card.querySelector(".badge");
    const lbl = card.querySelector(".badge .lbl");
    b.classList.remove("b-ok","b-amber","b-red");
    if (kind === "ok") b.classList.add("b-ok");
    else if (kind === "amber") b.classList.add("b-amber");
    else if (kind === "red") b.classList.add("b-red");
    lbl.textContent = text;
  }

  function toast(card, msg){
    const t = card.querySelector('[data-k="toast"]');
    t.textContent = msg;
    card.classList.add("showtoast");
    setTimeout(() => card.classList.remove("showtoast"), 900);
  }

  async function copyText(card, text){
    try{
      if (navigator.clipboard && navigator.clipboard.writeText){
        await navigator.clipboard.writeText(text);
        toast(card, "Copied");
        return true;
      }
    }catch(_){}
    try{
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.left = "-1000px";
      ta.style.top = "-1000px";
      document.body.appendChild(ta);
      ta.focus(); ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      toast(card, ok ? "Copied" : "Copy failed");
      return ok;
    }catch(_){}
    toast(card, "Copy failed");
    return false;
  }

  async function fetchJsonTry(urls){
    for (const u of urls){
      try{
        const r = await fetch(u, { cache: "no-store", credentials: "same-origin" });
        if (!r.ok) continue;
        const j = await r.json();
        if (j && typeof j === "object") return { ok:true, url:u, json:j };
      }catch(_){}
    }
    return { ok:false };
  }

  function pickFirst(obj, keys){
    for (const k of keys){
      if (obj && obj[k] != null && String(obj[k]).trim() !== "") return obj[k];
    }
    return null;
  }

  function normalizeRelease(j){
    // tolerant schema: accept common fields without breaking older pipelines
    const ts = pickFirst(j, ["ts","timestamp","built_at","created_at","time","release_ts"]);
    const sha = pickFirst(j, ["sha","git_sha","commit","commit_sha","hash"]);
    const pkg = pickFirst(j, ["pkg_url","package_url","download_url","url","href","pkg","package","path","pkg_path","package_path","tgz","tgz_path"]);
    const name = pickFirst(j, ["pkg_name","package_name","name","filename"]);
    let pkgUrl = null;
    if (pkg){
      try{ pkgUrl = new URL(String(pkg), location.origin).toString(); }catch(_){ pkgUrl = String(pkg); }
    }
    const pkgName =
      name ? String(name) :
      (pkgUrl ? decodeURIComponent(pkgUrl.split("/").pop() || "package") : "package");
    return {
      ts: ts ? String(ts) : null,
      sha: sha ? String(sha) : null,
      pkgUrl,
      pkgName,
      raw: j
    };
  }

  async function existsCheck(url){
    // HEAD first; if blocked, fallback to tiny GET (Range)
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), CFG.headTimeoutMs);
    try{
      let r = await fetch(url, { method: "HEAD", cache:"no-store", credentials:"same-origin", signal: ac.signal });
      clearTimeout(t);
      if (r.ok) return { ok:true, exists:true, status:r.status, via:"HEAD" };
      if (r.status === 404) return { ok:true, exists:false, status:404, via:"HEAD" };
      // other status => unknown but report
      return { ok:true, exists:null, status:r.status, via:"HEAD" };
    }catch(_){
      clearTimeout(t);
    }

    const ac2 = new AbortController();
    const t2 = setTimeout(() => ac2.abort(), CFG.headTimeoutMs);
    try{
      const r2 = await fetch(url, {
        method: "GET",
        headers: { "Range": "bytes=0-0" },
        cache:"no-store",
        credentials:"same-origin",
        signal: ac2.signal
      });
      clearTimeout(t2);
      if (r2.ok || r2.status === 206) return { ok:true, exists:true, status:r2.status, via:"RANGE" };
      if (r2.status === 404) return { ok:true, exists:false, status:404, via:"RANGE" };
      return { ok:true, exists:null, status:r2.status, via:"RANGE" };
    }catch(e){
      clearTimeout(t2);
      return { ok:false, exists:null, status:null, via:"ERR" };
    }
  }

  function shortSha(sha){
    if (!sha) return "-";
    const s = String(sha).trim();
    return s.length > 12 ? (s.slice(0,12) + "…") : s;
  }

  function fmtTs(ts){
    if (!ts) return "-";
    const s = String(ts);
    // if looks like epoch seconds/ms, convert
    if (/^\d{10,13}$/.test(s)){
      const n = int(s);
      const ms = (s.length === 10) ? n*1000 : n;
      try{ return new Date(ms).toISOString().replace("T"," ").replace("Z","Z"); }catch(_){}
    }
    return s;
  }
  function int(x){ try{ return parseInt(String(x),10); }catch(_){ return 0; } }

  let last = { pkgUrl:null, sha:null };

  async function tick(force){
    ensureStyle();
    const card = ensureCard();

    // keep fixed overlay even if something rerenders body; re-attach if needed
    if (!document.body.contains(card)) document.body.appendChild(card);

    setBadge(card, "", "LOADING");
    card.querySelector('[data-k="hint"]').textContent = "updated: " + nowIso();

    const res = await fetchJsonTry(CFG.jsonUrls);
    if (!res.ok){
      setBadge(card, "red", "NO DATA");
      card.querySelector('[data-k="ts"]').textContent = "-";
      card.querySelector('[data-k="pkg"]').innerHTML = "-";
      card.querySelector('[data-k="sha"]').textContent = "-";
      card.querySelector('[data-k="hint"]').textContent = "updated: " + nowIso() + " • release_latest.json not reachable";
      last = { pkgUrl:null, sha:null };
      return;
    }

    const rel = normalizeRelease(res.json);
    const ts = rel.ts || "-";
    const sha = rel.sha || "-";
    const pkgUrl = rel.pkgUrl;

    card.querySelector('[data-k="ts"]').textContent = ts;
    card.querySelector('[data-k="sha"]').textContent = sha ? shortSha(sha) : "-";

    if (pkgUrl){
      const safeName = rel.pkgName || "package";
      card.querySelector('[data-k="pkg"]').innerHTML = `<a href="${pkgUrl}" target="_blank" rel="noreferrer">${safeName}</a>`;
    }else{
      card.querySelector('[data-k="pkg"]').innerHTML = "-";
    }

    // stale detection: only if pkgUrl exists
    if (pkgUrl){
      const ex = await existsCheck(pkgUrl);
      if (ex.ok && ex.exists === false){
        setBadge(card, "amber", "STALE");
        card.querySelector('[data-k="hint"]').textContent =
          `updated: ${nowIso()} • package missing (404) • via ${ex.via}`;
      }else if (ex.ok && ex.exists === true){
        setBadge(card, "ok", "OK");
        card.querySelector('[data-k="hint"]').textContent =
          `updated: ${nowIso()} • ${res.url}`;
      }else{
        setBadge(card, "amber", "CHECK");
        card.querySelector('[data-k="hint"]').textContent =
          `updated: ${nowIso()} • cannot verify package • ${res.url}`;
      }
    }else{
      setBadge(card, "amber", "NO PKG");
      card.querySelector('[data-k="hint"]').textContent =
        `updated: ${nowIso()} • release json has no package url • ${res.url}`;
    }

    last = { pkgUrl: pkgUrl || null, sha: rel.sha || null };

    // wire actions
    const onClick = async (ev) => {
      const btn = ev.target && ev.target.closest("button[data-act]");
      if (!btn) return;
      const act = btn.getAttribute("data-act");
      if (act === "copy_pkg"){
        if (!last.pkgUrl) return toast(card, "No package link");
        await copyText(card, last.pkgUrl);
      } else if (act === "copy_sha"){
        if (!last.sha) return toast(card, "No sha");
        await copyText(card, String(last.sha));
      } else if (act === "refresh"){
        await tick(true);
      } else if (act === "hide"){
        card.remove();
      }
    };

    // avoid double binding
    if (!card.__vsp_release_v2_bound){
      card.__vsp_release_v2_bound = true;
      card.addEventListener("click", onClick);
    }
  }

  function start(){
    tick(false);
    setInterval(() => {
      // only refresh while still on runs-like page
      if (!isRunsLikePage()) return;
      tick(false);
    }, CFG.refreshMs);
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", start, { once:true });
  } else {
    start();
  }
})();
""" % marker

js.write_text(s.rstrip() + "\n\n" + block.strip() + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

if [ "$node_ok" -eq 1 ]; then
  echo "== node --check =="
  node --check "$JS"
else
  echo "[WARN] node not found; skip syntax check"
fi

echo "== restart service (best-effort) =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "[DONE] release card v2 patched"
