#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
JS="static/js/vsp_dashboard_cio_kpi_v1.js"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p963_${TS}"
mkdir -p "$OUT"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$APP" "$OUT/$(basename "$APP").bak_${TS}"
cp -f "$JS" "$OUT/$(basename "$JS").bak_${TS}"
echo "[OK] backups => $OUT"

echo "== [1] patch backend: add /api/vsp/kpi_counts_v1 =="
python3 - <<'PY'
from pathlib import Path
import re, json

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="### VSP_P963_KPI_COUNTS_V1 ###"
if marker in s:
    print("[OK] backend already patched")
    raise SystemExit(0)

# Ensure imports
if "from flask import" in s and "jsonify" not in s:
    s = re.sub(r"from flask import ([^\n]+)", lambda m: m.group(0)+", jsonify", s, count=1)
if "import json" not in s:
    s = "import json\n" + s

code = r'''
''' + marker + r'''
# KPI counts API: compute severity counts from run folder artifacts
try:
    from flask import jsonify, request
except Exception:
    pass

def _vsp_p963_find_run_dir(rid: str):
    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]
    for root in roots:
        d = Path(root) / rid
        if d.is_dir():
            return d, roots
    return None, roots

def _vsp_p963_extract_items(obj):
    # returns list of findings (best-effort)
    if obj is None:
        return []
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in ("items","findings","results","data","rows"):
            v = obj.get(k)
            if isinstance(v, list):
                return v
        # sometimes unified JSON is nested
        v = obj.get("unified") or obj.get("findings_unified")
        if isinstance(v, dict):
            for k in ("items","findings","results","rows"):
                vv = v.get(k)
                if isinstance(vv, list):
                    return vv
    return []

def _vsp_p963_sev(it):
    if not isinstance(it, dict):
        return ""
    for k in ("severity_norm","sev_norm","severity","sev","level","priority"):
        v = it.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip().upper()
    return ""

def _vsp_p963_counts_from_items(items):
    out = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
    for it in items:
        sev = _vsp_p963_sev(it)
        if sev in out:
            out[sev] += 1
    return out

@app.get("/api/vsp/kpi_counts_v1")
def api_vsp_kpi_counts_v1():
    rid = (request.args.get("rid") or "").strip()
    if not rid:
        return jsonify({"ok":False,"err":"missing rid","rid":"","counts":{}}), 400

    run_dir, roots = _vsp_p963_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":False,"err":"rid not found on disk","rid":rid,"roots":roots,"counts":{}}), 404

    cand = [
        run_dir / "reports" / "findings_unified_commercial.json",
        run_dir / "findings_unified_commercial.json",
        run_dir / "reports" / "findings_unified.json",
        run_dir / "findings_unified.json",
    ]

    chosen = None
    j = None
    j_err = ""
    for fp in cand:
        if fp.is_file() and fp.stat().st_size > 10:
            try:
                j = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
                chosen = str(fp)
                break
            except Exception as e:
                j_err = f"{fp.name}: {e}"
                continue

    if chosen is None or j is None:
        return jsonify({
            "ok": False,
            "err": "no usable json source",
            "rid": rid,
            "run_dir": str(run_dir),
            "checked": [str(x) for x in cand],
            "json_err": j_err,
            "counts": {},
        }), 200

    items = _vsp_p963_extract_items(j)
    counts = _vsp_p963_counts_from_items(items)

    # degraded info (optional)
    degraded_fp = run_dir / "degraded_tools.json"
    degraded = None
    if degraded_fp.is_file():
        try:
            degraded = json.loads(degraded_fp.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            degraded = None

    return jsonify({
        "ok": True,
        "rid": rid,
        "source": chosen,
        "n": len(items),
        "counts": counts,
        "degraded": degraded,
    }), 200
'''

# Insert before last "if __name__" if present; else append.
m = re.search(r"\nif\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
if m:
    s = s[:m.start()] + "\n" + code + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + code + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] backend inserted KPI counts route")
PY

echo "== [2] patch KPI JS to use /api/vsp/kpi_counts_v1?rid=... =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_cio_kpi_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="/* VSP_P963_USE_KPI_COUNTS_V1 */"
if marker in s:
    print("[OK] JS already wired to kpi_counts_v1")
    raise SystemExit(0)

# Replace any occurrences of top_findings_v2 fetch in boot() by calling kpi_counts_v1
# We'll simply inject a small override near the top: redefine getCountsForRID and modify boot logic by regex.
# safest: append a new boot() at end that shadows prior boot() by reassigning.
append = r'''
''' + marker + r'''
(function(){
  try{
    // override boot() if exists
    if (typeof boot !== 'function') return;

    function getLatestRID(){
      return getJSON('/api/ui/runs_v3?limit=1&include_ci=1').then(function(r){
        var it = (r && r.items && r.items[0]) ? r.items[0] : null;
        var rid = it && (it.rid || it.run_id || it.id) ? (it.rid || it.run_id || it.id) : '';
        return String(rid || '');
      }).catch(function(){ return ''; });
    }

    // shadow boot with reliable KPI source
    boot = function(){
      getLatestRID().then(function(rid){
        if(!rid){
          render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0},{rid:'N/A',degraded:'no runs'});
          return;
        }
        return getJSON('/api/vsp/kpi_counts_v1?rid=' + encodeURIComponent(rid)).then(function(j){
          var counts = (j && j.counts) ? j.counts : pickCounts(j);
          var meta = {rid: rid, degraded: (j && j.degraded) ? j.degraded : ''};
          render(counts, meta);
        }).catch(function(err){
          render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0},{rid:rid,degraded:'kpi_counts_failed'});
          console.warn('[VSP CIO KPI] kpi_counts_v1 failed:', err);
        });
      });
    };
  }catch(e){
    console.warn('[VSP CIO KPI] P963 patch init failed:', e);
  }
})();
'''
p.write_text(s + "\n" + append, encoding="utf-8")
print("[OK] appended P963 JS override")
PY

echo "[PASS] P963 patched backend + JS"
echo "[NEXT] restart service then test: /api/vsp/kpi_counts_v1?rid=... and open /vsp5"
