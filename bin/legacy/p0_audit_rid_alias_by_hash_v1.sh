#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
LIMIT="${1:-220}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need head

tmp="$(mktemp -d /tmp/vsp_rid_hash_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

curl -fsS "$BASE/api/vsp/runs?limit=$LIMIT&offset=0" -o "$tmp/runs.json"

python3 - "$tmp/runs.json" "$BASE" <<'PY'
import json, sys, subprocess, urllib.parse, hashlib

runs = json.load(open(sys.argv[1],"r",encoding="utf-8")).get("runs") or []
BASE = sys.argv[2]

def get_json(url, timeout=10):
    out = subprocess.check_output(["curl","-fsS","-L",url], timeout=timeout)
    return json.loads(out.decode("utf-8","ignore") or "{}")

def stable_hash(obj):
    s = json.dumps(obj, sort_keys=True, separators=(",",":")).encode("utf-8","ignore")
    return hashlib.sha256(s).hexdigest()

gate_hash_groups = {}   # sha -> [rid...]
gate_from_groups = {}   # from -> [rid...]

for r in runs:
    rid = (r or {}).get("rid") or ""
    if not rid: 
        continue
    j = get_json(f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path=run_gate_summary.json")
    # run_file_allow wrapper may include {"ok":..., "from":..., "data":...} OR raw file dict
    fromp = j.get("from") or j.get("path") or j.get("resolved") or "NO_FROM"
    data = j.get("data") if isinstance(j.get("data"), dict) else j
    h = stable_hash(data)

    gate_hash_groups.setdefault(h, []).append(rid)
    gate_from_groups.setdefault(fromp, []).append(rid)

print("runs_scanned =", len(runs))
print("unique_gate_hashes =", len(gate_hash_groups))
print("unique_from_fields =", len(gate_from_groups))

# show top hash group
top = sorted(gate_hash_groups.items(), key=lambda kv: -len(kv[1]))
print("\n== gate_summary.json hash groups (top 5) ==")
for h, rids in top[:5]:
    print(f"{len(rids):>3}  sha={h[:12]}..  example={rids[0]}")

print("\n== from field groups (top 8) ==")
for f, rids in sorted(gate_from_groups.items(), key=lambda kv: -len(kv[1]))[:8]:
    print(f"{len(rids):>3}  from={f}  example={rids[0]}")

# if multiple hashes exist, print a pair for test
if len(gate_hash_groups) >= 2:
    h1, h2 = top[0][0], top[1][0]
    ridA, ridB = gate_hash_groups[h1][0], gate_hash_groups[h2][0]
    print("\nPAIR_FOR_TEST (different gate_summary content):")
    print("RID_A =", ridA, "shaA =", h1[:16])
    print("RID_B =", ridB, "shaB =", h2[:16])
else:
    print("\nNOTE: All RIDs return identical run_gate_summary content (hash). This strongly indicates RID alias/fallback.")
PY
