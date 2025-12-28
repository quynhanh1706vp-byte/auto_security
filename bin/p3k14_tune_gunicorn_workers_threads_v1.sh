#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need date; need python3; need grep; need sed

# locate unit file
UNIT_PATH="$(systemctl show -p FragmentPath --value "$SVC" 2>/dev/null || true)"
[ -n "$UNIT_PATH" ] || { echo "[ERR] cannot locate unit file for $SVC"; exit 2; }
[ -f "$UNIT_PATH" ] || { echo "[ERR] unit file not found: $UNIT_PATH"; exit 2; }

echo "[INFO] unit=$UNIT_PATH"
sudo cp -f "$UNIT_PATH" "${UNIT_PATH}.bak_p3k14_${TS}"
echo "[BACKUP] ${UNIT_PATH}.bak_p3k14_${TS}"

python3 - <<PY
from pathlib import Path
import re, sys

unit = Path("$UNIT_PATH")
s = unit.read_text(encoding="utf-8", errors="replace")

# Find ExecStart line
m = re.search(r'(?m)^ExecStart=(.+)$', s)
if not m:
    print("[ERR] ExecStart not found in unit")
    sys.exit(2)

line = m.group(1)

# If it's gunicorn, enforce gthread concurrency
# Add/replace: --workers 2 --threads 8 --worker-class gthread --timeout 120 --keep-alive 5
def upsert_flag(cmd, key, val):
    # replace forms: --key N OR --key=N
    cmd2 = re.sub(rf'(\s--{re.escape(key)})(?:\s+\S+|=\S+)', rf'\\1 {val}', cmd)
    if cmd2 != cmd:
        return cmd2, True
    # add
    return cmd + f' --{key} {val}', True

changed = False

# normalize short -w if present
line2 = re.sub(r'(\s-w\s+)\d+', r'\g<1>2', line)
if line2 != line:
    line = line2
    changed = True

# ensure worker-class gthread
if "--worker-class" in line:
    line2 = re.sub(r'(\s--worker-class)(?:\s+\S+|=\S+)', r'\1 gthread', line)
    if line2 != line:
        line = line2
        changed = True
else:
    line += " --worker-class gthread"
    changed = True

# ensure workers
if ("--workers" in line) or (" -w " in line):
    # if --workers exists, force 2
    if "--workers" in line:
        line2 = re.sub(r'(\s--workers)(?:\s+\S+|=\S+)', r'\1 2', line)
        if line2 != line:
            line = line2
            changed = True
else:
    line += " --workers 2"
    changed = True

# ensure threads
if "--threads" in line:
    line2 = re.sub(r'(\s--threads)(?:\s+\S+|=\S+)', r'\1 8', line)
    if line2 != line:
        line = line2
        changed = True
else:
    line += " --threads 8"
    changed = True

# ensure timeout
if "--timeout" in line:
    line2 = re.sub(r'(\s--timeout)(?:\s+\S+|=\S+)', r'\1 120', line)
    if line2 != line:
        line = line2
        changed = True
else:
    line += " --timeout 120"
    changed = True

# ensure keep-alive
if "--keep-alive" in line:
    line2 = re.sub(r'(\s--keep-alive)(?:\s+\S+|=\S+)', r'\1 5', line)
    if line2 != line:
        line = line2
        changed = True
else:
    line += " --keep-alive 5"
    changed = True

if not changed:
    print("[WARN] ExecStart unchanged (already tuned?)")
    sys.exit(0)

s2 = re.sub(r'(?m)^ExecStart=.+$', "ExecStart=" + line, s)
unit.write_text(s2, encoding="utf-8")
print("[OK] patched ExecStart with workers/threads/gthread")
PY

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== quick static timing smoke =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for u in \
  "$BASE/static/js/vsp_bundle_tabs5_v1.js" \
  "$BASE/static/css/vsp_dark_commercial_p1_2.css"
do
  curl -fsS -w "time=%{time_total} http=%{http_code} url=$u\n" -o /dev/null "$u" || true
done

echo "[DONE] p3k14_tune_gunicorn_workers_threads_v1"
