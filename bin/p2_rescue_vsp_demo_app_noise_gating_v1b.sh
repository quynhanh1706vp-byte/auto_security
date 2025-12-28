#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need curl

# Pick a known-good backup (the one created before the broken noise patch)
bak="$(ls -1t ${APP}.bak_silence_noise_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] cannot find backup: ${APP}.bak_silence_noise_*"
  ls -1 ${APP}.bak_* 2>/dev/null | tail -n 30 || true
  exit 2
fi

cp -f "$bak" "$APP"
echo "[OK] restored $APP from $bak"

# Patch safely:
# - Add helper _vsp_noise_enabled() (default silent)
# - Convert lines that print the noise tags:
#   * If print(...) and return ... appear on SAME line -> split into 2 lines
#   * Else convert to one-liner: if _vsp_noise_enabled(): print(...)
python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_NOISE_GATING_SAFE_SPLIT_V1B"
if marker in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

helper = '''
# --- VSP_P2_NOISE_GATING_SAFE_SPLIT_V1B ---
import os as _os
def _vsp_noise_enabled():
    # default SILENT for commercial; set VSP_COMMERCIAL_SILENCE_NOISE=1 to enable prints
    return (_os.environ.get("VSP_COMMERCIAL_SILENCE_NOISE","0") == "1")
# --- end ---
'''.lstrip("\n")

if "_vsp_noise_enabled" not in s:
    m=re.search(r'(?m)^(import|from)\s+[^\n]+\n', s)
    if m:
        idx=m.end()
        s = s[:idx] + helper + "\n" + s[idx:]
    else:
        s = helper + "\n" + s

tags = ["[VSP_API_HIT]", "[VSP_EXPORT_FORCE_BIND_V5]"]

out=[]
changed=0

for line in s.splitlines(True):
    l=line
    if "print(" in l and any(t in l for t in tags):
        # Case 1: print(...) + return ... on same line -> split safely
        m = re.match(r'^(\s*)print\((.*)\)\s*(return\b.*)$', l)
        if m:
            indent=m.group(1)
            inside=m.group(2).rstrip()
            ret=m.group(3).rstrip()
            out.append(f"{indent}if _vsp_noise_enabled(): print({inside})\n")
            out.append(f"{indent}{ret}\n")
            changed += 1
            continue

        # Case 2: pure print(...) line
        m = re.match(r'^(\s*)print\((.*)\)\s*$', l)
        if m:
            indent=m.group(1)
            inside=m.group(2).rstrip()
            out.append(f"{indent}if _vsp_noise_enabled(): print({inside})\n")
            changed += 1
            continue

        # Case 3: print(...) but with trailing stuff -> safest: wrap as one-liner, keep rest
        # e.g. "print(...); x=1" (rare)
        l = re.sub(r'^(\s*)print\((.*)\)\s*;\s*', r'\1if _vsp_noise_enabled(): print(\2)\n\1', l)
        out.append(l)
        changed += 1
        continue

    out.append(l)

s2="".join(out) + f"\n# {marker}\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] converted noisy print lines: {changed}")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK: $APP"

# restart service
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl set-environment VSP_COMMERCIAL_SILENCE_NOISE=0 >/dev/null 2>&1 || true
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; restart manually"
fi

# quick sanity
echo "== quick sanity =="
curl -fsS "$BASE/api/vsp/ui_health_v2" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "ready=", j.get("ready"), "marker=", j.get("marker"))
PY
