#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need sudo; need systemctl; need curl; need ss

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_apihitgw_v1n4_${TS}"
ok "backup: ${F}.bak_apihitgw_v1n4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_P0_API_HITLOG_WSGI_V1N3" not in s:
    raise SystemExit("[ERR] V1N3 marker not found. Did you patch V1N3 in this file?")

# Replace the print(...) line inside V1N3 wrapper with wsgi.errors write
# Robust: replace any line containing [VSP_API_HIT] print(...)
pat = re.compile(r'^\s*print\(f"\[VSP_API_HIT\]\s*\{method\}\s*\{full\}"[^)]*\)\s*$', re.M)
if not pat.search(s):
    # fallback: replace any print line that contains [VSP_API_HIT]
    pat2 = re.compile(r'^\s*print\(.*\[VSP_API_HIT\].*\)\s*$', re.M)
    if not pat2.search(s):
        raise SystemExit("[ERR] Could not find VSP_API_HIT print() line to replace.")
    pat = pat2

repl = r'''                    try:
                        _e = environ.get("wsgi.errors")
                        if _e:
                            _e.write(f"[VSP_API_HIT] {method} {full}\n")
                            _e.flush()
                        else:
                            # fallback
                            print(f"[VSP_API_HIT] {method} {full}", flush=True)
                    except Exception:
                        pass'''

s2 = pat.sub(repl, s, count=1)

# Add marker for v1n4
if "VSP_P0_API_HITLOG_WSGI_V1N4" not in s2:
    s2 = s2.replace("VSP_P0_API_HITLOG_WSGI_V1N3", "VSP_P0_API_HITLOG_WSGI_V1N3\n# VSP_P0_API_HITLOG_WSGI_V1N4: log via wsgi.errors (journald-safe)")

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK")
PY

ok "py_compile OK: $F"
node --check "$F" && ok "node --check OK: $F" || err "node --check FAIL: $F"

sudo systemctl daemon-reload || true
sudo systemctl restart vsp-ui-8910.service

for i in $(seq 1 60); do
  ss -ltnp | grep -q ':8910' && break
  sleep 0.25
done
ss -ltnp | grep -q ':8910' || err "8910 not listening"

# generate hits
curl -fsS "http://127.0.0.1:8910/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "http://127.0.0.1:8910/api/vsp/rid_latest" >/dev/null || true
curl -fsS "http://127.0.0.1:8910/api/vsp/release_latest" >/dev/null || true

echo "== [CHECK] VSP_API_HIT in last 30s =="
sudo journalctl -u vsp-ui-8910.service --since "30 seconds ago" --no-pager -o cat | grep '\[VSP_API_HIT\]' | tail -n 80 || true
