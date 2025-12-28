#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8910}"
RID="${2:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need python3

if [ -z "${RID:-}" ]; then
  RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
fi
echo "[RID]=$RID"

python3 - "$RID" <<'PY'
import sys, json, time
from pathlib import Path

RID = sys.argv[1]
ROOT = Path("/home/test/Data/SECURITY_BUNDLE")

cands = [
    ROOT/"out"/RID,
    ROOT/"out_ci"/RID,
]
if "RUN_" in RID:
    tail = RID[RID.find("RUN_"):]
    cands += [ROOT/"out"/tail, ROOT/"out_ci"/tail]

run_dir = None
for d in cands:
    if d.is_dir():
        run_dir = d
        break

if not run_dir:
    raise SystemExit(f"[ERR] cannot find run_dir for RID={RID}. Tried: " + ", ".join(map(str,cands)))

reports = run_dir/"reports"
reports.mkdir(parents=True, exist_ok=True)

ts = time.strftime("%Y-%m-%dT%H:%M:%S")
gate = {
  "run_id": run_dir.name,
  "verdict": "UNKNOWN",
  "overall": "UNKNOWN",
  "degraded": True,
  "generated_at": ts,
  "note": "Backfilled minimal reports because this run folder had no report artifacts."
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

def write_if_missing(fp: Path, content: str, min_bytes: int = 5):
    if (not fp.exists()) or fp.stat().st_size < min_bytes:
        fp.write_text(content, encoding="utf-8")
        return True
    return False

written = 0
written += write_if_missing(reports/"run_gate_summary.json", json.dumps(gate, indent=2, ensure_ascii=False)) 
written += write_if_missing(reports/"findings_unified.json", json.dumps(unified, indent=2, ensure_ascii=False))
written += write_if_missing(reports/"SUMMARY.txt", "\n".join([
    f"RUN_ID: {run_dir.name}",
    "OVERALL: UNKNOWN",
    "DEGRADED: true",
    f"GENERATED_AT: {ts}",
    "NOTE: Backfilled minimal SUMMARY because reports were missing.",
    ""
]), min_bytes=10)

rid_for_links = run_dir.name
def link(rel):
    # urlencode '/' as %2F to be safe
    return f"/api/vsp/run_file?rid={rid_for_links}&name=" + rel.replace("/", "%2F")

idx = reports/"index.html"
if (not idx.exists()) or idx.stat().st_size < 80:
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
    written += 1

print("[OK] run_dir =", run_dir)
print("[OK] wrote_files =", written)
PY
