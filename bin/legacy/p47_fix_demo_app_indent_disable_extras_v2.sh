#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
OUT="out_ci"; mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need ls; need head; need grep; need sudo; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_fix_demo_app_v2_${TS}.txt"
ok(){ echo "[OK] $*" | tee -a "$LOG"; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

echo "== [P47 FIX v2] restore demo_app + disable extras decorator ==" | tee "$LOG"

[ -f "$APP" ] || fail "missing $APP"

# 1) backup current broken file
cp -f "$APP" "${APP}.bak_before_fixv2_${TS}"
ok "backup: ${APP}.bak_before_fixv2_${TS}"

# 2) restore from latest clean backup created by previous script (before the bad edit)
BAK="$(ls -1t ${APP}.bak_extras_disable_* 2>/dev/null | head -n 1 || true)"
if [ -z "$BAK" ]; then
  # fallback to any recent rescue backup
  BAK="$(ls -1t ${APP}.bak_extras_rescue_* 2>/dev/null | head -n 1 || true)"
fi
[ -n "$BAK" ] || fail "no backup found: ${APP}.bak_extras_disable_* (or bak_extras_rescue_*)"

cp -f "$BAK" "$APP"
ok "restored: $BAK -> $APP"

# 3) minimal patch: comment ONLY the decorator lines for /api/vsp/dashboard_extras_v1
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# comment only decorator lines, do NOT touch following code
pat = re.compile(r'(?m)^[ \t]*@app\.route\((["\'])/api/vsp/dashboard_extras_v1\1[^)]*\)\s*$')
new, n = pat.subn(lambda m: "# [DISABLED_BY_P47_FIX_V2] " + m.group(0).lstrip(), s)

# also cover cases with spaces and methods on next lines (rare), still safest to only kill the line containing path
pat2 = re.compile(r'(?m)^[ \t]*@app\.route\([^\\n]*dashboard_extras_v1[^\\n]*\)\s*$')
new2, n2 = pat2.subn(lambda m: "# [DISABLED_BY_P47_FIX_V2] " + m.group(0).lstrip(), new)

p.write_text(new2, encoding="utf-8")
print(f"[OK] disabled decorator lines: exact={n}, loose={n2}")
PY

# 4) compile check
python3 -m py_compile "$APP" || fail "py_compile failed (still indent error) -> open ${APP}.bak_before_fixv2_${TS} and current file diff"
ok "py_compile PASS: $APP"

# 5) restart + probes
ok "restart $SVC"
sudo systemctl restart "$SVC" || true

# wait up to ~8s
pass=0
for i in $(seq 1 20); do
  c1="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/vsp5 2>/dev/null || true)"
  c2="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/api/vsp/dashboard_extras_v1 2>/dev/null || true)"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then pass=1; break; fi
  sleep 0.4
done

if [ "$pass" -eq 1 ]; then
  ok "UP: /vsp5=200 and /api/vsp/dashboard_extras_v1=200"
  exit 0
fi

echo "== status ==" | tee -a "$LOG"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
echo "== journal tail ==" | tee -a "$LOG"
sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
fail "service not healthy after fix v2 (see $LOG)"
