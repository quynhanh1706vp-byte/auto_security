#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import json, time

out = Path("out")
if not out.exists():
    print("[SKIP] missing out/ under SECURITY_BUNDLE")
    raise SystemExit(0)

def safe_read_json(p):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

patched=0
for rd in sorted(out.glob("RUN_*"), reverse=True):
    if not rd.is_dir(): 
        continue
    reports = rd/"reports"
    reports.mkdir(exist_ok=True)
    idx = reports/"index.html"
    sumj = reports/"run_gate_summary.json"

    # summary json
    if not sumj.exists():
        gate = safe_read_json(rd/"run_gate.json") or {}
        uni  = safe_read_json(rd/"findings_unified.json") or {}
        verdict = gate.get("overall") or gate.get("verdict") or gate.get("status") or "UNKNOWN"
        counts = None
        if isinstance(uni, dict):
            counts = uni.get("counts") or uni.get("summary") or None
        obj = {
            "run_id": rd.name,
            "verdict": verdict,
            "counts": counts,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "note": "backfilled minimal summary for UI demo"
        }
        sumj.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        patched += 1

    # index html
    if not idx.exists():
        rid = rd.name
        links = []
        for rel in ["reports/run_gate_summary.json","SUMMARY.txt","findings_unified.json","findings_unified.csv","findings_unified.sarif"]:
            if (rd/rel).exists():
                links.append(rel)
        html = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>{rid} - Reports</title>
<style>
body{{font-family:system-ui,Segoe UI,Roboto,Arial;margin:24px;background:#0b1220;color:#e7eefc}}
a{{color:#9ad1ff}}
.card{{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);border-radius:14px;padding:16px;margin-top:12px}}
.small{{opacity:.8;font-size:12px}}
</style></head>
<body>
<h2>{rid} - Minimal Reports</h2>
<div class="small">Backfilled to keep UI “commercial” even when pipeline didn’t export full report set.</div>
<div class="card">
<h3>Artifacts</h3>
<ul>
{''.join([f'<li><a href="../{x}">{x}</a></li>' for x in links]) if links else '<li>(no artifacts found)</li>'}
</ul>
</div>
</body></html>
"""
        idx.write_text(html, encoding="utf-8")
        patched += 1

print("[OK] backfilled files:", patched)
PY
