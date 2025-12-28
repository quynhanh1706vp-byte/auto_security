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

cp -f "$F" "${F}.bak_p3k9_${TS}"
echo "[BACKUP] ${F}.bak_p3k9_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s0 = p.read_text(encoding="utf-8", errors="replace")
s = s0

MARK="VSP_P3K9_TABS5_BUMP_TIMEOUTS_SLOW_POLLING_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# 1) Bump abort timeouts: any <= 2500ms -> 9000ms
def bump_small_ms(m):
    ms = int(m.group(2))
    if ms <= 2500:
        return m.group(1) + "9000" + m.group(3)
    return m.group(0)

# setTimeout(...abort..., 2000)
s = re.sub(r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
           bump_small_ms, s, flags=re.I)

# timeout: 2000 / timeoutMs: 2000 / timeout_ms: 2000
s = re.sub(r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
           lambda m: m.group(1) + ("9000" if int(m.group(2)) <= 2500 else m.group(2)),
           s, flags=re.I)

# 2) Slow down aggressive polling: setInterval(..., <=5000) -> 15000
def bump_interval(m):
    ms = int(m.group(2))
    if ms <= 5000:
        return m.group(1) + "15000" + m.group(3)
    return m.group(0)

s = re.sub(r'(\bsetInterval\s*\(\s*[\s\S]{0,200}?,\s*)(\d{1,5})(\s*\))',
           bump_interval, s, flags=re.I)

# 3) Silence noisy timeout label (cosmetic)
s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest slow (ignored)")

changed = (s != s0)
if changed:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[SKIP] no change (patterns not found)")

PY

echo "== node -c =="
node -c "$F" >/dev/null && echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,160p' || true
  sudo journalctl -u "$SVC" -n 160 --no-pager || true
  exit 3
}

echo "[DONE] p3k9_tabs5_bump_timeouts_and_slow_polling_v1"
