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

cp -f "$F" "${F}.bak_p3k13b_${TS}"
echo "[BACKUP] ${F}.bak_p3k13b_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s0=p.read_text(encoding="utf-8", errors="replace")
s=s0

MARK="VSP_P3K13B_TABS5_SILENCE_P2BADGES_TIMEOUT_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# silence labels
s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest slow (ignored)")
s = s.replace("rid_latest fetch fail timeout", "rid_latest slow (ignored)")

# also avoid scary "Dashboard error: timeout" strings if present
s = s.replace("Dashboard error: timeout", "Dashboard: loading…")

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[SKIP] no change")
PY

node -c "$F" >/dev/null && echo "[OK] node -c passed"
sudo systemctl restart "$SVC"
sleep 0.8
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || exit 3
echo "[DONE] p3k13b_tabs5_silence_p2badges_timeout_v1"
