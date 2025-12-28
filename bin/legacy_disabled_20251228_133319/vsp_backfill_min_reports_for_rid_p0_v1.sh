#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need python3

RID="${2:-}"
if [ -z "${RID:-}" ]; then
  RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
fi
echo "[RID]=$RID"

ROOT="/home/test/Data/SECURITY_BUNDLE"
python3 - <<'PY'
from pathlib import Path
import json, time, os

RID=os.environ["RID"]
ROOT=Path("/home/test/Data/SECURITY_BUNDLE")

cands=[]
cands.append(ROOT/"out"/RID)
cands.append(ROOT/"out_ci"/RID)

# optional canonical RUN_ tail
if "RUN_" in RID:
    tail = RID[RID.find("RUN_"):]
    cands.append(ROOT/"out"/tail)
    cands.append(ROOT/"out_ci"/tail)

run_dir=None
for d in cands:
    if d.is_dir():
        run_dir=d
        break

if not run_dir:
    raise SystemExit(f"[ERR] cannot find run_dir for RID={RID} in out/out_ci (cands={cands})")

reports = run_dir/"reports"
reports.mkdir(parents=True, exist_ok=True)

# Minimal JSONs
ts = time.strftime("%Y-%m-%dT%H:%M:%S")
gate = {
  "run_id": run_dir.name,
  "verdict": "UNKNOWN",
  "overall": "UNKNOWN",
  "degraded": True,
  "generated_at": ts,
  "note": "Backfilled minimal reports because this run folder had no report artifacts. Treat as degraded/stub run."
}

sev_levels = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
counts = {k:0 for k in sev_levels}

unified = {
  "run_id": run_dir.name,
  "generated_at": ts,
  "counts": counts,
  "findings": [],
  "tools": {},
  "note": "Backfilled minimal unified findings (empty) for UI/demo continuity."
}

# Files to ensure (ONLY in reports/ for whitelist-friendliness)
files = {
  "run_gate_summary.json": json.dumps(gate, indent=2, ensure_ascii=False),
  "findings_unified.json": json.dumps(unified, indent=2, ensure_ascii=False),
  "SUMMARY.txt": "\n".join([
      f"RUN_ID: {run_dir.name}",
      "OVERALL: UNKNOWN",
      "DEGRADED: true",
      f"GENERATED_AT: {ts}",
      "NOTE: Backfilled minimal SUMMARY because reports were missing.",
      ""
  ])
}

written=[]
for name, content in files.items():
    fp = reports/name
    if (not fp.exists()) or fp.stat().st_size < 5:
        fp.write_text(content, encoding="utf-8")
        written.append(str(fp))

# index.html with ABSOLUTE run_file links (so links work even when served via run_file)
rid_for_links = run_dir.name
def link(rel):
    # rel is reports/...
    return f"/api/vsp/run_file?rid={rid_for_links}&name={rel.replace('/','%2F')}"

idx = reports/"index.html"
if (not idx.exists()) or idx.stat().st_size < 50:
    html = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>{rid_for_links} - Reports</title>
<style>
body{{font-family:system-ui,Segoe UI,Roboto,Arial;margin:24px;background:#0b1220;color:#e7eefc}}
a{{color:#9ad1ff}}
.card{{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);border-radius:14px;padding:16px;margin-top:12px}}
.small{{opacity:.8;font-size:12px}}
</style></head>
<body>
<h2>{rid_for_links} - Minimal Reports</h2>
<div class="small">Generated to keep Runs &amp; Reports “commercial-grade” even when pipeline outputs are missing.</div>
<div class="card">
<h3>Artifacts</h3>
<ul>
<li><a href="{link('reports/run_gate_summary.json')}" target="_blank" rel="noopener">run_gate_summary.json</a></li>
<li><a href="{link('reports/findings_unified.json')}" target="_blank" rel="noopener">findings_unified.json</a></li>
<li><a href="{link('reports/SUMMARY.txt')}" target="_blank" rel="noopener">SUMMARY.txt</a></li>
</ul>
</div>
</body></html>
"""
    idx.write_text(html, encoding="utf-8")
    written.append(str(idx))

print("[OK] run_dir =", run_dir)
print("[OK] wrote =", len(written))
for w in written[:20]:
    print(" -", w)
PY
