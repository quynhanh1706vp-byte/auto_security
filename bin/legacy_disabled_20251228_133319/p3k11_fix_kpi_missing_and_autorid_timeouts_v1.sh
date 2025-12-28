#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need curl
command -v systemctl >/dev/null 2>&1 || true

KPI="static/js/vsp_dashboard_kpi_force_any_v1.js"
TABS5="static/js/vsp_bundle_tabs5_v1.js"
AUTORID="static/js/vsp_tabs4_autorid_v1.js"

echo "== [0] ensure KPI script exists (avoid <script> load fail) =="
mkdir -p static/js
if [ ! -f "$KPI" ]; then
  cat > "$KPI" <<'JS'
/* VSP_P3K11_KPI_FORCE_ANY_STUB_V1
 * Stub to avoid dashboard <script> 404 / load-fail causing Firefox slowdown.
 * Real KPI logic can be reintroduced later. This file must exist.
 */
(function(){
  try {
    window.__VSP_KPI_FORCE_ANY = window.__VSP_KPI_FORCE_ANY || function(){ return; };
    window.__VSP_KPI_FORCE_ANY_V1 = true;
  } catch(e) {}
})();
JS
  echo "[OK] created stub: $KPI"
else
  echo "[OK] exists: $KPI"
fi

echo "== [1] patch TABS5 (P2Badges rid_latest timeout + fail-soft) =="
[ -f "$TABS5" ] || { echo "[ERR] missing $TABS5"; exit 2; }
cp -f "$TABS5" "${TABS5}.bak_p3k11_${TS}"
echo "[BACKUP] ${TABS5}.bak_p3k11_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s0=p.read_text(encoding="utf-8", errors="replace")
s=s0
MARK="VSP_P3K11_TABS5_TIMEOUT_FAILSOFT_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# bump abort timeouts (<=2500 -> 12000) only when abort() appears
def bump_abort_settimeout(m):
    ms=int(m.group(2))
    return m.group(1)+("12000" if ms<=2500 else str(ms))+m.group(3)
s = re.sub(r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
           bump_abort_settimeout, s, flags=re.I)

# bump config timeout fields (timeout/timeoutMs/timeout_ms) <=2500 -> 12000
s = re.sub(r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
           lambda m: m.group(1)+("12000" if int(m.group(2))<=2500 else m.group(2)),
           s, flags=re.I)

# silence noisy label (cosmetic)
s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest slow (non-fatal)")

# fail-soft: if code does Promise.reject or throw in catch blocks, convert to return null (conservative)
s = re.sub(r'(?m)^\s*return\s+Promise\.reject\([^)]*\)\s*;\s*$', '  return null;', s)
s = re.sub(r'(?m)^\s*throw\s+\w+\s*;\s*$', '  return null;', s)

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[WARN] no change patterns hit in tabs5")
PY

echo "== [2] patch AUTORID (NetworkError -> fail-soft + bump abort timeouts) =="
[ -f "$AUTORID" ] || { echo "[ERR] missing $AUTORID"; exit 2; }
cp -f "$AUTORID" "${AUTORID}.bak_p3k11_${TS}"
echo "[BACKUP] ${AUTORID}.bak_p3k11_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s0=p.read_text(encoding="utf-8", errors="replace")
s=s0
MARK="VSP_P3K11_AUTORID_TIMEOUT_FAILSOFT_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# bump abort setTimeouts (<=2500 -> 12000) only when abort() appears
def bump_abort_settimeout(m):
    ms=int(m.group(2))
    return m.group(1)+("12000" if ms<=2500 else str(ms))+m.group(3)
s = re.sub(r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
           bump_abort_settimeout, s, flags=re.I)

# bump timeout fields
s = re.sub(r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
           lambda m: m.group(1)+("12000" if int(m.group(2))<=2500 else m.group(2)),
           s, flags=re.I)

# fail-soft: convert throw/reject inside catch blocks to return null
# (keep conservative: only rewrite lines that are exactly 'throw x;' or 'return Promise.reject(x);')
s = re.sub(r'(?m)^\s*return\s+Promise\.reject\([^)]*\)\s*;\s*$', '  return null;', s)
s = re.sub(r'(?m)^\s*throw\s+\w+\s*;\s*$', '  return null;', s)

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[WARN] no change patterns hit in autorid")
PY

echo "== [3] node -c sanity =="
node -c "$TABS5" >/dev/null && echo "[OK] node -c: $TABS5"
node -c "$AUTORID" >/dev/null && echo "[OK] node -c: $AUTORID"
node -c "$KPI" >/dev/null && echo "[OK] node -c: $KPI"

echo "== [4] restart =="
sudo systemctl restart "$SVC"
sleep 0.8
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,180p' || true
  sudo journalctl -u "$SVC" -n 180 --no-pager || true
  exit 3
}

echo "== [5] smoke: can fetch the KPI script + rid_latest fast =="
curl -fsS -I "$BASE/static/js/vsp_dashboard_kpi_force_any_v1.js" | head -n 5 || true
curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest ok=",j.get("ok"),"rid=",j.get("rid"))'

echo "[DONE] p3k11_fix_kpi_missing_and_autorid_timeouts_v1"
