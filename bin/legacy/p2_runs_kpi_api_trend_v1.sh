#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

PYFILE="$(grep -RIl --exclude='*.bak_*' -E 'runs_kpi_v1|/api/ui/runs_kpi_v1' . | head -n1 || true)"
if [ -z "${PYFILE:-}" ]; then
  echo "[ERR] cannot find python file containing runs_kpi_v1 route"
  exit 2
fi
echo "[INFO] target=$PYFILE"

cp -f "$PYFILE" "${PYFILE}.bak_kpi_api_trend_${TS}"
echo "[BACKUP] ${PYFILE}.bak_kpi_api_trend_${TS}"

python3 - <<PY
from pathlib import Path
import re, json, math, statistics, datetime

p = Path("$PYFILE")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_API_TREND_V1"
if marker in s:
    print("[OK] API trend patch already present")
    raise SystemExit(0)

# Find end of runs_kpi_v1 handler: we’ll inject BEFORE "return jsonify(...)" or "return {...}"
# We'll do a safe injection: wrap right before final return of the handler.
# Pattern: a route function containing "runs_kpi_v1" in def name OR in route string.
m = re.search(r"def\s+([a-zA-Z0-9_]*runs_kpi_v1[a-zA-Z0-9_]*)\s*\(", s)
if not m:
    # fallback: locate route decorator then the next def
    m = re.search(r"/api/ui/runs_kpi_v1[^\n]*\n\s*def\s+([a-zA-Z0-9_]+)\s*\(", s)
if not m:
    raise SystemExit("[ERR] cannot locate runs_kpi_v1 handler in python")

fn_name = m.group(1)
print("[INFO] handler:", fn_name)

# locate the function body slice (naive but works for typical flask files)
# find "def fn_name(" start to next "def " at same indent
start = s.find("def "+fn_name)
if start < 0: raise SystemExit("[ERR] cannot slice handler")
rest = s[start:]
m2 = re.search(r"\n(?=def\s+[a-zA-Z0-9_]+\s*\()", rest)
end = start + (m2.start() if m2 else len(rest))
block = s[start:end]

# We assume handler builds a dict named like j / out / resp. If not, we will create `out` and return it unchanged.
# Inject logic: ensure we have a dict variable to enrich:
# - If it returns jsonify(j) -> we can mutate j before return.
# We'll inject just before first "return" inside handler.
retm = re.search(r"\n\s*return\s+", block)
if not retm:
    raise SystemExit("[ERR] handler has no return statement?")
inject_pos = start + retm.start()

inject = f"""
  # ===================== {marker} =====================
  # Enrich KPI response with trend/degraded/duration (best-effort) without widening file read surface.
  try:
    _items = locals().get("items") or locals().get("runs") or locals().get("runs_list") or None
    _out = locals().get("out") or locals().get("j") or locals().get("resp") or locals().get("data") or None
    if not isinstance(_out, dict):
      _out = {{}}
      locals()["out"] = _out

    # Build day buckets from whatever run meta we already scanned in this handler.
    # Expect each item to have: rid, overall(optional), degraded(optional), day(optional), gate(optional dict)
    def _day_from_rid(rid: str):
      # try RUN_YYYYmmdd_HHMMSS
      try:
        m = re.search(r"(20\\d{{2}})(\\d{{2}})(\\d{{2}})", rid or "")
        if m:
          return f"{{m.group(1)}}-{{m.group(2)}}-{{m.group(3)}}"
      except Exception:
        pass
      return None

    labels = []
    daymap = {{}}

    if isinstance(_items, list):
      for it in _items:
        if not isinstance(it, dict): 
          continue
        rid = it.get("rid") or it.get("run_id") or ""
        day = it.get("day") or _day_from_rid(rid)
        if not day:
          continue
        b = daymap.setdefault(day, {{"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0, "CRITICAL":0,"HIGH":0, "degraded":0, "dur": []}})
        ov = (it.get("overall") or it.get("status") or "UNKNOWN") or "UNKNOWN"
        if ov not in ("GREEN","AMBER","RED","UNKNOWN"):
          ov = "UNKNOWN"
        b[ov] += 1

        # degraded best-effort
        if bool(it.get("degraded") or (it.get("by_type") and any((x or {{}}).get("degraded") for x in (it.get("by_type") or {{}}).values() if isinstance(x, dict)))):
          b["degraded"] += 1

        # duration best-effort
        dur = it.get("duration_s") or it.get("duration") or None
        try:
          if dur is not None:
            b["dur"].append(float(dur))
        except Exception:
          pass

        # severity best-effort: if gate summary already merged into item
        sev = it.get("by_severity") or it.get("severity") or it.get("sev") or None
        if isinstance(sev, dict):
          try:
            b["CRITICAL"] += int(sev.get("CRITICAL",0) or 0)
            b["HIGH"] += int(sev.get("HIGH",0) or 0)
          except Exception:
            pass

    labels = sorted(daymap.keys())
    trend_overall = {{
      "labels": labels,
      "GREEN": [daymap[d]["GREEN"] for d in labels],
      "AMBER": [daymap[d]["AMBER"] for d in labels],
      "RED": [daymap[d]["RED"] for d in labels],
      "UNKNOWN": [daymap[d]["UNKNOWN"] for d in labels],
    }}
    trend_sev = {{
      "labels": labels,
      "CRITICAL": [daymap[d]["CRITICAL"] for d in labels],
      "HIGH": [daymap[d]["HIGH"] for d in labels],
    }}

    total = sum(daymap[d]["GREEN"]+daymap[d]["AMBER"]+daymap[d]["RED"]+daymap[d]["UNKNOWN"] for d in labels) or 0
    degraded_count = sum(daymap[d]["degraded"] for d in labels) if labels else 0
    degraded_rate = (degraded_count/total) if total else 0.0

    # duration stats
    durs = []
    for d in labels:
      durs += daymap[d]["dur"]
    dur_avg = (sum(durs)/len(durs)) if durs else None
    dur_p95 = None
    if durs:
      durs_sorted = sorted(durs)
      k = max(0, min(len(durs_sorted)-1, math.ceil(0.95*len(durs_sorted))-1))
      dur_p95 = durs_sorted[k]

    _out["trend_overall"] = trend_overall
    _out["trend_sev"] = trend_sev
    _out["degraded"] = {{"count": degraded_count, "rate": degraded_rate}}
    _out["duration"] = {{"avg_s": dur_avg, "p95_s": dur_p95}}
  except Exception as _e:
    try:
      _out = locals().get("out") or locals().get("j") or None
      if isinstance(_out, dict):
        _out["trend_overall"] = {{"labels":[]}}
        _out["trend_sev"] = {{"labels":[]}}
    except Exception:
      pass
  # ===================== /{marker} =====================

"""

# Need `re, math` imported; inject small imports near top if missing
if "import re" not in s:
    s = "import re\n" + s
if "import math" not in s:
    s = "import math\n" + s

s = s[:inject_pos] + inject + s[inject_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] injected API trend enrichment into", p)
PY

python3 -m py_compile "$PYFILE" && echo "[OK] py_compile OK"
echo "[DONE] p2_runs_kpi_api_trend_v1 (restart UI service to apply)"
