#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k7b_${TS}"
echo "[BACKUP] ${F}.bak_p3k7b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3K7B_P2BADGES_TIMEOUT_7S_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

lines = s.splitlines(True)

# Strategy:
# - Find region that references rid_latest (badges)
# - In next N lines, if there is setTimeout(...abort..., <small>) => bump to 7000
# - Also bump obvious timeoutMs=xxx / timeout: xxx values in that region if <= 2000
N = 140
NEW_MS = 7000

def bump_timeout_in_line(line: str) -> str:
    # setTimeout(() => ctrl.abort(), 800)
    line2 = re.sub(
        r'(setTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2000 else m.group(2)) + m.group(3),
        line,
        flags=re.I,
    )
    # timeoutMs = 800 / timeout: 800 / timeout=800
    line3 = re.sub(
        r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2000 else m.group(2)),
        line2,
        flags=re.I,
    )
    return line3

changed = False
i = 0
while i < len(lines):
    if "rid_latest" in lines[i]:
        # patch this window
        for j in range(i, min(i+N, len(lines))):
            before = lines[j]
            after = bump_timeout_in_line(before)
            if after != before:
                lines[j] = after
                changed = True
        i += N
        continue
    i += 1

if not changed:
    # fallback: if we didn't touch anything, still inject a safer global guard:
    # increase any abort-related setTimeout <=2000 anywhere in file (still safe)
    s2 = "".join(lines)
    s3 = re.sub(
        r'(setTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2000 else m.group(2)) + m.group(3),
        s2,
        flags=re.I,
    )
    if s3 != s2:
        lines = s3.splitlines(True)
        changed = True

out = "// " + MARK + "\n" + "".join(lines)
p.write_text(out, encoding="utf-8")
print("[OK] patched: bump abort/timeout to", NEW_MS, "ms")
PY

echo "== node -c =="
node -c "$F" >/dev/null
echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k7b_p2badges_increase_timeout_v1"
