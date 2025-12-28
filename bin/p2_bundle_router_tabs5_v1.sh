#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_bundle_tabs5_v1.js"
mkdir -p static/js

cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true
echo "[BACKUP] ${JS}.bak_${TS} (if existed)"

cat > "$JS" <<'JS'
/* VSP_P2_BUNDLE_TABS5_V1
 * Router-bundle: load page modules by route, keep templates minimal:
 * Only include: vsp_tabs4_autorid_v1.js + this file.
 */
(function(){
  "use strict";

  function log(){ try{ console.log.apply(console, arguments); }catch(e){} }
  function warn(){ try{ console.warn.apply(console, arguments); }catch(e){} }

  function getAssetV(){
    // Try to reuse existing ?v=<digits> from any script tag.
    var scripts = document.getElementsByTagName("script");
    for (var i=0;i<scripts.length;i++){
      var src = scripts[i].getAttribute("src") || "";
      var m = src.match(/[?&]v=([0-9]{6,})/);
      if (m) return m[1];
    }
    return "";
  }

  function withV(url){
    var v = getAssetV();
    if(!v) return url;
    return url + (url.indexOf("?")>=0 ? "&" : "?") + "v=" + encodeURIComponent(v);
  }

  function loadScript(url){
    return new Promise(function(resolve, reject){
      var s = document.createElement("script");
      s.defer = true;
      s.src = withV(url);
      s.onload = function(){ resolve(url); };
      s.onerror = function(){ reject(new Error("load fail: "+url)); };
      document.head.appendChild(s);
    });
  }

  function exists(url){
    // Avoid noisy 404s: HEAD first (fallback GET if HEAD not allowed)
    var u = withV(url);
    return fetch(u, { method: "HEAD", credentials: "same-origin", cache: "no-store" })
      .then(function(r){
        if(r && r.ok) return true;
        if(r && (r.status === 405 || r.status === 403)) {
          return fetch(u, { method: "GET", credentials: "same-origin", cache: "no-store" })
            .then(function(r2){ return !!(r2 && r2.ok); })
            .catch(function(){ return false; });
        }
        return false;
      })
      .catch(function(){ return false; });
  }

  function loadIfExists(url){
    return exists(url).then(function(ok){
      if(!ok) return false;
      return loadScript(url).then(function(){ return true; }).catch(function(){ return false; });
    });
  }

  function pickRoute(){
    var p = (location.pathname || "/").toLowerCase();
    // normalize
    if (p === "/" || p === "/index") return "/vsp5";
    return p;
  }

  // Candidate modules: router will only load ones that exist.
  var ROUTES = {
    "/vsp5": [
      "/static/js/vsp_dash_only_v1.js",
      "/static/js/vsp_dashboard_kpi_force_any_v1.js",
      "/static/js/vsp_dashboard_gate_story_v1.js",
      "/static/js/vsp_dashboard_charts_pretty_v3.js"
    ],
    "/runs": [
      "/static/js/vsp_runs_reports_overlay_v1.js",
      "/static/js/vsp_runs_quick_actions_v1.js",
      "/static/js/vsp_runs_tab_resolved_v1.js"
    ],
    "/settings": [
      "/static/js/vsp_settings_tab_v1.js"
    ],
    "/data_source": [
      "/static/js/vsp_data_source_lazy_v1.js"
    ],
    "/rule_overrides": [
      "/static/js/vsp_rule_overrides_v1.js"
    ]
  };

  var route = pickRoute();
  var list = ROUTES[route] || [];
  if(!list.length){
    warn("[BundleTabs5] no modules mapped for route:", route);
    return;
  }

  log("[BundleTabs5] route=", route, "candidates=", list.length);

  // Load sequentially to keep deterministic order
  (function seq(i){
    if(i >= list.length){
      log("[BundleTabs5] done route=", route);
      return;
    }
    loadIfExists(list[i]).then(function(loaded){
      if(loaded) log("[BundleTabs5] loaded:", list[i]);
      seq(i+1);
    });
  })(0);

})();
JS

# Optional syntax check
if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check $JS"
fi

python3 - <<'PY'
from pathlib import Path
import re, shutil, time

