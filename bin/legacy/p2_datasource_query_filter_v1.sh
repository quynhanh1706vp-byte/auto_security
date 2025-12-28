#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

html="$(curl -fsS "$BASE/data_source")"
mapfile -t js < <(echo "$html" | grep -oE '/static/js/[^"'"'"' ]+\.js(\?v=[0-9]+)?' | sed 's/\?.*$//' | awk '!seen[$0]++')
[ "${#js[@]}" -gt 0 ] || { echo "[ERR] cannot extract JS from /data_source"; exit 2; }

pick=""
for u in "${js[@]}"; do
  b="$(basename "$u")"
  if echo "$b" | grep -qiE 'data_source_tab|data_source|datasource'; then pick="$b"; break; fi
done
[ -n "$pick" ] || pick="$(basename "${js[0]}")"
F="static/js/$pick"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p2qf_${TS}"
echo "[BACKUP] ${F}.bak_p2qf_${TS}"
echo "[INFO] patch target=$F"

if grep -q "VSP_P2_DS_QUERY_FILTER_V1" "$F"; then
  echo "[OK] already patched"
  echo "[NEXT] refresh: $BASE/data_source?severity=HIGH&q=codeql"
  exit 0
fi

cat >> "$F" <<'JS'

/* ===== VSP_P2_DS_QUERY_FILTER_V1 ===== */
(function(){
  function qs(sel,root){ return (root||document).querySelector(sel); }
  function sp(){ try{return new URL(location.href).searchParams;}catch(_){return null;} }
  function fire(el, type){ try{ el.dispatchEvent(new Event(type,{bubbles:true})); }catch(_){} }

  function apply(){
    var p=sp(); if(!p) return;
    var sev=(p.get("severity")||"").toUpperCase();
    var q=(p.get("q")||"").trim();
    if(!sev && !q) return;

    var sevSel = qs("select[name='severity'], #severity, #sev");
    var qInp  = qs("input[name='q'], #q, #search");

    if(sevSel && sev){ try{ sevSel.value=sev; }catch(_){ } fire(sevSel,"change"); }
    if(qInp && q){ try{ qInp.value=q; }catch(_){ } fire(qInp,"input"); fire(qInp,"change"); }

    var btn = qs("button#apply, #apply, .apply, button[data-action='apply']");
    if(btn) btn.click();
    if(window.__vspDataSourceApply){ try{ window.__vspDataSourceApply(); }catch(_){ } }
  }

  if(document.readyState!=="loading") setTimeout(apply, 80);
  else document.addEventListener("DOMContentLoaded", function(){ setTimeout(apply, 80); });
})();
JS

echo "[OK] patched (no sudo, no restart)"
echo "[NEXT] refresh: $BASE/data_source?severity=HIGH&q=codeql"
