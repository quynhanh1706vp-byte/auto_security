#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
T="templates/vsp_5tabs_enterprise_v2.html"
TBAK="templates/vsp_5tabs_enterprise_v2.html.bak_p2filters"
JSNEW="static/js/vsp_p2_dashboard_filters_v1.js"
JSLUXE="static/js/vsp_dashboard_luxe_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] rollback risky template/module changes =="
if [ -f "$TBAK" ]; then
  cp -f "$TBAK" "$T"
  echo "[OK] restored template from $TBAK"
else
  if [ -f "$T" ]; then
    cp -f "$T" "${T}.bak_rm_p2_${TS}"
    # remove injected script line if exists
    sed -i '/vsp_p2_dashboard_filters_v1\.js/d' "$T"
    echo "[OK] removed injected script line in $T"
  fi
fi

# new module JS is not needed; keep backup but disable by rename
if [ -f "$JSNEW" ]; then
  mv -f "$JSNEW" "${JSNEW}.disabled_${TS}" || true
  echo "[OK] disabled $JSNEW"
fi

echo "== [1] recover service =="
sudo systemctl reset-failed "$SVC" 2>/dev/null || true
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || echo "[WARN] service not active yet"

echo "== [2] quick probe /vsp5 =="
curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null && echo "[OK] /vsp5 200" || echo "[WARN] /vsp5 not ready yet"

echo "== [3] apply P2 filterbar patch directly into luxe dashboard JS =="
[ -f "$JSLUXE" ] || { echo "[ERR] missing $JSLUXE"; exit 2; }
cp -f "$JSLUXE" "${JSLUXE}.bak_p2filterbar_${TS}"
echo "[BACKUP] ${JSLUXE}.bak_p2filterbar_${TS}"

if grep -q "VSP_P2_FILTERBAR_V1" "$JSLUXE"; then
  echo "[OK] already patched VSP_P2_FILTERBAR_V1"
else
cat >> "$JSLUXE" <<'JS'
/* ===== VSP_P2_FILTERBAR_V1 (luxe) ===== */
(function(){
  function ready(fn){ if(document.readyState!=="loading") fn(); else document.addEventListener("DOMContentLoaded", fn); }
  function qs(sel,root){ return (root||document).querySelector(sel); }

  function mount(){
    if (document.getElementById("vsp-p2-filterbar")) return;

    var nav = qs(".topnav.vsp5nav");
    var host = nav ? nav.parentNode : document.body;

    var bar = document.createElement("div");
    bar.id="vsp-p2-filterbar";
    bar.style.cssText="margin:10px 12px 0 12px;padding:10px 12px;border:1px solid #333;border-radius:12px;background:#0f1218;color:#ddd;font:12px/1.2 monospace;display:flex;gap:10px;align-items:center;flex-wrap:wrap";
    bar.innerHTML =
      '<span style="opacity:.9">FILTER</span>' +
      '<select id="vsp-p2-sev" style="background:#111;border:1px solid #333;color:#ddd;border-radius:10px;padding:6px 10px">' +
        '<option value="">severity=ALL</option>' +
        '<option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>' +
      '</select>' +
      '<input id="vsp-p2-q" placeholder="search title/file/tool/cwe" style="min-width:260px;background:#111;border:1px solid #333;color:#ddd;border-radius:10px;padding:6px 10px" />' +
      '<button id="vsp-p2-apply" style="background:#111;border:1px solid #333;color:#bfffe8;border-radius:10px;padding:6px 10px;cursor:pointer">Apply → Data Source</button>' +
      '<button id="vsp-p2-clear" style="background:#111;border:1px solid #333;color:#ffe6bf;border-radius:10px;padding:6px 10px;cursor:pointer">Clear</button>';

    if (nav && nav.nextSibling) host.insertBefore(bar, nav.nextSibling);
    else host.insertBefore(bar, host.firstChild);

    function go(){
      var sev = (qs("#vsp-p2-sev")||{}).value || "";
      var q = (qs("#vsp-p2-q")||{}).value || "";
      var url = new URL("/data_source", window.location.origin);
      if (sev) url.searchParams.set("severity", sev);
      if (q) url.searchParams.set("q", q);
      window.location.href = url.toString();
    }

    qs("#vsp-p2-apply").addEventListener("click", go);
    qs("#vsp-p2-clear").addEventListener("click", function(){
      qs("#vsp-p2-sev").value="";
      qs("#vsp-p2-q").value="";
    });

    // Quick drilldown: Ctrl+click any severity word → Data Source severity
    document.addEventListener("click", function(e){
      if(!e.ctrlKey) return;
      var t=(e.target && e.target.textContent || "").trim().toUpperCase();
      var S=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      if(S.indexOf(t)>=0){
        var url = new URL("/data_source", window.location.origin);
        url.searchParams.set("severity", t);
        window.location.href=url.toString();
      }
    }, true);
  }

  ready(mount);
})();
JS
  echo "[OK] appended VSP_P2_FILTERBAR_V1 into $JSLUXE"
fi

echo "== [4] done =="
echo "[OK] Open: $BASE/vsp5  (filter bar under topnav)"
