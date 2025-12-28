#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

backup() { [ -f "$1" ] && cp -f "$1" "$1.bak_${TS}" && echo "[BACKUP] $1.bak_${TS}"; }

# --- (1) Fix effLimit redeclare in vsp_runs_commercial_panel_v1.js ---
F_RUNS="static/js/vsp_runs_commercial_panel_v1.js"
if [ -f "$F_RUNS" ]; then
  backup "$F_RUNS"
  python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_runs_commercial_panel_v1.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_FIX_EFFLIMIT_REDECLARE_V1 ==="
if TAG not in txt:
    # Replace any 'let effLimit' or 'const effLimit' with 'var effLimit'
    txt2 = re.sub(r"\b(let|const)\s+(effLimit)\b", r"var \2", txt)
    # Optional: if file is included twice, keep it isolated
    if not txt2.lstrip().startswith("(function"):
        txt2 = (
            f"{TAG}\n"
            "(function(){\n"
            "  try {\n"
            "    if (window.__VSP_GUARD__ && window.__VSP_GUARD__.RUNS_COMMERCIAL_PANEL_V1) return;\n"
            "    window.__VSP_GUARD__ = window.__VSP_GUARD__ || {};\n"
            "    window.__VSP_GUARD__.RUNS_COMMERCIAL_PANEL_V1 = true;\n"
            "  } catch(e) {}\n\n"
            + txt2 +
            "\n})();\n"
        )
    txt = txt2

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", p)
PY
else
  echo "[WARN] missing $F_RUNS"
fi

# --- (2) Charts engine bridge + (3) Header RID sync + (4) Dark inputs CSS ---
mkdir -p static/js static/css

F_BRIDGE="static/js/vsp_charts_engine_bridge_v1.js"
backup "$F_BRIDGE"
cat > "$F_BRIDGE" <<'JS'
/* vsp_charts_engine_bridge_v1.js
 * Goal: expose window.VSP_DASH_CHARTS_ENGINE so vsp_dashboard_enhance can render.
 */
(function(){
  'use strict';
  function pick() {
    try {
      var cand = [
        window.VSP_DASH_CHARTS_ENGINE,
        window.VSP_DASH_CHARTS_V3,
        window.VSP_DASH_CHARTS_V2,
        window.vsp_dashboard_charts_pretty_v3,
        window.vsp_dashboard_charts_v3,
        window.vsp_dashboard_charts_v2,
        window.VSP_CHARTS_V3,
        window.VSP_CHARTS_V2
      ].filter(Boolean)[0];

      if (!cand) return null;

      // Normalize to engine object
      if (typeof cand === 'function') {
        return { renderAll: cand, hydrate: cand };
      }
      if (typeof cand === 'object') {
        // common method names
        var r = cand.renderAll || cand.render || cand.hydrate || cand.run;
        if (typeof r === 'function') return cand;
      }
      return null;
    } catch(e){ return null; }
  }

  function attachIfPossible() {
    var eng = pick();
    if (!eng) return false;
    window.VSP_DASH_CHARTS_ENGINE = eng;
    try { console.log("[VSP_CHARTS_BRIDGE] engine attached:", eng); } catch(e){}
    return true;
  }

  // Try multiple times because scripts may load late
  var n = 0;
  var iv = setInterval(function(){
    n++;
    if (attachIfPossible() || n > 30) clearInterval(iv);
  }, 250);
})();
JS
echo "[OK] wrote $F_BRIDGE"

F_HDR="static/js/vsp_header_run_context_sync_v1.js"
backup "$F_HDR"
cat > "$F_HDR" <<'JS'
/* vsp_header_run_context_sync_v1.js
 * Sync top header rid + quick links to latest resolved run (commercial truth source).
 */
