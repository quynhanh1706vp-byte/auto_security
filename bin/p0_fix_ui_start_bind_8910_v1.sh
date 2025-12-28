#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixbind_${TS}"
echo "[BACKUP] ${F}.bak_fixbind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# 1) nếu có core.wsgi:application (nhầm sang core service), đổi về gateway UI
s = s.replace("core.wsgi:application", "wsgi_vsp_ui_gateway:application")

# 2) nếu bind 8000 => đổi về 8910 (chỉ các dạng thường gặp)
s = re.sub(r'--bind\s+127\.0\.0\.1:8000', '--bind 127.0.0.1:8910', s)
s = re.sub(r'--bind\s+0\.0\.0\.0:8000', '--bind 127.0.0.1:8910', s)
s = re.sub(r'--bind\s+\[::\]:8000', '--bind 127.0.0.1:8910', s)

# 3) nếu script có check/kill nhầm 8000 (hiếm), đổi về 8910
s = s.replace(":8000", ":8910")

if s == orig:
  print("[WARN] no changes made (did not find core.wsgi or :8000 patterns)")
else:
  p.write_text(s, encoding="utf-8")
  print("[OK] patched start script to bind 8910 + gateway app")

PY

bash -n "$F"
echo "[OK] bash -n OK"
