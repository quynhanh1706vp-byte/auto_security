#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

echo "== [0] find files containing 'Dashboard error: timeout' =="
mapfile -t files < <(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' 'Dashboard error: timeout' static/js || true)
if [ "${#files[@]}" -eq 0 ]; then
  echo "[WARN] not found string in static/js (maybe generated elsewhere)"
else
  printf '[FOUND] %s\n' "${files[@]}"
fi

python3 - <<'PY'
from pathlib import Path
import glob

MARK="VSP_P3K18_MUTE_DASHBOARD_TIMEOUT_LABEL_V1"
targets=[]
for fp in glob.glob("static/js/*.js"):
    p=Path(fp)
    s=p.read_text(encoding="utf-8", errors="replace")
    if "Dashboard error: timeout" in s and MARK not in s:
        targets.append(p)

for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_suffix(p.suffix + f".bak_p3k18_{__import__('time').strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    s2 = f"/* === {MARK} === */\n" + s.replace("Dashboard error: timeout", "")
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p)

print("[DONE] patched_files=", len(targets))
PY

# syntax check patched files quickly
for f in static/js/*.js; do node -c "$f" >/dev/null 2>&1 || { echo "[ERR] node -c fail: $f"; exit 3; }; done
echo "[OK] node -c all js passed"

sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 4; }

echo "[DONE] p3k18_mute_dashboard_error_timeout_label_v1"
