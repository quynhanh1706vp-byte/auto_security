#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PY_APP="vsp_demo_app.py"
JS="static/js/vsp_runs_commercial_panel_v1.js"

[ -f "$PY_APP" ] || { echo "[ERR] missing $PY_APP"; exit 1; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PY_APP" "$PY_APP.bak_runsfs_sort_${TS}"
cp "$JS" "$JS.bak_toggle_${TS}"
echo "[BACKUP] $PY_APP.bak_runsfs_sort_${TS}"
echo "[BACKUP] $JS.bak_toggle_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

# ---------- patch vsp_demo_app.py: sort CI-first + newest-first, limit AFTER sort ----------
p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP_COMMERCIAL_RUNS_FS_SORT_V1 ==="
if MARK in txt:
    print("[SKIP] runs fs sort marker already present")
else:
    m = re.search(r"(def\s+vsp_runs_index_v3_fs\s*\(\s*\)\s*:\n)", txt)
    if not m:
        raise SystemExit("[ERR] cannot find def vsp_runs_index_v3_fs() in vsp_demo_app.py")

    # Find the first 'return jsonify(' inside that function block and inject before it
    start = m.start(1)
    # naive block end: until next "\ndef " at same indentation (col 0)
    nxt = re.search(r"\n(?=def\s+\w+\s*\()", txt[m.end(1):])
    end = (m.end(1) + nxt.start()) if nxt else len(txt)
    block = txt[start:end]

    # detect list var name
    list_var = "items"
    if re.search(r"(?m)^\s*runs\s*=\s*\[\s*\]|\s*runs\.append\(", block):
        list_var = "runs"
    elif re.search(r"(?m)^\s*items\s*=\s*\[\s*\]|\s*items\.append\(", block):
        list_var = "items"

    # locate return jsonify
    rj = re.search(r"(?m)^\s*return\s+jsonify\s*\(", block)
    if not rj:
        # maybe flask.jsonify
        rj = re.search(r"(?m)^\s*return\s+flask\.jsonify\s*\(", block)
    if not rj:
        raise SystemExit("[ERR] cannot find return jsonify(...) inside vsp_runs_index_v3_fs()")

    inject = f"""
    {MARK}
    # Commercial sort: CI-first + newest-first (mtime fallback), and apply limit AFTER sort.
    try:
        import os, datetime
        _OUT = OUT_DIR if 'OUT_DIR' in globals() else os.path.join(ROOT, 'out')
        def _mtime(it):
            rid = (it.get('run_id') or '').strip()
            if not rid:
                return 0.0
            try:
                return os.path.getmtime(os.path.join(_OUT, rid))
            except Exception:
                return 0.0
        def _created_ts(it):
            s = (it.get('created_at') or '').strip()
            if not s:
                return 0.0
            # accept "2025-12-13T12:33:55" or "...Z"
            try:
                if s.endswith('Z'):
                    s2 = s[:-1]
                else:
                    s2 = s
                dt = datetime.datetime.fromisoformat(s2)
                return dt.timestamp()
            except Exception:
                return 0.0

        def _key(it):
            rid = (it.get('run_id') or '')
            ci_first = 0 if rid.startswith('RUN_VSP_CI_') else 1
            # newest first -> negative
            return (ci_first, -max(_created_ts(it), _mtime(it)), rid)

        {list_var}.sort(key=_key)
        try:
            {list_var} = {list_var}[:limit]
        except Exception:
            pass
    except Exception as _e:
        pass
    # === END VSP_COMMERCIAL_RUNS_FS_SORT_V1 ===
"""

    block2 = block[:rj.start()] + inject + block[rj.start():]
    txt2 = txt[:start] + block2 + txt[end:]
    p.write_text(txt2, encoding="utf-8")
    print("[OK] patched runs_index_v3_fs sort/limit: CI-first + newest-first")

# ---------- patch vsp_runs_commercial_panel_v1.js: add UI toggle + make URL respect globals ----------
js = Path("static/js/vsp_runs_commercial_panel_v1.js")
jst = js.read_text(encoding="utf-8", errors="ignore")

JMARK = "/* === VSP_COMMERCIAL_RUNS_UI_TOGGLE_V1 === */"
if JMARK in jst:
    print("[SKIP] runs UI toggle marker already present")
else:
    # patch URL builder line
    pat = r"const\s+url\s*=\s*`/api/vsp/runs_index_v3_fs\?limit=\$\{encodeURIComponent\(limit\)\}&hide_empty=\$\{hideEmpty\s*\?\s*1\s*:\s*0\}`;"
    rep = (
        "const effLimit = (window.VSP_RUNS_LIMIT ? Number(window.VSP_RUNS_LIMIT) : limit) || 50;\n"
        "    const effShowEmpty = !!window.VSP_RUNS_SHOW_EMPTY;\n"
        "    const url = `/api/vsp/runs_index_v3_fs?limit=${encodeURIComponent(effLimit)}&hide_empty=${effShowEmpty ? 0 : (hideEmpty ? 1 : 0)}`;"
    )
    if re.search(pat, jst):
        jst = re.sub(pat, rep, jst, count=1)
        print("[OK] patched runs_index url to respect globals")
    else:
        print("[WARN] cannot find exact url builder pattern; skipping url patch")

    # append toggle injector
    jst += "\n\n" + JMARK + r"""
(function () {
  if (window.VSP_COMMERCIAL_RUNS_UI_TOGGLE_V1) return;
  window.VSP_COMMERCIAL_RUNS_UI_TOGGLE_V1 = true;

  function injectControls() {
    var root = document.getElementById('vsp-runs-main');
    if (!root) return;

    if (root.querySelector('#vsp-runs-show-empty')) return;

    var bar = document.createElement('div');
    bar.style.cssText = "display:flex;gap:14px;align-items:center;justify-content:flex-end;margin:8px 0 12px 0;padding:8px 10px;border:1px solid rgba(255,255,255,.08);border-radius:12px;background:rgba(255,255,255,.03)";

    var showEmpty = !!window.VSP_RUNS_SHOW_EMPTY;
    var limit = (window.VSP_RUNS_LIMIT ? Number(window.VSP_RUNS_LIMIT) : 50) || 50;

    bar.innerHTML =
      '<label style="display:flex;gap:8px;align-items:center;font-size:12px;opacity:.95;cursor:pointer">' +
        '<input id="vsp-runs-show-empty" type="checkbox" ' + (showEmpty ? 'checked' : '') + ' />' +
        '<span>Show empty runs</span>' +
      '</label>' +
      '<label style="display:flex;gap:8px;align-items:center;font-size:12px;opacity:.95">' +
        '<span>Limit</span>' +
        '<select id="vsp-runs-limit" style="background:rgba(255,255,255,.06);color:inherit;border:1px solid rgba(255,255,255,.10);border-radius:10px;padding:4px 8px;">' +
          '<option value="50">50</option>' +
          '<option value="200">200</option>' +
          '<option value="500">500</option>' +
        '</select>' +
      '</label>';

    root.prepend(bar);
    var cb = bar.querySelector('#vsp-runs-show-empty');
    var sel = bar.querySelector('#vsp-runs-limit');
    sel.value = String(limit);

    function apply() {
      window.VSP_RUNS_SHOW_EMPTY = !!cb.checked;
      window.VSP_RUNS_LIMIT = Number(sel.value) || 50;

      // try soft refresh hooks first
      if (typeof window.VSP_RUNS_REFRESH === 'function') { window.VSP_RUNS_REFRESH(); return; }

      // try click refresh button if present
      var btn = root.querySelector('[data-action="refresh"], .vsp-btn-refresh, button[title*="Refresh"], button[title*="reload"]');
      if (btn) { btn.click(); return; }

      // fallback: reload hash/page
      try { location.hash = '#runs'; } catch (e) {}
      setTimeout(function(){ try{ location.hash = '#runs'; }catch(e){} }, 50);
      setTimeout(function(){ try{ location.reload(); }catch(e){} }, 150);
    }

    cb.addEventListener('change', apply);
    sel.addEventListener('change', apply);
  }

  document.addEventListener('DOMContentLoaded', function(){ setTimeout(injectControls, 200); });
  window.addEventListener('hashchange', function(){ setTimeout(injectControls, 120); });
  setTimeout(injectControls, 400);
})();
"""
    js.write_text(jst, encoding="utf-8")
    print("[OK] appended UI toggle injector")
PY

python3 -m py_compile "$PY_APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] patch runs fs sort + runs UI toggle"