TS = time.strftime("%Y%m%d_%H%M%S")
tpl_dir = Path("templates")
assert tpl_dir.is_dir(), "[ERR] templates/ not found"

bundle_name = "vsp_bundle_tabs5_v1.js"
autorid_re = re.compile(r'(<script[^>]+src="/static/js/vsp_tabs4_autorid_v1\.js[^"]*"[^>]*>\s*</script>)', re.I)
v_digits_re = re.compile(r'vsp_tabs4_autorid_v1\.js\?v=([0-9]{6,})', re.I)

# remove any other /static/js/vsp_*.js scripts except autorid + bundle
rm_other_vsp_re = re.compile(
  r'\n?\s*<script[^>]+src="/static/js/(?!vsp_tabs4_autorid_v1\.js)(?!' + re.escape(bundle_name) + r')vsp_[^"]+"[^>]*>\s*</script>\s*',
  re.I
)

patched = []
for p in sorted(tpl_dir.glob("*.html")):
  s = p.read_text(encoding="utf-8", errors="ignore")
  if "vsp_tabs4_autorid_v1.js" not in s:
    continue

  bak = p.with_suffix(p.suffix + f".bak_p2bundle_{TS}")
  shutil.copy2(p, bak)

  s2 = rm_other_vsp_re.sub("\n", s)

  # Ensure bundle include exists right after autorid include
  if bundle_name not in s2:
    # try to reuse digits v=... if present
    m = v_digits_re.search(s2)
    if m:
      bsrc = f'/static/js/{bundle_name}?v={m.group(1)}'
    else:
      # fallback to templated asset_v (should be rendered by your runtime asset_v patch)
      bsrc = f'/static/js/{bundle_name}?v={{% raw %}}{{{{ asset_v|default("") }}}}{{% endraw %}}'
      # We intentionally keep it safe: if your templates already render digits, this branch won't hit.

    insert = r'\1\n<script defer src="' + bsrc + r'"></script>'
    s2, n = autorid_re.subn(insert, s2, count=1)
    if n != 1:
      raise SystemExit(f"[ERR] cannot locate autorid script tag to insert bundle in {p}")

  p.write_text(s2, encoding="utf-8")
  patched.append(p.name)

print("[OK] patched templates:", patched)
PY

# Restart service (ignore if not systemd)
systemctl restart "$SVC" 2>/dev/null || true

# Self-check: pages reachable + no token dirt + only 2 vsp scripts
echo "== [SELF-CHECK] tabs5 pages + script includes =="
pages=(/vsp5 /runs /settings /data_source /rule_overrides)
for P in "${pages[@]}"; do
  echo "-- $P --"
  HTML="$(curl -fsS "$BASE$P")"
  echo "$HTML" | grep -q "vsp_tabs4_autorid_v1.js" || { echo "[ERR] missing autorid on $P"; exit 3; }
  echo "$HTML" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on $P"; exit 3; }
  # ensure no other vsp_ js includes
  OTHER="$(echo "$HTML" | grep -oE 'static/js/vsp_[a-zA-Z0-9_]+\.js' | sort -u | tr '\n' ' ')"
  # allow exactly autorid + bundle (bundle name does not start with vsp_? it does, so count carefully)
  # We'll hard-check absence of vsp_*.js except autorid and bundle.
  BAD="$(echo "$HTML" | grep -oE 'static/js/vsp_[a-zA-Z0-9_]+\.js' | sort -u | grep -vE 'vsp_tabs4_autorid_v1\.js|vsp_bundle_tabs5_v1\.js' || true)"
  if [ -n "$BAD" ]; then
    echo "[ERR] extra vsp js on $P:"
    echo "$BAD"
    exit 3
  fi
  # token dirt check
  echo "$HTML" | grep -q "{{" && { echo "[ERR] token dirt '{{' on $P"; exit 3; } || true
  echo "$HTML" | grep -q "}}" && { echo "[ERR] token dirt '}}' on $P"; exit 3; } || true
  echo "[OK] $P"
done

echo "[DONE] VSP_P2_BUNDLE_TABS5_V1 applied OK"
