#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_tabs4_autorid_v1.js"
TPL_DIR="templates"

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p static/js

cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true
echo "[BACKUP] ${JS}.bak_${TS} (if existed)"

cat > "$JS" <<'JS'
/* VSP_P1_TABS4_AUTORID_NODASH_V1
   - Only for non-dashboard tabs (Runs/Settings/Data Source/Rule Overrides)
   - Poll rid_latest_gate_root_v2 + ui_health_v2
   - Store RID in localStorage + dispatch event vsp:rid-changed
*/
(function(){
  const POLL_MS = 5000;
  const LS_KEY = "vsp_current_rid_v2";

  function pageIsDashboard(){
    // hard block: never run on /vsp5 (dashboard)
    try { return (location.pathname || "").startsWith("/vsp5"); } catch(e) { return false; }
  }
  if(pageIsDashboard()) return;

  function ensureBadge(){
    let el = document.getElementById("vsp-ui-ok-badge");
    if(el) return el;
    el = document.createElement("div");
    el.id = "vsp-ui-ok-badge";
    el.style.cssText = [
      "position:fixed","right:14px","bottom:14px","z-index:99999",
      "padding:10px 12px","border-radius:12px","font:600 12px/1.2 system-ui,Segoe UI,Roboto,Arial",
      "background:#1b2333","color:#d6e2ff","border:1px solid rgba(255,255,255,.12)",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    el.textContent = "UI OK: …";
    document.body.appendChild(el);
    return el;
  }

  async function fetchJSON(url){
    try{
      const r = await fetch(url, {cache:"no-store"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if(!ct.includes("application/json")){
        return {ok:false, err:"non-json", status:r.status, url};
      }
      const j = await r.json();
      if(typeof j !== "object" || j === null) return {ok:false, err:"bad-json", status:r.status, url};
      j._http_status = r.status;
      return j;
    }catch(e){
      return {ok:false, err:String(e), url};
    }
  }

  function setBadge(ok, rid, detail){
    const el = ensureBadge();
    if(ok){
      el.textContent = `UI OK: GREEN • ${rid||"-"}`;
      el.style.borderColor = "rgba(65,255,164,.35)";
      el.style.background = "rgba(10,28,18,.92)";
      el.style.color = "#bfffe0";
    }else{
      el.textContent = `UI OK: RED • ${rid||"-"}`;
      el.style.borderColor = "rgba(255,96,96,.45)";
      el.style.background = "rgba(35,10,12,.92)";
      el.style.color = "#ffd4d4";
    }
    if(detail && detail.err){ el.title = detail.err; }
    else if(detail && detail.checks && (!detail.ok)){
      try{ el.title = JSON.stringify(detail.checks).slice(0,700); }catch(e){ el.title=""; }
    } else el.title = "";
  }

  function tryUpdateRidPickers(rid){
    if(!rid) return;
    try{
      // Update <select> / <input> that looks like rid picker
      const nodes = Array.from(document.querySelectorAll("select, input"));
      for(const n of nodes){
        const id = (n.id||"").toLowerCase();
        const nm = (n.name||"").toLowerCase();
        if(id.includes("rid") || nm.includes("rid")){
          if(n.tagName === "SELECT"){
            // set if option exists
            const opt = Array.from(n.options||[]).find(o => (o.value===rid || (o.textContent||"").includes(rid)));
            if(opt){
              n.value = opt.value;
              n.dispatchEvent(new Event("change", {bubbles:true}));
            }
          }else{
            // input
            if(n.value !== rid){
              n.value = rid;
              n.dispatchEvent(new Event("input", {bubbles:true}));
              n.dispatchEvent(new Event("change", {bubbles:true}));
            }
          }
        }
      }
    }catch(e){}
  }

  async function callReloadHooks(){
    // Soft hooks (if tabs define them)
    const hooks = [
      "VSP_reloadAll",
      "VSP_reloadRuns",
      "VSP_reloadReports",
      "VSP_reloadSettings",
      "VSP_reloadDataSource",
      "VSP_reloadRuleOverrides",
    ];
    let called = false;
    for(const h of hooks){
      try{
        const fn = window[h];
        if(typeof fn === "function"){
          called = true;
          await Promise.resolve(fn());
        }
      }catch(e){}
    }
    return called;
  }

  let lastRID = null;

  function getStoredRID(){
    try{ return localStorage.getItem(LS_KEY) || ""; }catch(e){ return ""; }
  }
  function storeRID(rid){
    try{ localStorage.setItem(LS_KEY, rid); }catch(e){}
  }

  async function tick(){
    const latest = await fetchJSON("/api/vsp/rid_latest_gate_root_v2");
    const rid = (latest && latest.ok && latest.rid) ? latest.rid : null;

    if(rid && rid !== lastRID){
      lastRID = rid;
      storeRID(rid);
      window.VSP_CURRENT_RID = rid;

      // sync any rid picker on page
      tryUpdateRidPickers(rid);

      // notify others
      try{
        window.dispatchEvent(new CustomEvent("vsp:rid-changed", {detail:{rid, latest}}));
      }catch(e){}

      // reload tab data without full refresh
      const called = await callReloadHooks();
      // If nothing can reload AND page isn't critical, do nothing.
      // (No hard reload here to keep it safe/commercial.)
      if(!called){
        // Optional: if you really want, enable soft reload:
        // setTimeout(()=>location.reload(), 1200);
      }
    }else if(!lastRID){
      // initialize from localStorage if available
      const st = getStoredRID();
      if(st) lastRID = st;
    }

    const health = await fetchJSON("/api/vsp/ui_health_v2?rid=" + encodeURIComponent(lastRID||""));
    setBadge(!!(health && health.ok), lastRID, health);
  }

  setTimeout(()=>{ ensureBadge(); tick(); setInterval(tick, POLL_MS); }, 900);
})();
JS

echo "[OK] wrote $JS"

python3 - <<'PY'
from pathlib import Path
import re, time

TPL_DIR = Path("templates")
MARK = "VSP_P1_TABS4_AUTORID_NODASH_V1"

# choose templates for 4 tabs only, exclude dashboard-like pages
targets=[]
for p in TPL_DIR.rglob("*.html"):
    name=p.name.lower()
    if "vsp5" in name or "dash" in name or "dashboard" in name:
        continue
    if any(k in name for k in ["runs", "report", "setting", "data_source", "datasource", "rule_overrides", "override"]):
        targets.append(p)

targets = sorted(set(targets))
if not targets:
    print("[WARN] no templates matched for 4 tabs")
    raise SystemExit(0)

for p in targets:
    t = p.read_text(encoding="utf-8", errors="replace")
    if MARK in t:
        continue
    # Inject before </body> if exists else append end
    inject = f'\n<!-- {MARK} -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{' + ' asset_v|default("") ' + '}}"></script>\n'
    if "</body>" in t:
        t2 = t.replace("</body>", inject + "</body>", 1)
    else:
        t2 = t + inject
    p.write_text(t2, encoding="utf-8")
    print("[OK] injected into", p)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== smoke 4 tabs HTML contain vsp_tabs4_autorid_v1.js =="
for path in /settings /data_source /rule_overrides /runs /runs_reports /reports; do
  code="$(curl -sS -o /tmp/vsp_tab.$$ -w '%{http_code}' "$BASE$path" || true)"
  if [ "$code" = "200" ]; then
    if grep -q "vsp_tabs4_autorid_v1.js" /tmp/vsp_tab.$$; then
      echo "[OK] $path has autorid js"
    else
      echo "[WARN] $path 200 but no autorid js (maybe different template/route)"
    fi
  fi
done
rm -f /tmp/vsp_tab.$$ 2>/dev/null || true
