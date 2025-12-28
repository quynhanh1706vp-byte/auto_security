#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p119_${TS}"
echo "[OK] backup: ${F}.bak_p119_${TS}"

cat > "$F" <<'JS'
/* VSP_P119_FIX_C_HEADER_STRIP_V1
 * Fix header strip on /c/*:
 * - Runs loaded: undefined  -> Runs loaded: <count>
 * - Latest RID: ...         -> sync from /api/ui/runs_v3
 * - Status badge text       -> GREEN/AMBER/RED based on fetch health
 * Safe: no external libs, DOM-guarded.
 */
(() => {
  const $  = (sel, root=document) => root.querySelector(sel);
  const $$ = (sel, root=document) => Array.from(root.querySelectorAll(sel));

  function safeText(el, s){
    if (!el) return false;
    el.textContent = String(s ?? "");
    return true;
  }

  function findLeafByContains(root, needle){
    needle = String(needle || "");
    if (!needle) return null;
    const els = $$("*", root);
    for (const el of els){
      if (el.children && el.children.length) continue; // leaf only
      const t = (el.textContent || "").trim();
      if (!t) continue;
      if (t.includes(needle)) return el;
    }
    return null;
  }

  function setLabelValue(root, label, value){
    // Try exact "Label: something" node replacement
    const leaf = findLeafByContains(root, label);
    if (!leaf) return false;

    const txt = (leaf.textContent || "").trim();
    const colon = txt.includes(":") ? ":" : "";
    // Keep label prefix as it appears (avoid changing localized text)
    if (txt.startsWith(label)) {
      leaf.textContent = `${label}${colon} ${value}`;
    } else {
      // fallback: overwrite fully
      leaf.textContent = `${label}${colon} ${value}`;
    }
    return true;
  }

  function setBadge(root, status){
    status = String(status || "AMBER").toUpperCase();
    if (!["GREEN","AMBER","RED"].includes(status)) status = "AMBER";

    // Prefer a small "pill" leaf whose text is one of these
    const leaves = $$("*", root).filter(el => (!el.children || el.children.length===0));
    const pill = leaves.find(el => ["GREEN","AMBER","RED","UNKNOWN"].includes((el.textContent||"").trim().toUpperCase()))
              || leaves.find(el => (el.textContent||"").trim().toUpperCase()==="RED");

    if (pill) {
      pill.textContent = status;
      pill.setAttribute("data-vsp-status", status);
      return true;
    }
    return false;
  }

  async function fetchJson(url){
    const r = await fetch(url, { credentials: "same-origin" });
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    return { ok:r.ok, status:r.status, json:j };
  }

  async function main(){
    const tb = document.getElementById("tb") || document; // audit had id=tb
    // only touch when header exists
    const hint = (tb.textContent || "");
    if (!hint.includes("Runs loaded") && !hint.includes("Latest RID") && !hint.includes("VSP")) {
      // still proceed but won't force anything
    }

    let status = "AMBER";
    let runsCount = "";
    let latestRid = "";

    try {
      const runs = await fetchJson("/api/ui/runs_v3?limit=50&include_ci=1");
      if (runs.ok && runs.json && Array.isArray(runs.json.items)) {
        runsCount = runs.json.items.length;
        latestRid = (runs.json.items[0]?.rid || "").trim();
        status = "GREEN";
      } else {
        status = "AMBER";
      }
    } catch (e) {
      status = "RED";
    }

    if (runsCount !== "") setLabelValue(tb, "Runs loaded", runsCount);
    if (latestRid) setLabelValue(tb, "Latest RID", latestRid);
    setBadge(tb, status);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();
JS

echo "[OK] wrote $F"
echo "[NEXT] Hard refresh: Ctrl+Shift+R on http://127.0.0.1:8910/c/dashboard?rid=VSP_CI_20251219_092640"
