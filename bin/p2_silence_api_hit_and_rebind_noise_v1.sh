#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P2_SILENCE_API_HIT_REBIND_NOISE_V1"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_silence_noise_${TS}"
echo "[BACKUP] ${APP}.bak_silence_noise_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_COMMERCIAL_SILENCE_NOISE" not in s:
    # inject helper near top
    inject = f'''
# --- { "VSP_P2_SILENCE_API_HIT_REBIND_NOISE_V1" } ---
import os as _os
def _vsp_noise_enabled():
    # 1 = print noise, 0/empty = silence
    return (_os.environ.get("VSP_COMMERCIAL_SILENCE_NOISE","1") == "1")
# --- end ---
'''.lstrip("\n")
    # place after first imports
    m=re.search(r'(?m)^(import|from)\s+', s)
    if m:
        # insert before first import is risky; insert at first import line start
        idx=m.start()
        s = s[:idx] + inject + "\n" + s[idx:]
    else:
        s = inject + "\n" + s

# wrap known noisy prints
s = re.sub(r'(?m)^\s*print\(\s*"\[VSP_API_HIT\].*$', lambda m: ("    if _vsp_noise_enabled():\n" + m.group(0)), s)
s = re.sub(r'(?m)^\s*print\(\s*"\[VSP_EXPORT_FORCE_BIND_V5\].*$', lambda m: ("    if _vsp_noise_enabled():\n" + m.group(0)), s)

p.write_text(s, encoding="utf-8")
print("[OK] patched noise gating (set VSP_COMMERCIAL_SILENCE_NOISE=0 to silence)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  # silence by default for commercial
  sudo systemctl set-environment VSP_COMMERCIAL_SILENCE_NOISE=0 >/dev/null 2>&1 || true
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; restart manually and export VSP_COMMERCIAL_SILENCE_NOISE=0"
fi
