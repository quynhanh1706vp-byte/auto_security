#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
GW="wsgi_vsp_ui_gateway.py"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_rescue_gateway_indent_safe_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need python3; need sudo; need systemctl; need curl; need grep; need awk; need sed; need tail

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

[ -f "$GW" ] || fail "missing $GW"

ok "== [P47 RESCUE GW] ts=$TS =="
ok "svc=$SVC"

# 1) pick newest backup that py_compile PASS
picked=""
for f in $(ls -1t ${GW}.bak_* 2>/dev/null | head -n 120); do
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    picked="$f"; break
  fi
done
[ -n "$picked" ] || fail "no compile-pass backup found: ${GW}.bak_*"

cp -f "$GW" "${GW}.bak_before_rescue_${TS}"
ok "backup current: ${GW}.bak_before_rescue_${TS}"

cp -f "$picked" "$GW"
ok "restored gateway from: $picked"
python3 -m py_compile "$GW"
ok "py_compile PASS after restore: $GW"

# 2) indent-aware patch (avoid breaking blocks)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

M1="VSP_ORIG_FLASK_APP_SAVED_V2"
M2="VSP_REPAIR_APP_BEFORE_AFTER_REQUEST_V2"

def insert_after_line(match, insert_lines):
    # insert right AFTER the matched line, respecting indent
    start = match.end()
    return s[:start] + "\n" + insert_lines + s[start:]

# (A) Save original Flask app right after application is created (indent-aware)
if M1 not in s:
    pat = re.compile(r'(?m)^(?P<ind>[ \t]*)application\s*=\s*_p3f_import_vsp_demo_app\(\)\s*$')
    m = pat.search(s)
    if m:
        ind = m.group("ind")
        block = (
            f"{ind}# --- {M1} ---\n"
            f"{ind}try:\n"
            f"{ind}    _VSP_ORIG_FLASK_APP = application\n"
            f"{ind}except Exception:\n"
            f"{ind}    _VSP_ORIG_FLASK_APP = None\n"
            f"{ind}# --- /{M1} ---\n"
        )
        s = s[:m.end()] + "\n" + block + s[m.end():]

# (B) Repair `app` before first @app.after_request (indent-aware)
if M2 not in s:
    pat2 = re.compile(r'(?m)^(?P<ind>[ \t]*)@app\.after_request\s*$')
    m2 = pat2.search(s)
    if m2:
        ind = m2.group("ind")
        guard = (
            f"{ind}# --- {M2} ---\n"
            f"{ind}try:\n"
            f"{ind}    _cand = globals().get('app')\n"
            f"{ind}    _orig = globals().get('_VSP_ORIG_FLASK_APP')\n"
            f"{ind}    if (_cand is None) or (not hasattr(_cand, 'after_request')):\n"
            f"{ind}        if _orig is not None and hasattr(_orig, 'after_request'):\n"
            f"{ind}            app = _orig\n"
            f"{ind}except Exception:\n"
            f"{ind}    pass\n"
            f"{ind}# --- /{M2} ---\n"
        )
        s = s[:m2.start()] + guard + s[m2.start():]

p.write_text(s, encoding="utf-8")
print("[OK] indent-aware gateway patch applied (if patterns found)")
PY

python3 -m py_compile "$GW"
ok "py_compile PASS after patch: $GW"

# 3) restart + probes
ok "restart $SVC"
sudo systemctl restart "$SVC" || true

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

pass=0
for i in $(seq 1 25); do
  c1="$(probe http://127.0.0.1:8910/vsp5)"
  c2="$(probe http://127.0.0.1:8910/api/vsp/dashboard_extras_v1)"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then pass=1; break; fi
  sleep 0.4
done

if [ "$pass" -eq 1 ]; then
  ok "UP: /vsp5=200 and /api/vsp/dashboard_extras_v1=200"
  exit 0
fi

warn "not healthy; dump status+journal+error tail"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null | tee -a "$LOG" >/dev/null || true
fail "still not healthy (see $LOG)"