(function(){
  'use strict';

  async function fetchLatest() {
    const url = "/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1";
    const r = await fetch(url, {cache:"no-store"});
    const j = await r.json();
    if (!j || !j.ok || !j.items || !j.items.length) return null;
    return j.items[0];
  }

  function setLinkByText(txtNeedle, href) {
    const needles = (txtNeedle||"").toLowerCase();
    const as = Array.from(document.querySelectorAll("a"));
    for (const a of as) {
      const t = (a.textContent||"").trim().toLowerCase();
      if (t.includes(needles)) { a.setAttribute("href", href); return true; }
    }
    return false;
  }

  function patchHeaderRid(rid) {
    // replace occurrences like "rid=RUN_..." in topbar
    const nodes = Array.from(document.querySelectorAll("body *"));
    for (const el of nodes) {
      const t = (el.childElementCount===0 ? (el.textContent||"") : "");
      if (!t) continue;
      if (t.includes("rid=") && t.includes("RUN_")) {
        el.textContent = t.replace(/rid=RUN_[A-Z0-9_]+/g, "rid="+rid);
      }
    }
  }

  async function run() {
    try {
      const item = await fetchLatest();
      if (!item) return;

      const rid = item.run_id || item.req_id || item.request_id;
      if (!rid) return;

      patchHeaderRid(rid);

      // Update quick links (top right)
      setLinkByText("degraded_tools.json", "/api/vsp/run_artifact_v2?rid="+encodeURIComponent(rid)+"&path=degraded_tools.json");
      setLinkByText("artifacts index", "/api/vsp/run_artifacts_index_v1/"+encodeURIComponent(rid));
      setLinkByText("runner.log", "/api/vsp/run_artifact_v2?rid="+encodeURIComponent(rid)+"&path=runner.log");

      try { console.log("[VSP_HDR_SYNC] synced rid =>", rid); } catch(e){}
    } catch(e) {
      try { console.warn("[VSP_HDR_SYNC] failed", e); } catch(_){}
    }
  }

  document.addEventListener("DOMContentLoaded", function(){ setTimeout(run, 50); });
  window.addEventListener("hashchange", function(){ setTimeout(run, 50); });
})();
JS
echo "[OK] wrote $F_HDR"

F_CSS="static/css/vsp_inputs_dark_v1.css"
backup "$F_CSS"
cat > "$F_CSS" <<'CSS'
/* vsp_inputs_dark_v1.css - make filters/selects commercial dark */
select, input[type="text"], input[type="search"], input, textarea {
  background: rgba(9, 13, 30, 0.92) !important;
  color: #e5e7eb !important;
  border: 1px solid rgba(255,255,255,0.10) !important;
  border-radius: 10px !important;
  outline: none !important;
}
select:focus, input:focus, textarea:focus {
  border-color: rgba(96,165,250,0.55) !important;
  box-shadow: 0 0 0 2px rgba(96,165,250,0.18) !important;
}
::placeholder { color: rgba(229,231,235,0.55) !important; }
CSS
echo "[OK] wrote $F_CSS"

# --- Patch template includes (add CSS + 2 JS) ---
T_CANDIDATES=("templates/vsp_dashboard_2025.html" "templates/vsp_5tabs_full.html" "templates/vsp_layout_sidebar.html")
TPL=""
for t in "${T_CANDIDATES[@]}"; do [ -f "$t" ] && TPL="$t" && break; done
if [ -z "$TPL" ]; then
  echo "[WARN] template not found in common paths; add manually:"
  echo '  <link rel="stylesheet" href="/static/css/vsp_inputs_dark_v1.css">'
  echo '  <script src="/static/js/vsp_charts_engine_bridge_v1.js" defer></script>'
  echo '  <script src="/static/js/vsp_header_run_context_sync_v1.js" defer></script>'
  exit 0
fi

backup "$TPL"

python3 - <<PY
from pathlib import Path
import re
tpl = Path("$TPL")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

css = '<link rel="stylesheet" href="/static/css/vsp_inputs_dark_v1.css">'
js1 = '<script src="/static/js/vsp_charts_engine_bridge_v1.js" defer></script>'
js2 = '<script src="/static/js/vsp_header_run_context_sync_v1.js" defer></script>'

def ensure(tag):
    global txt
    if tag in txt: return
    if re.search(r"</head\s*>", txt, flags=re.I):
        txt = re.sub(r"(</head\s*>)", tag + "\\n\\1", txt, flags=re.I, count=1)
    elif re.search(r"</body\s*>", txt, flags=re.I):
        txt = re.sub(r"(</body\s*>)", tag + "\\n\\1", txt, flags=re.I, count=1)
    else:
        txt += "\\n" + tag + "\\n"

ensure(css)
ensure(js1)
ensure(js2)

tpl.write_text(txt, encoding="utf-8")
print("[OK] patched template:", tpl)
PY

echo "[DONE] patch_ui_commercial_hardening_v2 applied."
echo "Restart:"
echo "  sudo systemctl restart vsp-ui-8910.service"
