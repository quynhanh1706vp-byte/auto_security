#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head

bak="$(ls -1t ${APP}.bak_silence_noise_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] cannot find backup: ${APP}.bak_silence_noise_*"
  ls -1 ${APP}.bak_* 2>/dev/null | tail -n 30 || true
  exit 2
fi

cp -f "$bak" "$APP"
echo "[OK] restored $APP from $bak"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_NOISE_GATING_ONELINER_V1"
if marker in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

# ensure helper exists near top
helper = '''
# --- VSP_P2_NOISE_GATING_ONELINER_V1 ---
import os as _os
def _vsp_noise_enabled():
    # default SILENT for commercial; set VSP_COMMERCIAL_SILENCE_NOISE=1 to enable prints
    return (_os.environ.get("VSP_COMMERCIAL_SILENCE_NOISE","0") == "1")
# --- end ---
'''.lstrip("\n")

if "_vsp_noise_enabled" not in s:
    # insert after first import line if possible
    m=re.search(r'(?m)^(import|from)\s+[^\n]+\n', s)
    if m:
        idx=m.end()
        s = s[:idx] + helper + "\n" + s[idx:]
    else:
        s = helper + "\n" + s

def repl(line, tag):
    # preserve indentation and keep 1-line statement to avoid indent issues
    m=re.match(r'^(\s*)print\(\s*("|\')(\[' + re.escape(tag) + r'.*?)\2\s*\)\s*$', line)
    if not m:
        return line, False
    indent=m.group(1)
    quote=m.group(2)
    msg=m.group(3)
    return f'{indent}if _vsp_noise_enabled(): print({quote}{msg}{quote})\n', True

out=[]
changed=0
for line in s.splitlines(True):
    l=line
    # match by prefixes (simpler & robust)
    if re.search(r'^\s*print\(\s*["\']\[VSP_API_HIT\]', l):
        # convert to 1-liner
        l = re.sub(r'^(\s*)print\((.*)\)\s*$', r'\1if _vsp_noise_enabled(): print(\2)', l)
        changed += 1
    if re.search(r'^\s*print\(\s*["\']\[VSP_EXPORT_FORCE_BIND_V5\]', l):
        l = re.sub(r'^(\s*)print\((.*)\)\s*$', r'\1if _vsp_noise_enabled(): print(\2)', l)
        changed += 1
    out.append(l)

s2="".join(out)
s2 += "\n# " + marker + "\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] converted noisy prints: {changed}")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK: $APP"

if command -v systemctl >/dev/null 2>&1; then
  # silence by default
  sudo systemctl set-environment VSP_COMMERCIAL_SILENCE_NOISE=0 >/dev/null 2>&1 || true
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; export VSP_COMMERCIAL_SILENCE_NOISE=0 and restart service manually"
fi

echo "[OK] done: noise gating fixed (default silent)"
