#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import json

out = Path("out")
if not out.exists():
    print("[SKIP] missing out/")
    raise SystemExit(0)

def read_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

patched = 0
for run_dir in sorted([p for p in out.iterdir() if p.is_dir()]):
    reports = run_dir / "reports"
    reports.mkdir(exist_ok=True)

    # write BOTH places (root + reports/) to satisfy any whitelist
    targets = [run_dir / "SUMMARY.txt", reports / "SUMMARY.txt"]

    # if both already exist and non-trivial, skip
    if all(t.exists() and t.stat().st_size > 10 for t in targets):
        continue

    # prefer reports/run_gate_summary.json then run_gate.json
    src = None
    data = None
    for cand in (reports / "run_gate_summary.json", run_dir / "run_gate_summary.json", run_dir / "run_gate.json"):
        if cand.exists():
            data = read_json(cand)
            if isinstance(data, dict):
                src = cand
                break
    if not isinstance(data, dict):
        continue

    rid = run_dir.name
    overall = data.get("overall") or data.get("verdict") or data.get("status") or "UNKNOWN"
    degraded = data.get("degraded") if isinstance(data.get("degraded"), bool) else False
    counts = data.get("counts") if isinstance(data.get("counts"), dict) else {}
    sev = data.get("severity") if isinstance(data.get("severity"), dict) else {}

    lines = []
    lines.append(f"RUN_ID: {rid}")
    lines.append(f"OVERALL: {overall}")
    lines.append(f"DEGRADED: {degraded}")
    if counts:
        lines.append("COUNTS: " + ", ".join([f"{k}={v}" for k,v in counts.items()]))
    if sev:
        lines.append("SEVERITY: " + ", ".join([f"{k}={v}" for k,v in sev.items()]))
    lines.append(f"SOURCE: {src}")

    body = "\n".join(lines) + "\n"
    for t in targets:
        if (not t.exists()) or t.stat().st_size <= 10:
            t.write_text(body, encoding="utf-8")
            patched += 1

print(f"[OK] backfilled SUMMARY.txt copies = {patched}")
PY
