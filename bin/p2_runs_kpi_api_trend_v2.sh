#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

# 0) Find the python file that defines /api/ui/runs_kpi_v1 (STRICT .py, exclude out*/static/templates/bin)
PYFILE="$(python3 - <<'PY'
from pathlib import Path
bad_parts = set(["out","out_ci",".git","node_modules","venv",".venv","static","templates","bin"])
cands=[]
for p in Path(".").rglob("*.py"):
    if any(part in bad_parts for part in p.parts):
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if '"/api/ui/runs_kpi_v1"' in s or "'/api/ui/runs_kpi_v1'" in s or "/api/ui/runs_kpi_v1" in s:
        cands.append(str(p))
print(cands[0] if cands else "")
PY
)"

if [ -z "${PYFILE:-}" ] || [ ! -f "$PYFILE" ]; then
  echo "[ERR] cannot find python file containing /api/ui/runs_kpi_v1"
  exit 2
fi

echo "[INFO] target=$PYFILE"
cp -f "$PYFILE" "${PYFILE}.bak_kpi_api_trend_${TS}"
echo "[BACKUP] ${PYFILE}.bak_kpi_api_trend_${TS}"

# 1) Patch handler body: enrich output with trend_overall/trend_sev/degraded/duration (best-effort, small-file only)
python3 - <<PY
from pathlib import Path
import re, textwrap

p = Path("$PYFILE")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_API_TREND_V2"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find decorator for /api/ui/runs_kpi_v1 then the def block
# Works for @app.get("/api/ui/runs_kpi_v1") or @bp.route("/api/ui/runs_kpi_v1", methods=[...])
pat = re.compile(
    r'(?s)(@[^\\n]*\\(\\s*[\\\'"]\\/api\\/ui\\/runs_kpi_v1[\\\'"][^\\)]*\\)\\s*\\n\\s*def\\s+([a-zA-Z0-9_]+)\\s*\\([^\\)]*\\)\\s*:\\s*\\n)(\\s+.*?)(?=\\n@|\\ndef\\s+|\\Z)'
)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot locate runs_kpi_v1 handler in python (decorator+def)")

head = m.group(1)
fn  = m.group(2)
indent = "  "  # typical 2 spaces, but body injection will use 2 spaces safely inside function

