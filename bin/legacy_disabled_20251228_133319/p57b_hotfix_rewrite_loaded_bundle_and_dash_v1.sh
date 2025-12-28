#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need cp; need mkdir; need node; need curl; need sudo; need systemctl; need head

OUT="out_ci"
EVID="$OUT/p57b_hotfix_${TS}"
mkdir -p "$EVID"

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
DASH="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }
[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }

cp -f "$BUNDLE" "$EVID/$(basename "$BUNDLE").bak_${TS}"
cp -f "$DASH"   "$EVID/$(basename "$DASH").bak_${TS}"
echo "[OK] backups => $EVID"

echo "== [1] rewrite bundle tabs5 SAFE =="
cat > "$BUNDLE" <<'JS'
/* VSP_BUNDLE_TABS5_SAFE_V2 - prevents JS crash, loads core modules in-order */
(function(){
  'use strict';
  const scripts = [
    "/static/js/vsp_tabs3_common_v3.js",
    "/static/js/vsp_topbar_commercial_v1.js",
    "/static/js/vsp_ui_shell_v1.js",
    "/static/js/vsp_cio_shell_apply_v1.js",
    "/static/js/vsp_polish_apply_p2_safe_v2.js",
    "/static/js/vsp_fetch_guard_rid_v1.js",
    "/static/js/vsp_rid_persist_patch_v1.js",
    "/static/js/vsp_rid_switch_refresh_all_v1.js",
    "/static/js/vsp_tabs4_autorid_v1.js"
  ];

  function already(src){
    return !!document.querySelector('script[src="' + src + '"]');
  }
  function loadOne(src){
    return new Promise((resolve) => {
      if (already(src)) return resolve({src, ok:true, cached:true});
      const s = document.createElement("script");
      s.src = src;
      s.async = false;
      s.onload = () => resolve({src, ok:true});
      s.onerror = () => resolve({src, ok:false});
      (document.head || document.documentElement).appendChild(s);
    });
  }

  (async function(){
    const results = [];
    for (const src of scripts){
      try { results.push(await loadOne(src)); }
      catch(e){ results.push({src, ok:false, err:String(e||"")}); }
    }
    try { console.debug("[VSP] bundle tabs5 loaded", results); } catch(_){}
    window.__VSP_BUNDLE_TABS5_SAFE_V2 = { ok:true, results };
  })();
})();
JS

echo "== [2] rewrite dashboard luxe SAFE =="
cat > "$DASH" <<'JS'
/* VSP_DASHBOARD_LUXE_SAFE_V2 - minimal, no-crash dashboard bootstrap */
(function(){
  'use strict';

  function el(tag, attrs){
    const x = document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) x.setAttribute(k, attrs[k]); }
    return x;
  }
  function safeText(x, t){ try{ x.textContent = t; } catch(_){} }

  function renderOverlay(stats){
    const id="vsp_dash_luxe_safe_v2";
    let box = document.getElementById(id);
    if(!box){
      box = el("div", { id });
      box.style.position="fixed";
      box.style.right="14px";
      box.style.bottom="14px";
      box.style.zIndex="99999";
      box.style.padding="12px 14px";
      box.style.borderRadius="14px";
      box.style.background="rgba(10,16,28,0.92)";
      box.style.border="1px solid rgba(255,255,255,0.08)";
      box.style.boxShadow="0 10px 30px rgba(0,0,0,0.35)";
      box.style.fontFamily="ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto";
      box.style.fontSize="12px";
      box.style.color="rgba(255,255,255,0.86)";
      box.style.minWidth="260px";

      const title = el("div");
      title.style.fontWeight="700";
      title.style.marginBottom="8px";
      safeText(title, "VSP Dashboard (SAFE)");
      box.appendChild(title);

      const body = el("div", { id: id+"_body" });
      box.appendChild(body);

      document.body.appendChild(box);
    }
    const body = document.getElementById(id+"_body");
    if(!body) return;

    body.innerHTML = "";
    const lines = [
      ["RID", stats.rid || "(none)"],
      ["Total", String(stats.total || 0)],
      ["CRITICAL", String(stats.CRITICAL||0)],
      ["HIGH", String(stats.HIGH||0)],
      ["MEDIUM", String(stats.MEDIUM||0)],
      ["LOW", String(stats.LOW||0)],
      ["INFO", String(stats.INFO||0)],
      ["TRACE", String(stats.TRACE||0)]
    ];
    for(const [k,v] of lines){
      const row = el("div");
      row.style.display="flex";
      row.style.justifyContent="space-between";
      row.style.gap="10px";
      row.style.padding="2px 0";
      const a=el("span"); a.style.opacity="0.75"; safeText(a,k);
      const b=el("span"); b.style.fontWeight="700"; safeText(b,v);
      row.appendChild(a); row.appendChild(b);
      body.appendChild(row);
    }
  }

  function normSev(s){
    s = String(s||"").toUpperCase().trim();
    if(["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].includes(s)) return s;
    if(s==="INFORMATIONAL") return "INFO";
    return "TRACE";
  }

  async function fetchTop(){
    const u = "/api/vsp/top_findings_v2?limit=200";
    const res = await fetch(u, { credentials:"same-origin" });
    if(!res.ok) throw new Error("HTTP "+res.status);
    return await res.json();
  }

  async function boot(){
    const stats = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,total:0,rid:(window.__VSP_RID||null)};
    try{
      const j = await fetchTop();
      const items = Array.isArray(j.items) ? j.items : [];
      stats.total = (typeof j.total==="number") ? j.total : items.length;
      stats.rid = j.run_id || j.rid || stats.rid || null;
      for(const it of items){
        const sev = normSev(it.severity || it.sev || it.level);
        stats[sev] = (stats[sev]||0) + 1;
      }
    }catch(e){
      stats.err = String(e||"");
      try{ console.warn("[VSP] dashboard safe fetch failed", e); }catch(_){}
    }
    renderOverlay(stats);
    window.__VSP_DASHBOARD_LUXE_SAFE_V2 = { ok:true, stats };
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", () => boot().catch(()=>{}));
  } else {
    boot().catch(()=>{});
  }
})();
JS

echo "== [3] node --check both =="
node --check "$BUNDLE" | cat
node --check "$DASH"   | cat
echo "[OK] syntax OK rewritten bundle+dash"

echo "== [4] restart service =="
sudo systemctl restart "$SVC"

echo "== [5] wait /vsp5 200 (max 40s) =="
ok=0
for i in $(seq 1 40); do
  code="$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != "1" ]; then
  echo "[ERR] service not reachable at $BASE/vsp5"
  exit 2
fi

echo "[DONE] P57B hotfix applied. Hard refresh browser: Ctrl+Shift+R"
echo "[EVID] $EVID"
