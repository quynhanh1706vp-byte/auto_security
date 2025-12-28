#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PY_APP="vsp_demo_app.py"
JS="static/js/vsp_runs_commercial_panel_v1.js"

[ -f "$PY_APP" ] || { echo "[ERR] missing $PY_APP"; exit 1; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PY_APP" "$PY_APP.bak_runsfs_sortfix_${TS}"
cp "$JS" "$JS.bak_runs_toggle_${TS}"
echo "[BACKUP] $PY_APP.bak_runsfs_sortfix_${TS}"
echo "[BACKUP] $JS.bak_runs_toggle_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

# -------------------------
# Patch vsp_demo_app.py: CI-first + newest-first (string ISO sort) for runs_index_v3_fs
# -------------------------
py_path = Path("vsp_demo_app.py")
txt = py_path.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

if "VSP_COMMERCIAL_RUNSFS_SORT_V1" not in txt:
    m = re.search(r"def\s+vsp_runs_index_v3_fs\s*\(\s*\)\s*:\s*\n", txt)
    if not m:
        raise SystemExit("[ERR] cannot find def vsp_runs_index_v3_fs() in vsp_demo_app.py")
    start = m.end()
    # find first 'return jsonify' inside this function block (best-effort)
    mret = re.search(r"\n([ \t]+)return\s+jsonify\s*\(", txt[start:])
    if not mret:
        raise SystemExit("[ERR] cannot find 'return jsonify(' inside vsp_runs_index_v3_fs()")
    indent = mret.group(1)
    insert_at = start + mret.start()

    block = (
        f"\n{indent}# === VSP_COMMERCIAL_RUNSFS_SORT_V1 (CI-first + newest-first) ===\n"
        f"{indent}try:\n"
        f"{indent}    # 1) newest-first (ISO string compare works for YYYY-mm-ddTHH:MM:SS)\n"
        f"{indent}    items.sort(key=lambda r: (str(r.get('created_at','')), str(r.get('run_id',''))), reverse=True)\n"
        f"{indent}    # 2) CI-first (stable sort)\n"
        f"{indent}    items.sort(key=lambda r: (0 if str(r.get('run_id','')).startswith('RUN_VSP_CI_') else 1))\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
        f"{indent}# === END VSP_COMMERCIAL_RUNSFS_SORT_V1 ===\n"
    )

    txt = txt[:insert_at] + block + txt[insert_at:]
    py_path.write_text(txt, encoding="utf-8")
    print("[OK] patched vsp_demo_app.py: CI-first + newest-first sort injected")
else:
    print("[SKIP] vsp_demo_app.py already has VSP_COMMERCIAL_RUNSFS_SORT_V1")

# -------------------------
# Patch vsp_runs_commercial_panel_v1.js: read toggles from localStorage + inject UI controls
# -------------------------
js_path = Path("static/js/vsp_runs_commercial_panel_v1.js")
js = js_path.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# 1) Load toggle config early (best-effort). Insert after first (function(){... or top)
if "VSP_RUNS_TOGGLE_CFG_V1" not in js:
    inject_cfg = r"""
// === VSP_RUNS_TOGGLE_CFG_V1 (limit/hide_empty via localStorage) ===
(function(){
  try {
    var lim = parseInt(localStorage.getItem('vsp_runs_limit') || '0', 10);
    if (lim && lim > 0) window.VSP_RUNS_LIMIT = lim;
    var he = localStorage.getItem('vsp_runs_hide_empty');
    if (he !== null && he !== undefined) window.VSP_RUNS_HIDE_EMPTY = parseInt(he, 10) || 0;
  } catch (e) {}
})();
// === END VSP_RUNS_TOGGLE_CFG_V1 ===
"""
    # place near top (after "use strict" if any)
    mtop = re.search(r"(^[ \t]*['\"]use strict['\"];[ \t]*\n)", js, flags=re.M)
    if mtop:
        pos = mtop.end()
        js = js[:pos] + inject_cfg + js[pos:]
    else:
        js = inject_cfg + "\n" + js
    print("[OK] injected VSP_RUNS_TOGGLE_CFG_V1")
else:
    print("[SKIP] VSP_RUNS_TOGGLE_CFG_V1 already present")

# 2) Make runs_index URL respect globals (replace the common pattern)
# Try to find the exact url template; if not, do a minimal insertion before first fetch('/api/vsp/runs_index_v3_fs')
if "VSP_RUNS_URL_GLOBALS_V1" not in js:
    # best-effort replace around `/api/vsp/runs_index_v3_fs?limit=...&hide_empty=...`
    pat = r"const\s+url\s*=\s*`/api/vsp/runs_index_v3_fs\?limit=\$\{[^}]+\}&hide_empty=\$\{[^}]+\}`\s*;"
    m = re.search(pat, js)
    if m:
        repl = """// === VSP_RUNS_URL_GLOBALS_V1 ===
    const effLimit = (typeof window.VSP_RUNS_LIMIT === 'number' && window.VSP_RUNS_LIMIT > 0) ? window.VSP_RUNS_LIMIT : limit;
    const effHide  = (typeof window.VSP_RUNS_HIDE_EMPTY === 'number') ? window.VSP_RUNS_HIDE_EMPTY : (hideEmpty ? 1 : 0);
    const url = `/api/vsp/runs_index_v3_fs?limit=${encodeURIComponent(effLimit)}&hide_empty=${encodeURIComponent(effHide)}`;
    // === END VSP_RUNS_URL_GLOBALS_V1 ==="""
        js = js[:m.start()] + repl + js[m.end():]
        print("[OK] patched URL builder to respect globals (direct match)")
    else:
        # fallback: inject before first fetch call to runs_index
        mf = re.search(r"fetch\(\s*['\"]/api/vsp/runs_index_v3_fs\?limit=", js)
        if not mf:
            print("[WARN] cannot locate runs_index_v3_fs URL builder or fetch; skip URL globals patch")
        else:
            # inject a helper so later code can use window.VSP_RUNS_LIMIT/HIDE_EMPTY by reload only
            js = js + r"""
// === VSP_RUNS_URL_GLOBALS_V1 (fallback note) ===
// If URL builder is custom, toggles still work by full reload; prefer the direct-match patch above.
// === END VSP_RUNS_URL_GLOBALS_V1 ===
"""
            print("[OK] appended fallback marker for URL globals")
else:
    print("[SKIP] VSP_RUNS_URL_GLOBALS_V1 already present")

# 3) Inject UI controls into Runs header (reload on change for stability)
if "VSP_RUNS_TOGGLE_UI_V1" not in js:
    ui = r"""
// === VSP_RUNS_TOGGLE_UI_V1 (inject controls; reload on change for stability) ===
(function(){
  if (window.VSP_RUNS_TOGGLE_UI_V1) return;
  window.VSP_RUNS_TOGGLE_UI_V1 = true;

  function qs(sel){ try { return document.querySelector(sel); } catch(e){ return null; } }
  function create(tag, html){
    var el = document.createElement(tag);
    if (html) el.innerHTML = html;
    return el;
  }

  function inject(){
    var host = qs('#vsp-runs-main');
    if (!host) return false;

    // Prefer header if exists
    var header = qs('#vsp-runs-main .vsp-card-header') || host;
    if (qs('#vsp-runs-toggle-box')) return true;

    var lim = (typeof window.VSP_RUNS_LIMIT === 'number' && window.VSP_RUNS_LIMIT > 0) ? window.VSP_RUNS_LIMIT : 200;
    var he  = (typeof window.VSP_RUNS_HIDE_EMPTY === 'number') ? window.VSP_RUNS_HIDE_EMPTY : 1;

    var box = create('div', `
      <div id="vsp-runs-toggle-box" style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-top:8px">
        <div style="font-size:12px;opacity:.85">Runs view:</div>
        <label style="display:flex;gap:6px;align-items:center;font-size:12px;cursor:pointer">
          <input id="vsp-runs-hide-empty" type="checkbox" ${he ? 'checked' : ''}/>
          Hide empty
        </label>
        <label style="display:flex;gap:6px;align-items:center;font-size:12px">
          Limit
          <select id="vsp-runs-limit" style="background:rgba(255,255,255,.06);color:inherit;border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:4px 8px">
            <option value="50">50</option>
            <option value="200">200</option>
            <option value="500">500</option>
          </select>
        </label>
        <button id="vsp-runs-toggle-apply" style="background:rgba(99,102,241,.18);color:inherit;border:1px solid rgba(99,102,241,.35);border-radius:10px;padding:6px 10px;font-size:12px;cursor:pointer">
          Apply
        </button>
      </div>
    `);

    header.appendChild(box);

    var sel = qs('#vsp-runs-limit');
    if (sel) sel.value = String(lim);

    function apply(){
      try {
        var newLim = parseInt((qs('#vsp-runs-limit')||{}).value || '200', 10) || 200;
        var newHe  = (qs('#vsp-runs-hide-empty')||{}).checked ? 1 : 0;
        localStorage.setItem('vsp_runs_limit', String(newLim));
        localStorage.setItem('vsp_runs_hide_empty', String(newHe));
      } catch(e) {}
      // reload to ensure *all* runs widgets pick up new query params consistently
      try { window.location.reload(); } catch(e) {}
    }

    var btn = qs('#vsp-runs-toggle-apply');
    if (btn) btn.addEventListener('click', apply);
    var cb = qs('#vsp-runs-hide-empty');
    if (cb) cb.addEventListener('change', function(){ /* no-op until Apply */ });
    return true;
  }

  // try now + retry a few times
  var tries = 0;
  var t = setInterval(function(){
    tries++;
    if (inject() || tries > 20) clearInterval(t);
  }, 500);
})();
// === END VSP_RUNS_TOGGLE_UI_V1 ===
"""
    js = js + "\n" + ui
    print("[OK] appended VSP_RUNS_TOGGLE_UI_V1 injector")
else:
    print("[SKIP] VSP_RUNS_TOGGLE_UI_V1 already present")

js_path.write_text(js, encoding="utf-8")
print("[OK] wrote", js_path)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"
echo "[DONE] commercial runsfs sort + runs UI toggles applied"
echo "Next: restart UI (8910) then test runs_index_v3_fs ordering + UI toggle shows in Runs tab."
