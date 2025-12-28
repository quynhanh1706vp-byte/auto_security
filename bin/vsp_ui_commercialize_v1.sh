#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "[ROOT] $ROOT"

# ----------------------------
# 1) FIX: add FS runs_index endpoint via Blueprint (robust)
# ----------------------------
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_commercialize_${TS}"
echo "[BACKUP] $F.bak_commercialize_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Remove any old injected block
txt = re.sub(r'(?s)# === RUNS_INDEX_FS_V1 ===.*?# === END RUNS_INDEX_FS_V1 ===\n?', '', txt)
txt = re.sub(r'(?m)^\s*# === RUNS_INDEX_FS_REGISTER_V1 ===.*?^\s*# === END RUNS_INDEX_FS_REGISTER_V1 ===\s*$\n?', '', txt, flags=re.S)

# Ensure Blueprint imported
if "Blueprint" not in txt:
    # Try multiline from flask import ( ... )
    m = re.search(r'(?s)from\s+flask\s+import\s*\((.*?)\)\s*\n', txt)
    if m:
        inner = m.group(1)
        if "Blueprint" not in inner:
            inner2 = inner.rstrip() + ", Blueprint"
            txt = txt[:m.start(1)] + inner2 + txt[m.end(1):]
    else:
        # single-line from flask import ...
        m2 = re.search(r'(?m)^from\s+flask\s+import\s+(.+)$', txt)
        if m2 and "Blueprint" not in m2.group(1):
            txt = txt[:m2.end()] + ", Blueprint" + txt[m2.end():]
        else:
            # fallback: add a new import line
            txt = "from flask import Blueprint\n" + txt

# Also ensure request/jsonify exist
for need in ("request","jsonify"):
    if re.search(r'(?m)^from\s+flask\s+import\b', txt) and need not in txt:
        # add to multiline if exists; else to single line
        m = re.search(r'(?s)from\s+flask\s+import\s*\((.*?)\)\s*\n', txt)
        if m:
            inner = m.group(1)
            if need not in inner:
                inner2 = inner.rstrip() + f", {need}"
                txt = txt[:m.start(1)] + inner2 + txt[m.end(1):]
        else:
            m2 = re.search(r'(?m)^from\s+flask\s+import\s+(.+)$', txt)
            if m2 and need not in m2.group(1):
                txt = txt[:m2.end()] + f", {need}" + txt[m2.end():]

# Build blueprint block (no dependency on app existing)
block = r'''
# === RUNS_INDEX_FS_V1 ===
import os, json, time
from pathlib import Path as _Path

vsp_runs_fs_bp = Blueprint("vsp_runs_fs_bp", __name__)

def _runsfs_safe_load_json(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return json.load(f)
    except Exception:
        return None

def _runsfs_pick_runs(out_root, limit=50):
    items = []
    try:
        for name in os.listdir(out_root):
            if not name.startswith("RUN_"):
                continue
            run_dir = os.path.join(out_root, name)
            if not os.path.isdir(run_dir):
                continue
            rpt = os.path.join(run_dir, "report")
            summary = os.path.join(rpt, "summary_unified.json")
            st = os.stat(run_dir)
            created_at = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(st.st_mtime))
            meta = _runsfs_safe_load_json(os.path.join(run_dir, "ci_source_meta.json")) or {}
            s = _runsfs_safe_load_json(summary) or {}
            bysev = (s.get("summary_by_severity") or s.get("by_severity") or {})
            items.append({
                "run_id": name,
                "created_at": created_at,
                "profile": (meta.get("profile") or s.get("profile") or ""),
                "target": (meta.get("target") or s.get("target") or ""),
                "totals": bysev if isinstance(bysev, dict) else {},
            })
    except Exception:
        pass
    items.sort(key=lambda x: x.get("created_at",""), reverse=True)
    return items[:max(1, int(limit))]

@vsp_runs_fs_bp.get("/api/vsp/runs_index_v3_fs")
def vsp_runs_index_v3_fs():
    limit = request.args.get("limit", "40")
    try:
        limit_i = max(1, min(500, int(limit)))
    except Exception:
        limit_i = 40
    ui_root = _Path(__file__).resolve().parents[1]  # .../ui
    bundle_root = ui_root.parent                    # .../SECURITY_BUNDLE
    out_dir = bundle_root / "out"
    items = _runsfs_pick_runs(str(out_dir), limit_i)
    kpi = {"total_runs": len(items), "last_n": min(20, len(items))}
    return jsonify({"ok": True, "source": "fs", "items": items, "kpi": kpi})
# === END RUNS_INDEX_FS_V1 ===
'''

