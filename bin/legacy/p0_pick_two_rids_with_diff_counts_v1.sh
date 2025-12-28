#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
LIMIT="${1:-200}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need head; need date

tmp="$(mktemp -d /tmp/vsp_pick2rid_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [1] fetch runs list (limit=$LIMIT) =="
curl -fsS "$BASE/api/vsp/runs?limit=$LIMIT&offset=0" -o "$tmp/runs.json"

python3 - "$tmp/runs.json" "$BASE" <<'PY'
import json, sys, subprocess, urllib.parse, time

runs = json.load(open(sys.argv[1],"r",encoding="utf-8")).get("runs") or []
BASE = sys.argv[2]

def get_json(url, timeout=8):
    out = subprocess.check_output(["curl","-fsS","-L",url], timeout=timeout)
    return json.loads(out.decode("utf-8","ignore") or "{}")

def sig(ct: dict):
    keys = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    return ",".join(f"{k}={int(ct.get(k,0) or 0)}" for k in keys)

groups = {}   # sig -> [rid...]
errs = []

for idx, r in enumerate(runs):
    rid = (r or {}).get("rid") or ""
    if not rid: 
        continue
    try:
        j = get_json(f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path=run_gate_summary.json", timeout=10)
        ct = (j.get("counts_total") or {})
        s = sig(ct)
        groups.setdefault(s, []).append(rid)
    except Exception as e:
        errs.append((rid, str(e)[:120]))

print("runs_scanned =", len(runs))
print("unique_signatures =", len(groups))
if errs:
    print("errors =", len(errs), "example=", errs[0][0], errs[0][1])

# Show top signatures
print("\n== top signatures (most common first) ==")
for s, rids in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:12]:
    print(f"{len(rids):>3}  {s}  example={rids[0]}")

# Pick 2 different signatures
good = [k for k in groups.keys() if k and k != "ERR"]
if len(good) < 2:
    print("\n[WARN] Not enough distinct signatures in sampled runs.")
    print("Try increasing LIMIT or check whether your run inventory is duplicated/aliased.")
    raise SystemExit(0)

good_sorted = sorted(good, key=lambda k: (-len(groups[k]), k))
s1, s2 = good_sorted[0], good_sorted[1]
rid1, rid2 = groups[s1][0], groups[s2][0]

print("\nPAIR_FOR_TEST:")
print("RID_A =", rid1)
print("SIG_A =", s1)
print("RID_B =", rid2)
print("SIG_B =", s2)

# Cross-check with dash_kpis for these two
def dash_kpis(rid):
    return get_json(f"{BASE}/api/vsp/dash_kpis?rid={urllib.parse.quote(rid)}", timeout=8)

try:
    k1 = dash_kpis(rid1)
    k2 = dash_kpis(rid2)
    print("\n== dash_kpis cross-check ==")
    print("RID_A total_findings =", k1.get("total_findings"), "counts_total =", k1.get("counts_total"))
    print("RID_B total_findings =", k2.get("total_findings"), "counts_total =", k2.get("counts_total"))
except Exception as e:
    print("\n[WARN] dash_kpis cross-check failed:", str(e)[:160])

print("\nOpen URLs:")
print(f"{BASE}/vsp5?rid={rid1}")
print(f"{BASE}/vsp5?rid={rid2}")
PY
