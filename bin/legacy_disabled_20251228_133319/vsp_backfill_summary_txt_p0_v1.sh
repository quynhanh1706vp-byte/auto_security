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
scanned = 0

for run_dir in sorted([p for p in out.iterdir() if p.is_dir()]):
    scanned += 1
    summ = run_dir / "SUMMARY.txt"
    if summ.exists() and summ.stat().st_size > 10:
        continue

    j1 = run_dir / "reports" / "run_gate_summary.json"
    j2 = run_dir / "run_gate_summary.json"
    j3 = run_dir / "run_gate.json"
    data = None
    src = None
    for cand in (j1, j2, j3):
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

    # counts best-effort
    counts = data.get("counts") if isinstance(data.get("counts"), dict) else {}
    sev = data.get("severity") if isinstance(data.get("severity"), dict) else {}
    tools = data.get("tools") if isinstance(data.get("tools"), dict) else {}

    lines = []
    lines.append(f"RUN_ID: {rid}")
    lines.append(f"OVERALL: {overall}")
    lines.append(f"DEGRADED: {degraded}")
    if counts:
        lines.append("COUNTS: " + ", ".join([f"{k}={v}" for k,v in counts.items()]))
    if sev:
        lines.append("SEVERITY: " + ", ".join([f"{k}={v}" for k,v in sev.items()]))
    if tools:
        # show small subset
        ok = []
        bad = []
        for k,v in tools.items():
            if isinstance(v, dict):
                st = v.get("status") or v.get("state") or v.get("ok")
            else:
                st = v
            if str(st).lower() in ("ok","pass","true"):
                ok.append(k)
            else:
                bad.append(k)
        if ok:
            lines.append("TOOLS_OK: " + ", ".join(ok[:12]))
        if bad:
            lines.append("TOOLS_WARN: " + ", ".join(bad[:12]))
    lines.append(f"SOURCE: {src}")

    summ.write_text("\n".join(lines) + "\n", encoding="utf-8")
    patched += 1

print(f"[OK] scanned={scanned} backfilled_summary_txt={patched}")
PY