# Insert block after flask imports (best effort)
if "RUNS_INDEX_FS_V1" not in txt:
    m_imp = re.search(r'(?s)from\s+flask\s+import\s*\(.*?\)\s*\n', txt) or re.search(r'(?m)^from\s+flask\s+import\s+.*\n', txt)
    if m_imp:
        ins = m_imp.end()
        txt = txt[:ins] + "\n" + block + "\n" + txt[ins:]
    else:
        txt = block + "\n" + txt

# Register blueprint after app = Flask(...)
m_app = re.search(r'(?m)^\s*app\s*=\s*Flask\([^)]*\)\s*$', txt)
if m_app and "RUNS_INDEX_FS_REGISTER_V1" not in txt:
    reg = "\n# === RUNS_INDEX_FS_REGISTER_V1 ===\ntry:\n    app.register_blueprint(vsp_runs_fs_bp)\nexcept Exception as _e:\n    pass\n# === END RUNS_INDEX_FS_REGISTER_V1 ===\n"
    txt = txt[:m_app.end()] + reg + txt[m_app.end():]

p.write_text(txt, encoding="utf-8")
print("[OK] patched vsp_demo_app.py: add runs_index_v3_fs + register blueprint")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] python syntax OK"

# ----------------------------
# 2) Switch JS calls runs_index_v3 -> runs_index_v3_fs (stop ERR_EMPTY_RESPONSE)
# ----------------------------
python3 - << 'PY'
from pathlib import Path
import re

root = Path("static/js")
targets = []
for p in root.glob("*.js"):
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "runs_index_v3" in txt and "runs_index_v3_fs" not in txt:
        targets.append(p)

for p in targets:
    bak = p.with_suffix(p.suffix + ".bak_runsfs")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    txt = bak.read_text(encoding="utf-8", errors="replace")
    txt = txt.replace("/api/vsp/runs_index_v3?", "/api/vsp/runs_index_v3_fs?")
    txt = txt.replace("runs_index_v3?limit", "runs_index_v3_fs?limit")
    p.write_text(txt, encoding="utf-8")
    print("[OK] patched", p.name)
print("[DONE] JS runs_index -> FS")
PY

# ----------------------------
# 3) Disable legacy runs filters (spams "Không tìm thấy pane Runs")
# ----------------------------
if [ -f static/js/vsp_runs_filters_advanced_v1.js ]; then
  cp static/js/vsp_runs_filters_advanced_v1.js static/js/vsp_runs_filters_advanced_v1.js.bak_disable_${TS}
  python3 - << 'PY'
from pathlib import Path
p = Path("static/js/vsp_runs_filters_advanced_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")
if "VSP_DISABLE_RUNS_FILTERS_V1" not in txt:
    txt = "(function(){/*VSP_DISABLE_RUNS_FILTERS_V1*/return;})();\n" + txt
    p.write_text(txt, encoding="utf-8")
    print("[OK] disabled vsp_runs_filters_advanced_v1.js")
else:
    print("[SKIP] already disabled")
PY
fi

# ----------------------------
# 4) Disable duplicate scan UI v3 & mount hook (keep commercial panel)
# ----------------------------
for f in static/js/vsp_runs_trigger_scan_ui_v3.js static/js/vsp_runs_trigger_scan_mount_hook_v1.js; do
  if [ -f "$f" ]; then
    cp "$f" "$f.bak_disable_${TS}"
    python3 - << PY
from pathlib import Path
p = Path("$f")
txt = p.read_text(encoding="utf-8", errors="replace")
if "VSP_DISABLE_DUP_SCAN_V1" not in txt:
    txt = "(function(){/*VSP_DISABLE_DUP_SCAN_V1*/return;})();\n" + txt
    p.write_text(txt, encoding="utf-8")
    print("[OK] disabled", p.name)
else:
    print("[SKIP] already disabled", p.name)
PY
  fi
done

# ----------------------------
# 5) Settings: stop injecting RUN/DAST block (keep Settings clean)
# ----------------------------
if [ -f static/js/vsp_settings_advanced_v1.js ]; then
  cp static/js/vsp_settings_advanced_v1.js static/js/vsp_settings_advanced_v1.js.bak_norundast_${TS}
  python3 - << 'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_settings_advanced_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")
