#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need date; need python3; need curl

UNIT_PATH="$(systemctl show -p FragmentPath --value "$SVC" 2>/dev/null || true)"
[ -n "$UNIT_PATH" ] || { echo "[ERR] cannot locate unit file for $SVC"; exit 2; }
[ -f "$UNIT_PATH" ] || { echo "[ERR] unit file not found: $UNIT_PATH"; exit 2; }

echo "[INFO] unit=$UNIT_PATH"
sudo cp -f "$UNIT_PATH" "${UNIT_PATH}.bak_p3k14v2_${TS}"
echo "[BACKUP] ${UNIT_PATH}.bak_p3k14v2_${TS}"

tmp="$(mktemp /tmp/vsp_unit_patch_XXXXXX)"
trap 'rm -f "$tmp"' EXIT

python3 - <<PY >"$tmp"
from pathlib import Path
import re, sys

unit = Path("$UNIT_PATH")
s = unit.read_text(encoding="utf-8", errors="replace")

m = re.search(r'(?m)^ExecStart=(.+)$', s)
if not m:
    print(s, end="")
    sys.stderr.write("[ERR] ExecStart not found\\n")
    sys.exit(2)

line = m.group(1).strip()

# only patch if gunicorn is used (avoid breaking non-gunicorn services)
if "gunicorn" not in line:
    print(s, end="")
    sys.stderr.write("[ERR] ExecStart is not gunicorn; abort to avoid breaking service\\n")
    sys.stderr.write(f"[INFO] ExecStart={line}\\n")
    sys.exit(3)

changed = False

# normalize -w
line2 = re.sub(r'(\s-w\s+)\d+', r'\g<1>2', line)
if line2 != line:
    line = line2; changed = True

def force_flag(cmd, key, val):
    # replace --key N or --key=N
    cmd2 = re.sub(rf'(\s--{re.escape(key)})(?:\s+\S+|=\S+)', rf'\\1 {val}', cmd)
    if cmd2 != cmd:
        return cmd2, True
    return (cmd + f' --{key} {val}'), True

# worker-class gthread
if "--worker-class" in line:
    line2 = re.sub(r'(\s--worker-class)(?:\s+\S+|=\S+)', r'\1 gthread', line)
    if line2 != line:
        line = line2; changed = True
else:
    line += " --worker-class gthread"; changed = True

# workers
if "--workers" in line:
    line2 = re.sub(r'(\s--workers)(?:\s+\S+|=\S+)', r'\1 2', line)
    if line2 != line:
        line = line2; changed = True
else:
    line += " --workers 2"; changed = True

# threads
if "--threads" in line:
    line2 = re.sub(r'(\s--threads)(?:\s+\S+|=\S+)', r'\1 8', line)
    if line2 != line:
        line = line2; changed = True
else:
    line += " --threads 8"; changed = True

# timeout
if "--timeout" in line:
    line2 = re.sub(r'(\s--timeout)(?:\s+\S+|=\S+)', r'\1 120', line)
    if line2 != line:
        line = line2; changed = True
else:
    line += " --timeout 120"; changed = True

# keep-alive
if "--keep-alive" in line:
    line2 = re.sub(r'(\s--keep-alive)(?:\s+\S+|=\S+)', r'\1 5', line)
    if line2 != line:
        line = line2; changed = True
else:
    line += " --keep-alive 5"; changed = True

if not changed:
    sys.stderr.write("[WARN] ExecStart unchanged (already tuned?)\\n")

s2 = re.sub(r'(?m)^ExecStart=.+$', "ExecStart=" + line, s)
print(s2, end="")
PY

echo "== write unit via sudo tee =="
sudo tee "$UNIT_PATH" >/dev/null < "$tmp"

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 4; }

echo "== quick static timing smoke =="
for u in \
  "$BASE/static/js/vsp_bundle_tabs5_v1.js" \
  "$BASE/static/css/vsp_dark_commercial_p1_2.css"
do
  curl -fsS -w "time=%{time_total} http=%{http_code} url=$u\n" -o /dev/null "$u" || true
done

echo "[DONE] p3k14_tune_gunicorn_workers_threads_v2"
