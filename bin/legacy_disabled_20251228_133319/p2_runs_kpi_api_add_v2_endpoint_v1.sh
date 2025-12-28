#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_kpi_v2_api_${TS}"
echo "[BACKUP] ${F}.bak_kpi_v2_api_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_V2_ENDPOINT_V1"
if marker in s:
    print("[OK] endpoint already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P2_RUNS_KPI_V2_ENDPOINT_V1 =====================
# Safe read-only aggregation endpoint (NO generic run_file). Small-file only.
try:
  import os, json, time, math, re
  from datetime import datetime, timedelta
  from flask import request, jsonify
except Exception:
  request = None
  jsonify = None

def _vsp_p2_pick_app():
  # try common globals
  for name in ("app", "application"):
    try:
      obj = globals().get(name)
      # flask app has .route or .get attribute
      if obj is not None and (hasattr(obj, "route") or hasattr(obj, "get")):
        return obj
    except Exception:
      pass
  return None

def _vsp_p2_safe_read_json(fp):
  try:
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
      return json.load(f)
  except Exception:
    return None

def _vsp_p2_parse_day(name: str):
  try:
    m = re.search(r"(20\d{2})(\d{2})(\d{2})", name or "")
    if m:
      return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
  except Exception:
    pass
  return None

def _vsp_p2_norm_overall(v):
  if not v:
    return "UNKNOWN"
  vv = str(v).strip().upper()
  if vv in ("GREEN", "AMBER", "RED", "UNKNOWN"):
    return vv
  if vv in ("PASS", "OK", "SUCCESS"):
    return "GREEN"
  if vv in ("WARN", "WARNING"):
    return "AMBER"
  if vv in ("FAIL", "FAILED", "ERROR"):
    return "RED"
  return "UNKNOWN"

def _vsp_p2_pick_sev(j: dict):
  if not isinstance(j, dict):
    return {}
  # best-effort: common keys
  for k in ("by_severity", "severity", "counts_by_severity", "sev"):
    v = j.get(k)
    if isinstance(v, dict):
      return v
  c = j.get("counts")
  if isinstance(c, dict):
    v = c.get("by_severity")
    if isinstance(v, dict):
      return v
  return {}

def _vsp_p2_is_degraded(j: dict):
  if not isinstance(j, dict):
    return False
  if bool(j.get("degraded")):
    return True
  bt = j.get("by_type")
  if isinstance(bt, dict):
    for _, vv in bt.items():
      if isinstance(vv, dict) and bool(vv.get("degraded")):
        return True
  return False

def _vsp_p2_duration_s(run_dir: str):
  # best-effort only
  for name in ("run_manifest.json", "run_status.json", "run_status_v1.json"):
    fp = os.path.join(run_dir, name)
    j = _vsp_p2_safe_read_json(fp) or {}
    for k in ("duration_s", "duration_sec", "duration"):
      if k in j:
        try:
          return float(j.get(k))
        except Exception:
          pass
    ts0 = j.get("ts_start") or j.get("start_ts") or j.get("started_ts")
    ts1 = j.get("ts_end")   or j.get("end_ts")   or j.get("finished_ts")
    try:
      if ts0 and ts1:
        return float(ts1) - float(ts0)
    except Exception:
      pass
  return None

def _vsp_p2_has_findings(run_dir: str):
  # presence only (avoid heavy reads)
  if os.path.isfile(os.path.join(run_dir, "findings_unified.json")):
    return True
  if os.path.isfile(os.path.join(run_dir, "reports", "findings_unified.json")):
    return True
  if os.path.isfile(os.path.join(run_dir, "reports", "findings_unified.csv")):
    return True
  return False

_app = _vsp_p2_pick_app()
if _app is not None:
  # flask 2+: .get exists; fallback to .route
  deco = getattr(_app, "get", None) or (lambda path: _app.route(path, methods=["GET"]))

  @deco("/api/ui/runs_kpi_v2")
  def vsp_ui_runs_kpi_v2():
    try:
      days = int(request.args.get("days", "30")) if request else 30
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
          # accept your real patterns: RUN_* OR contains _RUN_ OR VSP_*
          if not (name.startswith("RUN_") or "_RUN_" in name or name.startswith("VSP_")):
            continue

          day = _vsp_p2_parse_day(name)
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

    by_overall = {"GREEN":0, "AMBER":0, "RED":0, "UNKNOWN":0}
    bucket = {}
    has_gate = 0
    has_findings = 0
    durs = []
    degraded_count = 0

    for _, day, run_dir, rid in runs:
      b = bucket.setdefault(day, {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0,"CRITICAL":0,"HIGH":0,"degraded":0})

      j = _vsp_p2_safe_read_json(os.path.join(run_dir, "run_gate_summary.json")) or {}
      if j:
        has_gate += 1

      ov = _vsp_p2_norm_overall(j.get("overall_status") or j.get("overall") or j.get("status"))
      by_overall[ov] += 1
      b[ov] += 1

      if _vsp_p2_is_degraded(j):
        degraded_count += 1
        b["degraded"] += 1

      sev = _vsp_p2_pick_sev(j)
      try:
        b["CRITICAL"] += int(sev.get("CRITICAL", 0) or 0)
        b["HIGH"]     += int(sev.get("HIGH", 0) or 0)
      except Exception:
        pass

      if _vsp_p2_has_findings(run_dir):
        has_findings += 1

      du = _vsp_p2_duration_s(run_dir)
      if du is not None:
        try:
          durs.append(float(du))
        except Exception:
          pass

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
# ===================== /VSP_P2_RUNS_KPI_V2_ENDPOINT_V1 =====================
""").strip("\n") + "\n"

# Append at end (safe, no regex surgery)
p.write_text(s + "\n\n" + block, encoding="utf-8")
print("[OK] appended KPI v2 endpoint block")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK"
echo "[DONE] p2_runs_kpi_api_add_v2_endpoint_v1 (restart service)"
