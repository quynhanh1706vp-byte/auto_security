#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

html="$(curl -fsS "$BASE/vsp5")"
mapfile -t js < <(echo "$html" | grep -oE '/static/js/[^"'"'"' ]+\.js(\?v=[0-9]+)?' | sed 's/\?.*$//' | awk '!seen[$0]++')
[ "${#js[@]}" -gt 0 ] || { echo "[ERR] cannot extract JS from /vsp5"; exit 2; }

pick=""
for u in "${js[@]}"; do
  b="$(basename "$u")"
  if echo "$b" | grep -qiE 'tabs|bundle'; then pick="$b"; break; fi
done
[ -n "$pick" ] || pick="$(basename "${js[0]}")"

F="static/js/$pick"
[ -f "$F" ] || { echo "[ERR] missing file: $F"; echo "JS candidates:"; printf '%s\n' "${js[@]}" | head; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_healthbadge_${TS}"
echo "[BACKUP] ${F}.bak_healthbadge_${TS}"
echo "[INFO] patch target=$F"

# idempotent append
if grep -q "VSP_HEALTH_BADGE_V1" "$F"; then
  echo "[OK] already patched"
else
cat >> "$F" <<'JS'

/* ===== VSP_HEALTH_BADGE_V1 ===== */
(function(){
  try{
    function ready(fn){ if(document.readyState!=="loading") fn(); else document.addEventListener("DOMContentLoaded", fn); }
    function el(tag, attrs){ var e=document.createElement(tag); if(attrs) for (var k in attrs) e.setAttribute(k, attrs[k]); return e; }

    function mount(){
      if(document.getElementById("vsp-health-badge")) return;
      var host = document.querySelector("header") || document.body;
      var wrap = el("div", {id:"vsp-health-badge", style:"position:fixed;top:10px;right:12px;z-index:9999;font:12px/1.2 monospace;padding:6px 10px;border-radius:10px;background:#111;border:1px solid #333;color:#ddd;opacity:0.95"});
      wrap.textContent = "HEALTH: ...";
      host.appendChild(wrap);

      fetch("/api/vsp/healthz", {cache:"no-store"})
        .then(function(r){ return r.json().then(function(j){ return {r:r,j:j}; }); })
        .then(function(x){
          var j=x.j||{};
          var ok = !!j.ok;
          var badge = document.getElementById("vsp-health-badge");
          if(!badge) return;
          badge.textContent = (ok ? "HEALTHY" : "DEGRADED") + " | asset_v=" + (j.asset_v||"-") + " | ts=" + (j.release_ts||"-");
          badge.style.borderColor = ok ? "#2a7" : "#a72";
          badge.style.color = ok ? "#bfffe8" : "#ffe6bf";
        })
        .catch(function(e){
          var badge = document.getElementById("vsp-health-badge");
          if(badge){ badge.textContent="HEALTH: UNKNOWN"; badge.style.borderColor="#a72"; }
        });
    }
    ready(mount);
  }catch(_){}
})();
JS
fi

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"
echo "[OK] open: $BASE/vsp5 (badge should appear top-right)"
