#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

TS="$(date +%Y%m%d_%H%M%S)"

W="wsgi_vsp_ui_gateway.py"
TPL="templates/vsp_runs_reports_v1.html"
JS_NEW="static/js/vsp_runs_kpi_compact_v3.js"

[ -f "$W" ]   || { echo "[ERR] missing $W"; exit 2; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$W"   "${W}.bak_kpi_v3_${TS}"
cp -f "$TPL" "${TPL}.bak_kpi_v3_${TS}"
echo "[BACKUP] ${W}.bak_kpi_v3_${TS}"
echo "[BACKUP] ${TPL}.bak_kpi_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_V3_ENDPOINT_V1"
if marker not in s:
    block = textwrap.dedent(r"""
# ===================== VSP_P2_RUNS_KPI_V3_ENDPOINT_V1 =====================
# V3: returns trend_overall/trend_sev + degraded + duration. Small-file only.
try:
  import os, json, time, math, re
  from datetime import datetime, timedelta
  from flask import request, jsonify
except Exception:
  request = None
  jsonify = None

def _vsp_p2_app():
  for nm in ("app","application"):
    try:
      obj = globals().get(nm)
      if obj is not None and (hasattr(obj,"route") or hasattr(obj,"get")):
        return obj
    except Exception:
      pass
  return None

def _vsp_p2_rjson(fp):
  try:
    with open(fp,"r",encoding="utf-8",errors="replace") as f:
      return json.load(f)
  except Exception:
    return None

def _vsp_p2_day(name:str):
  try:
    m = re.search(r"(20\d{2})(\d{2})(\d{2})", name or "")
    if m:
      return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
  except Exception:
    pass
  return None

def _vsp_p2_overall(v):
  if not v: return "UNKNOWN"
  vv = str(v).strip().upper()
  if vv in ("GREEN","AMBER","RED","UNKNOWN"): return vv
  if vv in ("PASS","OK","SUCCESS"): return "GREEN"
  if vv in ("WARN","WARNING"): return "AMBER"
  if vv in ("FAIL","FAILED","ERROR"): return "RED"
  return "UNKNOWN"

def _vsp_p2_sev(j:dict):
  if not isinstance(j, dict): return {}
  for k in ("by_severity","severity","counts_by_severity","sev"):
    v = j.get(k)
    if isinstance(v, dict): return v
  c = j.get("counts")
  if isinstance(c, dict):
    v = c.get("by_severity")
    if isinstance(v, dict): return v
  return {}

def _vsp_p2_degraded(j:dict):
  if not isinstance(j, dict): return False
  if bool(j.get("degraded")): return True
  bt = j.get("by_type")
  if isinstance(bt, dict):
    for _, vv in bt.items():
      if isinstance(vv, dict) and bool(vv.get("degraded")):
        return True
  return False

def _vsp_p2_dur(run_dir:str):
  for name in ("run_manifest.json","run_status.json","run_status_v1.json"):
    fp = os.path.join(run_dir, name)
    j = _vsp_p2_rjson(fp) or {}
    for k in ("duration_s","duration_sec","duration"):
      if k in j:
        try: return float(j.get(k))
        except Exception: pass
    ts0 = j.get("ts_start") or j.get("start_ts") or j.get("started_ts")
    ts1 = j.get("ts_end")   or j.get("end_ts")   or j.get("finished_ts")
    try:
      if ts0 and ts1: return float(ts1) - float(ts0)
    except Exception:
      pass
  return None

def _vsp_p2_has_findings(run_dir:str):
  if os.path.isfile(os.path.join(run_dir,"findings_unified.json")): return True
  if os.path.isfile(os.path.join(run_dir,"reports","findings_unified.json")): return True
  if os.path.isfile(os.path.join(run_dir,"reports","findings_unified.csv")): return True
  return False

_app = _vsp_p2_app()
if _app is not None:
  deco = getattr(_app, "get", None) or (lambda path: _app.route(path, methods=["GET"]))

  @deco("/api/ui/runs_kpi_v3")
  def vsp_ui_runs_kpi_v3():
    try:
      days = int(request.args.get("days","30")) if request else 30
    except Exception:
      days = 30
    days = max(1, min(days, 3650))
    now = datetime.now()
    cut = now - timedelta(days=days)

    roots = []
    for r in (
      os.environ.get("VSP_RUNS_ROOT"),
      "/home/test/Data/SECURITY_BUNDLE/out",
      "/home/test/Data/SECURITY_BUNDLE/out_ci",
      "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ):
      if r and os.path.isdir(r) and r not in roots:
        roots.append(r)

    runs = []
    for root in roots:
      try:
        for name in os.listdir(root):
          run_dir = os.path.join(root, name)
          if not os.path.isdir(run_dir): 
            continue
          if not (name.startswith("RUN_") or "_RUN_" in name or name.startswith("VSP_")):
            continue
          day = _vsp_p2_day(name)
          if day:
            try:
              d = datetime.strptime(day, "%Y-%m-%d")
            except Exception:
              d = datetime.fromtimestamp(os.path.getmtime(run_dir))
              day = d.strftime("%Y-%m-%d")
          else:
            d = datetime.fromtimestamp(os.path.getmtime(run_dir))
            day = d.strftime("%Y-%m-%d")
          if d < cut:
            continue
          runs.append((d, day, run_dir, name))
      except Exception:
        pass

    runs.sort(key=lambda x: x[0], reverse=True)
    latest_rid = runs[0][3] if runs else None

    by_overall = {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}
    bucket = {}
    has_gate = 0
    has_findings = 0
    durs = []
    degraded_count = 0

    for _, day, run_dir, rid in runs:
      b = bucket.setdefault(day, {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0,"CRITICAL":0,"HIGH":0,"degraded":0})
      j = _vsp_p2_rjson(os.path.join(run_dir,"run_gate_summary.json")) or {}
      if j: has_gate += 1
      ov = _vsp_p2_overall(j.get("overall_status") or j.get("overall") or j.get("status"))
      by_overall[ov] += 1
      b[ov] += 1

      if _vsp_p2_degraded(j):
        degraded_count += 1
        b["degraded"] += 1

      sev = _vsp_p2_sev(j)
      try:
        b["CRITICAL"] += int(sev.get("CRITICAL",0) or 0)
        b["HIGH"]     += int(sev.get("HIGH",0) or 0)
      except Exception:
        pass

      if _vsp_p2_has_findings(run_dir):
        has_findings += 1

      du = _vsp_p2_dur(run_dir)
      if du is not None:
        try: durs.append(float(du))
        except Exception: pass

    labels = sorted(bucket.keys())
    trend_overall = {
      "labels": labels,
      "GREEN":   [bucket[d]["GREEN"] for d in labels],
      "AMBER":   [bucket[d]["AMBER"] for d in labels],
      "RED":     [bucket[d]["RED"] for d in labels],
      "UNKNOWN": [bucket[d]["UNKNOWN"] for d in labels],
    }
    trend_sev = {
      "labels": labels,
      "CRITICAL": [bucket[d]["CRITICAL"] for d in labels],
      "HIGH":     [bucket[d]["HIGH"] for d in labels],
    }

    total_runs = len(runs)
    rate = (degraded_count/total_runs) if total_runs else 0.0

    dur_avg = None
    dur_p95 = None
    if durs:
      dur_avg = sum(durs)/len(durs)
      ds = sorted(durs)
      k = max(0, min(len(ds)-1, int(math.ceil(0.95*len(ds))-1)))
      dur_p95 = ds[k]

    out = {
      "ok": True,
      "total_runs": total_runs,
      "latest_rid": latest_rid,
      "by_overall": by_overall,
      "has_gate": has_gate,
      "has_findings": has_findings,
      "trend_overall": trend_overall,
      "trend_sev": trend_sev,
      "degraded": {"count": degraded_count, "rate": rate},
      "duration": {"avg_s": dur_avg, "p95_s": dur_p95},
      "roots_used": roots,
      "ts": int(time.time()),
    }
    return jsonify(out) if jsonify else out
# ===================== /VSP_P2_RUNS_KPI_V3_ENDPOINT_V1 =====================
""").strip("\n") + "\n"
    s2 = s + "\n\n" + block
    w.write_text(s2, encoding="utf-8")
    print("[OK] appended runs_kpi_v3 endpoint")
else:
    print("[WARN] marker already present; skip append")
PY

python3 -m py_compile "$W" >/dev/null && echo "[OK] py_compile OK"

# JS compact: fetch v3 (fallback v2/v1), and hide big white canvases if no data.
mkdir -p static/js
cat > static/js/vsp_runs_kpi_compact_v3.js <<'JS'
/* VSP_P2_RUNS_KPI_COMPACT_V3 (no heavy canvas, hide blank panels) */
(()=> {
  if (window.__vsp_runs_kpi_compact_v3) return;
  window.__vsp_runs_kpi_compact_v3 = true;

  const $ = (q)=> document.querySelector(q);

  async function fetchKpi(days){
    const q = encodeURIComponent(String(days||30));
    const urls = [`/api/ui/runs_kpi_v3?days=${q}`, `/api/ui/runs_kpi_v2?days=${q}`, `/api/ui/runs_kpi_v1?days=${q}`];
    let lastErr = null;
    for (const u of urls){
      try{
        const r = await fetch(u, {cache:"no-store"});
        const j = await r.json();
        if (j && j.ok) return j;
        lastErr = new Error(j?.err || "not ok");
      }catch(e){ lastErr = e; }
    }
    throw lastErr || new Error("kpi fetch failed");
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if (!el) return false;
    el.textContent = (v===null || v===undefined) ? "—" : String(v);
    return true;
  }

  function hideIfBlankCanvas(){
    // if your old patch left canvases that become huge white blocks: hide them unless trend labels exist
    const c1 = document.getElementById("vsp_runs_kpi_canvas_overall");
    const c2 = document.getElementById("vsp_runs_kpi_canvas_sev");
    // also allow wrappers
    const w1 = document.getElementById("vsp_runs_kpi_canvas_wrap_overall") || (c1? c1.parentElement : null);
    const w2 = document.getElementById("vsp_runs_kpi_canvas_wrap_sev") || (c2? c2.parentElement : null);
    // default: hide (we render compact)
    if (w1) w1.style.display = "none";
    if (w2) w2.style.display = "none";
  }

  function renderCompactTrend(rootId, labels, seriesMap){
    const root = document.getElementById(rootId);
    if (!root) return;
    if (!labels || !labels.length){
      root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
      return;
    }
    // compact bars per day (stacked)
    const keys = Object.keys(seriesMap);
    const n = labels.length;
    let max = 1;
    for (let i=0;i<n;i++){
      let sum = 0;
      for (const k of keys) sum += (Number(seriesMap[k][i]||0) || 0);
      if (sum > max) max = sum;
    }
    const rows = labels.slice(-14).map((d, idx)=>{
      // map to last 14 points
      const i = labels.length - 14 + idx;
      let seg = '';
      let sum = 0;
      for (const k of keys){
        const v = Number(seriesMap[k][i]||0) || 0;
        sum += v;
      }
      const width = Math.max(2, Math.round((sum/max)*260));
      seg = `<div style="height:8px;width:${width}px;border-radius:6px;background:rgba(148,163,184,.25)"></div>`;
      return `<div style="display:flex;align-items:center;gap:10px;margin:6px 0">
        <div style="width:92px;color:#94a3b8;font-size:11px">${d}</div>
        ${seg}
        <div style="color:#cbd5e1;font-size:11px">${sum}</div>
      </div>`;
    }).join("");
    root.innerHTML = `<div style="margin-top:6px">${rows}</div>`;
  }

  async function boot(){
    // keep layout stable; do not create huge blocks
    hideIfBlankCanvas();

    const daysSel = document.getElementById("vsp_runs_kpi_days");
    const days = daysSel ? Number(daysSel.value||30) : 30;

    try{
      const j = await fetchKpi(days);

      // if your template has these ids from previous patch, they will update; if not, nothing breaks.
      setText("vsp_runs_kpi_total_runs", j.total_runs);
      setText("vsp_runs_kpi_green", j.by_overall?.GREEN ?? 0);
      setText("vsp_runs_kpi_amber", j.by_overall?.AMBER ?? 0);
      setText("vsp_runs_kpi_red", j.by_overall?.RED ?? 0);
      setText("vsp_runs_kpi_unknown", j.by_overall?.UNKNOWN ?? 0);
      setText("vsp_runs_kpi_has_findings", j.has_findings);

      // Optional: compact trends if placeholders exist
      const to = j.trend_overall || {};
      const ts = j.trend_sev || {};
      renderCompactTrend("vsp_runs_kpi_trend_overall_compact", to.labels||[], {
        GREEN: to.GREEN||[], AMBER: to.AMBER||[], RED: to.RED||[], UNKNOWN: to.UNKNOWN||[]
      });
      renderCompactTrend("vsp_runs_kpi_trend_sev_compact", ts.labels||[], {
        CRITICAL: ts.CRITICAL||[], HIGH: ts.HIGH||[]
      });

      // degraded/duration (safe)
      setText("vsp_runs_kpi_degraded_count", j.degraded?.count ?? 0);
      const avg = j.duration?.avg_s;
      const p95 = j.duration?.p95_s;
      setText("vsp_runs_kpi_dur_avg", (avg==null? "—" : Math.round(avg)));
      setText("vsp_runs_kpi_dur_p95", (p95==null? "—" : Math.round(p95)));

    }catch(e){
      // don't spam; just quietly keep page usable
      console.warn("[RUNS_KPI_COMPACT_V3] failed:", e);
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
JS

node --check static/js/vsp_runs_kpi_compact_v3.js >/dev/null && echo "[OK] node --check OK"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

# Ensure compact placeholders exist (small, not vơ layout).
if "vsp_runs_kpi_trend_overall_compact" not in s:
    # add minimal strip under existing Runs KPI title, without changing layout much.
    ins = r"""
<div style="display:flex;gap:18px;flex-wrap:wrap;margin:10px 0 0 0">
  <div style="min-width:360px;flex:1">
    <div style="color:#94a3b8;font-size:12px;margin-bottom:6px">Overall trend (compact)</div>
    <div id="vsp_runs_kpi_trend_overall_compact"></div>
  </div>
  <div style="min-width:360px;flex:1">
    <div style="color:#94a3b8;font-size:12px;margin-bottom:6px">CRITICAL/HIGH trend (compact)</div>
    <div id="vsp_runs_kpi_trend_sev_compact"></div>
  </div>
</div>
"""
    # Insert after first "Runs — Operational KPI" header if exists; else append near top of body.
    if "Runs — Operational KPI" in s:
        s = s.replace("Runs — Operational KPI</div>", "Runs — Operational KPI</div>"+ins, 1)
    else:
        s = s.replace("</body>", ins+"\n</body>", 1)

# Ensure script is included once
if "vsp_runs_kpi_compact_v3.js" not in s:
    s = s.replace("</body>", '\n<script src="/static/js/vsp_runs_kpi_compact_v3.js?v={{ asset_v }}"></script>\n</body>', 1)

tpl.write_text(s, encoding="utf-8")
print("[OK] template patched (compact placeholders + script include)")
PY

echo "[DONE] p2_runs_kpi_v3_compact_fix_v1"
