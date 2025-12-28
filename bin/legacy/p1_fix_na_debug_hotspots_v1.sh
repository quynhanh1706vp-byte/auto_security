#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

patch_file(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_hotfix_${TS}"
  python3 - "$f" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# 1) Replace common UI substrings containing N/A (not logic tokens)
s=s.replace("Run: N/A","Run: —")
s=s.replace(">N/A<",">—<")
s=s.replace("(N/A)","(—)")
s=s.replace("findings: N/A","findings: —")
s=s.replace("time: N/A","time: —")

# 2) Replace direct assignments of "N/A" for textContent only
s=re.sub(r'(\.textContent\s*=\s*)(["\'])N/A\2', r'\1"—"', s)

# 3) Kill noisy DEBUG init console.log lines (settings_render.js)
s=re.sub(r'(?m)^\s*console\.log\([^\n]*\[VSP\]\[DEBUG\][^\n]*\);\s*$', '', s)

p.write_text(s, encoding="utf-8")
print("[OK] patched", p, "changed=", (s!=orig))
PY
}

patch_file static/js/security_bundle.js
patch_file static/js/settings_render.js
patch_file static/js/vsp_ui_extras_v25.js

echo "[DONE] backups: *.bak_hotfix_${TS}"
