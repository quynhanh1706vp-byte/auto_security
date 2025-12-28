#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

echo "== [1] find dashboard datasource callers =="
mapfile -t files < <(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' \
  '/api/vsp/datasource?mode=dashboard' static/js || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "[ERR] no JS file references '/api/vsp/datasource?mode=dashboard' under static/js"
  echo "Hint: grep -RIn '/api/vsp/datasource' static/js | head"
  exit 2
fi

printf "[FOUND] %s\n" "${files[@]}"

echo "== [2] patch JS -> datasource_lite (+limit) =="
python3 - <<'PY'
from pathlib import Path
import re, time

files = []
import subprocess, shlex, os, sys

# read file list from grep output saved by shell in env? no; re-run safely in python
import glob
# shell already printed list; we'll re-discover deterministically:
import subprocess
out = subprocess.check_output(["bash","-lc",
    "grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' '/api/vsp/datasource?mode=dashboard' static/js || true"
], text=True)
files = [x.strip() for x in out.splitlines() if x.strip()]

ts = time.strftime("%Y%m%d_%H%M%S")
patched = 0

for f in files:
    p = Path(f)
    s = p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P3G_DASH_USE_DATASOURCE_LITE_V1" in s:
        print("[SKIP] already patched:", f)
        continue

    bak = p.with_name(p.name + f".bak_p3g_{ts}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    # Replace exact dashboard datasource endpoint
    s2 = s.replace("/api/vsp/datasource?mode=dashboard", "/api/vsp/datasource_lite?mode=dashboard")

    # Ensure limit param exists when building URL (best effort):
    # If code already appends '&rid=' etc, we add '&limit=800' once.
    if "datasource_lite" in s2:
        # add a marker comment near top
        s2 = "/* VSP_P3G_DASH_USE_DATASOURCE_LITE_V1 */\n" + s2
        # add limit=800 if not present anywhere
        if "limit=" not in s2:
            # add '&limit=800' right after 'datasource_lite?mode=dashboard'
            s2 = s2.replace("datasource_lite?mode=dashboard", "datasource_lite?mode=dashboard&limit=800")

    p.write_text(s2, encoding="utf-8")
    patched += 1
    print("[OK] patched:", f)

print("[DONE] patched_files=", patched)
PY

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^${SVC}"; then
    sudo systemctl restart "${SVC}"
    sleep 0.6
    sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }
  else
    echo "[WARN] unit not found: ${SVC} (skip restart)"
  fi
fi

echo "== [4] smoke: dashboard datasource_lite =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/datasource_lite?rid=$RID&limit=200" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); sm=j.get("summary") or {}; print("ok=",j.get("ok"),"findings=",len(j.get("findings") or []),"total=",sm.get("findings_total"),"lite=",sm.get("lite"))'

echo "[DONE] p3g_dashboard_use_datasource_lite_v1"
