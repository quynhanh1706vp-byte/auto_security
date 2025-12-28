#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need sed
command -v node >/dev/null 2>&1 || { echo "[ERR] node required"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, subprocess, time

cur = Path("static/js/vsp_runs_tab_resolved_v1.js")
if not cur.exists():
    raise SystemExit("[ERR] missing " + str(cur))

# collect backups
cand = []
for p in cur.parent.glob(cur.name + ".bak_*"):
    cand.append(p)

# also consider current (for scoring)
cand.append(cur)

def node_ok(p: Path) -> bool:
    try:
        r = subprocess.run(["node","--check",str(p)], capture_output=True, text=True)
        return r.returncode == 0
    except Exception:
        return False

def score_text(s: str) -> int:
    t = s
    sc = 0
    # must not be stub
    if "=> STUB" in t or "STUB" in t and len(t) < 2000:
        sc -= 999
    # strong signals of real renderer
    keys = [
        "Open Summary", "Open Data Source", "Artifacts", "Quick open",
        "runs?limit", "/api/vsp/runs", "render", "tbody", "table", "filter"
    ]
    for k in keys:
        if k in t: sc += 3
    # prefer files with more code
    sc += min(len(t)//2000, 30)
    # penalize minified tiny or empty
    if len(t) < 1500: sc -= 50
    return sc

best = None
best_sc = -10**9
for p in cand:
    s = p.read_text(encoding="utf-8", errors="replace")
    ok = node_ok(p)
    if not ok:
        continue
    sc = score_text(s)
    # strongly reject stub-like
    if sc < -200:
        continue
    # prefer backups over current if current is stub
    if sc > best_sc:
        best_sc = sc
        best = p

if best is None:
    raise SystemExit("[ERR] no valid backup passes node --check. list your backups:\n" +
                     "\n".join(str(x) for x in sorted(cur.parent.glob(cur.name+".bak_*"))))

# if best is current and it is OK, still print
print("[PICK] best =", best, "score=", best_sc)

# if best is a backup, restore it
if best != cur:
    bak = cur.with_name(cur.name + f".bak_before_restore_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(cur.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    cur.write_text(best.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[RESTORE] current <= ", best)
    print("[BACKUP] current saved as", bak)
else:
    print("[OK] current already best")

# final check
subprocess.check_call(["node","--check", str(cur)])
print("[OK] node --check current OK")
PY

echo "[INFO] restart UI clean"
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== quick sanity =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,10p' || true
curl -sS http://127.0.0.1:8910/runs | head -n 20 | sed -n '1,20p' || true
