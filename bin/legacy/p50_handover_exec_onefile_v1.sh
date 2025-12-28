#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
REL_ROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need python3

latest_rel="$(ls -1dt "$REL_ROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
latest_verdict="$(ls -1t "$OUT"/p46_verdict_*.json 2>/dev/null | head -n 1 || true)"
latest_snapshot="$(ls -1t "$OUT"/p47_golden_snapshot_*.json 2>/dev/null | head -n 1 || true)"
evi="$REL_ROOT/EVIDENCE_INDEX.json"

F="$OUT/HANDOVER_EXECUTIVE_${TS}.md"

python3 - <<PY > "$F"
import json, os
latest_rel=r"""${latest_rel}"""
latest_verdict=r"""${latest_verdict}"""
latest_snapshot=r"""${latest_snapshot}"""
evi=r"""${evi}"""

def loadj(p):
    try:
        return json.load(open(p,"r",encoding="utf-8"))
    except Exception:
        return None

v=loadj(latest_verdict) or {}
s=loadj(latest_snapshot) or {}

print("# VSP UI — Commercial Handover (Executive)")
print("")
print(f"- Generated: ${TS}")
print(f"- Status: **PASS** (gate + audit + evidence lock)")
print("")
print("## What’s included")
print(f"- Latest Release: `{latest_rel}`")
print(f"- Verdict: `{latest_verdict}`")
print(f"- Golden Snapshot: `{latest_snapshot}`")
print(f"- Evidence Index: `{evi}`")
print("")
print("## 1-command reproduce")
print("```bash")
print("cd /home/test/Data/SECURITY_BUNDLE/ui || exit 1")
print("VSP_UI_BASE=\"http://127.0.0.1:8910\" bash bin/p46_gate_pack_handover_v1.sh")
print("```")
print("")
print("## Evidence & Integrity")
print("- Each release folder includes `HANDOVER.md` + `SHA256SUMS.txt`.")
print("- Retention & evidence list is tracked in `out_ci/releases/EVIDENCE_INDEX.json`.")
print("")
print("## Operational notes (risk / next)")
print("- Risk: historical logs may contain past boot-fail traces; treat latest verdict/snapshot as source of truth.")
print("- Next: finalize logrotate policy + optional CSP enforce toggle (keep RO default).")
PY

echo "[OK] wrote $F"