if "VSP_SETTINGS_DISABLE_RUNDAST_V1" not in txt:
    # crude but effective: if script contains "Injecting RUN/DAST block", short-circuit before that log
    txt = re.sub(r'(?m)^(.*Injecting RUN/DAST block.*)$', r'// VSP_SETTINGS_DISABLE_RUNDAST_V1\nreturn;\n\1', txt, count=1)
    if "VSP_SETTINGS_DISABLE_RUNDAST_V1" not in txt:
        # fallback: disable entire file
        txt = "(function(){/*VSP_SETTINGS_DISABLE_RUNDAST_V1*/return;})();\n" + txt
    p.write_text(txt, encoding="utf-8")
    print("[OK] Settings RUN/DAST injection disabled")
else:
    print("[SKIP] already disabled")
PY
fi

# ----------------------------
# 6) Dashboard: fix charts timing + object KPI
# ----------------------------
if [ -f static/js/vsp_dashboard_enhance_v1.js ]; then
  cp static/js/vsp_dashboard_enhance_v1.js static/js/vsp_dashboard_enhance_v1.js.bak_dashfix_${TS}
  python3 - << 'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_dashboard_enhance_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")

# insert safeText helper once
if "VSP_DASH_SAFE_TEXT_V1" not in txt:
    ins_at = txt.find("'use strict';")
    if ins_at != -1:
        ins_at = ins_at + len("'use strict';")
        helper = r"""

  // === VSP_DASH_SAFE_TEXT_V1 ===
  function safeText(v){
    if (v === null || v === undefined) return '-';
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'object'){
      return String(v.id || v.cwe || v.name || v.path || v.file || v.rule || JSON.stringify(v));
    }
    return String(v);
  }
  // === END VSP_DASH_SAFE_TEXT_V1 ===
"""
        txt = txt[:ins_at] + helper + txt[ins_at:]

# patch direct assignments for top-cwe/top-module if present
txt = re.sub(r'(getElementById\(["\']vsp-kpi-top-cwe["\']\)\.textContent\s*=\s*)([^;]+);', r'\1safeText(\2);', txt)
txt = re.sub(r'(getElementById\(["\']vsp-kpi-top-module["\']\)\.textContent\s*=\s*)([^;]+);', r'\1safeText(\2);', txt)

# add charts retry when engine loads after enhance
if "VSP_DASH_CHARTS_RETRY_V1" not in txt:
    txt = txt.replace(
        "No charts engine V2/V3 found – only KPIs filled.",
        "No charts engine V2/V3 found – only KPIs filled. (will retry)"
    )
    # append retry block near end of hydrateDashboard (best effort)
    txt = txt + r"""

// === VSP_DASH_CHARTS_RETRY_V1 ===
(function(){
  try{
    let tries = 0;
    function tryHydrate(){
      tries++;
      const eng = window.VSP_CHARTS_V3 || window.VSP_CHARTS_PRETTY_V3 || window.VSP_CHARTS_ENGINE_V3;
      if (eng && typeof eng.hydrate === 'function' && window.__VSP_LAST_DASH_DATA__){
        eng.hydrate(window.__VSP_LAST_DASH_DATA__);
        console.log('[VSP_DASH] charts hydrated via retry');
        return;
      }
      if (tries < 8) setTimeout(tryHydrate, 300);
    }
    setTimeout(tryHydrate, 300);
  }catch(e){}
})();
// === END VSP_DASH_CHARTS_RETRY_V1 ===
"""
# also store last dash data when fetched (best effort)
if "__VSP_LAST_DASH_DATA__" not in txt:
    txt = txt.replace("console.log('[VSP_DASH] dashboard_v3 data =", "window.__VSP_LAST_DASH_DATA__ = data;\n    console.log('[VSP_DASH] dashboard_v3 data =")
p.write_text(txt, encoding="utf-8")
print("[OK] dashboard enhance patched (safeText + charts retry)")
PY
fi

# ----------------------------
# 7) Restart UI + smoke checks
# ----------------------------
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "=== UI LOG (last 40) ==="
tail -n 40 out_ci/ui_8910.log || true

echo "=== Smoke: runs_index_v3_fs ==="
curl -s "http://localhost:8910/api/vsp/runs_index_v3_fs?limit=3" | head -c 400; echo

echo "=== Smoke: dashboard_v3 ==="
curl -s "http://localhost:8910/api/vsp/dashboard_v3" | head -c 200; echo

echo "[DONE] commercialize_v1"