new_body = textwrap.dedent(f"""
{indent}# ===================== {marker} =====================
{indent}# Commercial-safe: server-side read-only aggregation; no generic run_file.
{indent}import os, json, time, math
{indent}from datetime import datetime, timedelta

{indent}try:
{indent}  from flask import request, jsonify
{indent}except Exception:
{indent}  request = None
{indent}  jsonify = None

{indent}def _safe_read_json(fp):
{indent}  try:
{indent}    with open(fp, "r", encoding="utf-8", errors="replace") as f:
{indent}      return json.load(f)
{indent}  except Exception:
{indent}    return None

{indent}def _parse_day_from_name(name: str):
{indent}  try:
{indent}    mm = re.search(r"(20\\d{{2}})(\\d{{2}})(\\d{{2}})", name or "")
{indent}    if mm:
{indent}      return f"{{mm.group(1)}}-{{mm.group(2)}}-{{mm.group(3)}}"
{indent}  except Exception:
{indent}    pass
{indent}  return None

{indent}def _norm_overall(v):
{indent}  if not v: return "UNKNOWN"
{indent}  vv = str(v).strip().upper()
{indent}  if vv in ("GREEN","AMBER","RED","UNKNOWN"): return vv
{indent}  # tolerate PASS/WARN/FAIL
{indent}  if vv in ("PASS","OK","SUCCESS"): return "GREEN"
{indent}  if vv in ("WARN","WARNING","AMBER"): return "AMBER"
{indent}  if vv in ("FAIL","FAILED","ERROR","RED"): return "RED"
{indent}  return "UNKNOWN"

{indent}def _pick_sev_counts(j):
{indent}  # best-effort: try common locations
{indent}  for k in ("by_severity","severity","sev","counts_by_severity"):
{indent}    if isinstance(j.get(k), dict): return j.get(k)
{indent}  c = j.get("counts") if isinstance(j.get("counts"), dict) else {{}}
{indent}  if isinstance(c.get("by_severity"), dict): return c.get("by_severity")
{indent}  return None

{indent}def _is_degraded(j):
{indent}  if bool(j.get("degraded")): return True
{indent}  bt = j.get("by_type")
{indent}  if isinstance(bt, dict):
{indent}    for _, vv in bt.items():
{indent}      if isinstance(vv, dict) and bool(vv.get("degraded")):
{indent}        return True
{indent}  return False

{indent}def _duration_s(run_dir):
{indent}  # best-effort: run_manifest.json / run_status.json
{indent}  for name in ("run_manifest.json","run_status.json","run_status_v1.json"):
{indent}    fp = os.path.join(run_dir, name)
{indent}    j = _safe_read_json(fp) or {{}}
{indent}    for k in ("duration_s","duration_sec","duration"):
{indent}      if k in j:
{indent}        try: return float(j.get(k))
{indent}        except Exception: pass
{indent}    # compute from timestamps if present
{indent}    ts0 = j.get("ts_start") or j.get("start_ts") or j.get("started_ts")
{indent}    ts1 = j.get("ts_end")   or j.get("end_ts")   or j.get("finished_ts")
{indent}    try:
{indent}      if ts0 and ts1:
{indent}        return float(ts1) - float(ts0)
{indent}    except Exception:
{indent}      pass
{indent}  return None

{indent}def _has_findings(run_dir):
{indent}  # presence only (no heavy reads)
{indent}  if os.path.isfile(os.path.join(run_dir,"findings_unified.json")): return True
{indent}  if os.path.isfile(os.path.join(run_dir,"reports","findings_unified.json")): return True
{indent}  if os.path.isfile(os.path.join(run_dir,"reports","findings_unified.csv")): return True
{indent}  return False

{indent}days = 30
{indent}try:
{indent}  if request is not None:
{indent}    days = int(request.args.get("days", "30"))
{indent}except Exception:
{indent}  days = 30
{indent}days = max(1, min(days, 3650))

{indent}now = datetime.now()
{indent}cut = now - timedelta(days=days)

{indent}roots = []
{indent}for r in (
{indent}  os.environ.get("VSP_RUNS_ROOT"),
{indent}  "/home/test/Data/SECURITY_BUNDLE/out",
{indent}  "/home/test/Data/SECURITY_BUNDLE/out_ci",
{indent}  "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
{indent}):
{indent}  if r and os.path.isdir(r) and r not in roots:
{indent}    roots.append(r)

{indent}runs = []
{indent}for root in roots:
{indent}  try:
{indent}    for name in os.listdir(root):
{indent}      run_dir = os.path.join(root, name)
{indent}      if not os.path.isdir(run_dir): 
{indent}        continue
{indent}      if not (name.startswith("RUN_") or "_RUN_" in name or name.startswith("VSP_")):
{indent}        continue
{indent}      day = _parse_day_from_name(name)
{indent}      if day:
{indent}        try:
{indent}          d = datetime.strptime(day, "%Y-%m-%d")
{indent}        except Exception:
{indent}          d = datetime.fromtimestamp(os.path.getmtime(run_dir))
{indent}      else:
{indent}        d = datetime.fromtimestamp(os.path.getmtime(run_dir))
{indent}        day = d.strftime("%Y-%m-%d")
{indent}      if d < cut:
{indent}        continue
{indent}      runs.append((d, day, run_dir, name))
{indent}  except Exception:
{indent}    pass

{indent}runs.sort(key=lambda x: x[0], reverse=True)
{indent}latest_rid = runs[0][3] if runs else None

{indent}by_overall = {{"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}}
{indent}has_gate = 0
{indent}has_findings = 0

{indent}# day buckets
{indent}bucket = {{}}
{indent}durs = []
{indent}degraded_count = 0

{indent}for _, day, run_dir, rid in runs:
{indent}  b = bucket.setdefault(day, {{"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0,"CRITICAL":0,"HIGH":0,"degraded":0}})
{indent}  gate_fp = os.path.join(run_dir, "run_gate_summary.json")
{indent}  j = _safe_read_json(gate_fp) or {{}}
{indent}  if j:
{indent}    has_gate += 1
{indent}  ov = _norm_overall(j.get("overall_status") or j.get("overall") or j.get("status") or j.get("verdict"))
{indent}  by_overall[ov] += 1
{indent}  b[ov] += 1

{indent}  if _is_degraded(j):
{indent}    degraded_count += 1
{indent}    b["degraded"] += 1

{indent}  sev = _pick_sev_counts(j) or {{}}
{indent}  try:
{indent}    b["CRITICAL"] += int(sev.get("CRITICAL",0) or 0)
{indent}    b["HIGH"]     += int(sev.get("HIGH",0) or 0)
{indent}  except Exception:
{indent}    pass

{indent}  if _has_findings(run_dir):
{indent}    has_findings += 1

{indent}  du = _duration_s(run_dir)
{indent}  if du is not None:
{indent}    try: durs.append(float(du))
{indent}    except Exception: pass

{indent}labels = sorted(bucket.keys())
{indent}trend_overall = {{
{indent}  "labels": labels,
{indent}  "GREEN":   [bucket[d]["GREEN"] for d in labels],
{indent}  "AMBER":   [bucket[d]["AMBER"] for d in labels],
{indent}  "RED":     [bucket[d]["RED"] for d in labels],
{indent}  "UNKNOWN": [bucket[d]["UNKNOWN"] for d in labels],
{indent}}}
{indent}trend_sev = {{
{indent}  "labels": labels,
{indent}  "CRITICAL": [bucket[d]["CRITICAL"] for d in labels],
{indent}  "HIGH":     [bucket[d]["HIGH"] for d in labels],
{indent}}}

{indent}total_runs = len(runs)
{indent}rate = (degraded_count/total_runs) if total_runs else 0.0

{indent}dur_avg = None
{indent}dur_p95 = None
{indent}if durs:
{indent}  dur_avg = sum(durs)/len(durs)
{indent}  ds = sorted(durs)
{indent}  k = max(0, min(len(ds)-1, int(math.ceil(0.95*len(ds))-1)))
{indent}  dur_p95 = ds[k]

{indent}out = {{
{indent}  "ok": True,
{indent}  "total_runs": total_runs,
{indent}  "latest_rid": latest_rid,
{indent}  "by_overall": by_overall,
{indent}  "has_gate": has_gate,
{indent}  "has_findings": has_findings,
{indent}  "trend_overall": trend_overall,
{indent}  "trend_sev": trend_sev,
{indent}  "degraded": {{"count": degraded_count, "rate": rate}},
{indent}  "duration": {{"avg_s": dur_avg, "p95_s": dur_p95}},
{indent}  "roots_used": roots,
{indent}  "ts": int(time.time()),
{indent}}}

{indent}if jsonify:
{indent}  return jsonify(out)
{indent}return out
{indent}# ===================== /{marker} =====================
""").strip("\n") + "\n"

# Replace body with new_body (keep decorator+def head)
s2 = s[:m.start()] + head + new_body + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched handler:", fn)
PY

python3 -m py_compile "$PYFILE" && echo "[OK] py_compile OK"
echo "[DONE] p2_runs_kpi_api_trend_v2 (restart service)"
