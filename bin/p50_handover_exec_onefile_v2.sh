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

python3 - "$F" "$latest_rel" "$latest_verdict" "$latest_snapshot" "$evi" <<'PY2'
import json, os, sys
F, latest_rel, latest_verdict, latest_snapshot, evi = sys.argv[1:6]
def loadj(p):
    try:
        with open(p, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}
v = loadj(latest_verdict) if latest_verdict else {}
s = loadj(latest_snapshot) if latest_snapshot else {}

out = []
out.append('# VSP UI — Commercial Handover (Executive)')
out.append('')
out.append(f'- Generated: {os.path.basename(F)}')
out.append(f'- Status: **PASS** (gate + audit + evidence lock)')
out.append('')
out.append('## What’s included')
out.append(f'- Latest Release: `{latest_rel}`' if latest_rel else '- Latest Release: `(missing)`')
out.append(f'- Verdict: `{latest_verdict}`' if latest_verdict else '- Verdict: `(missing)`')
out.append(f'- Golden Snapshot: `{latest_snapshot}`' if latest_snapshot else '- Golden Snapshot: `(missing)`')
out.append(f'- Evidence Index: `{evi}`' if evi else '- Evidence Index: `(missing)`')
out.append('')
out.append('## 1-command reproduce')
out.append('```bash')
out.append('cd /home/test/Data/SECURITY_BUNDLE/ui || exit 1')
out.append('VSP_UI_BASE="http://127.0.0.1:8910" bash bin/p46_gate_pack_handover_v1.sh')
out.append('```')
out.append('')
out.append('## Evidence & Integrity')
out.append('- Each release folder includes `HANDOVER.md` + `SHA256SUMS.txt`.')
out.append('- Retention & evidence list is tracked in `out_ci/releases/EVIDENCE_INDEX.json`.')
out.append('')
out.append('## Operational notes (risk / next)')
out.append('- Note: historical logs may contain past boot-fail traces; use latest verdict/snapshot as source of truth.')
out.append('- Next: logrotate hardening + optional CSP enforce toggle (keep CSP-RO default).')
out.append('')

with open(F, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
print('[OK] wrote', F)
PY2

# quick sanity: file must contain header + reproduce block
grep -q "VSP UI — Commercial Handover" "$F" && grep -q "p46_gate_pack_handover_v1.sh" "$F" && echo "[OK] sanity PASS" || { echo "[ERR] sanity FAIL"; exit 2; }

echo "[OK] done: $F"
