#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need date; need python3; need ss; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
DROP="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

sudo mkdir -p "$DROP"

echo "== [1] disable ALL accesslog drop-ins (current, even if resurrected) =="
sudo bash -lc "ls -1 $DROP/override_accesslog*.conf 2>/dev/null || true" | while read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  sudo mv -f "$f" "$DROP/${base}.disabled_${TS}"
  ok "disabled: $base"
done
# also disable the v1m7 file if present
if sudo test -f "$DROP/override_accesslog_safe_v1m7.conf"; then
  sudo mv -f "$DROP/override_accesslog_safe_v1m7.conf" "$DROP/override_accesslog_safe_v1m7.conf.disabled_${TS}"
  ok "disabled: override_accesslog_safe_v1m7.conf"
fi

echo "== [2] ensure SAFE journald override exists (capture-output only) =="
cat > /tmp/override_journald_v1n0.conf <<'CONF'
[Service]
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
Environment="GUNICORN_CMD_ARGS=--capture-output"
CONF
sudo cp -f /tmp/override_journald_v1n0.conf "$DROP/override_journald_v1n0.conf"
ok "written: $DROP/override_journald_v1n0.conf"

echo "== [3] patch vsp_demo_app.py to log /api/vsp/* hits into journal =="
APP="vsp_demo_app.py"
[ -f "$APP" ] || err "missing $APP"
cp -f "$APP" "${APP}.bak_apihit_${TS}"
ok "backup: ${APP}.bak_apihit_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")
MARK = "VSP_P0_API_HITLOG_V1N0"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# ensure flask.request is imported
if not re.search(r'from\s+flask\s+import\s+.*\brequest\b', s):
    # try to extend existing "from flask import ..." line if present
    m = re.search(r'^(from\s+flask\s+import\s+.+)$', s, flags=re.M)
    if m:
        line = m.group(1)
        if "request" not in line:
            newline = line.rstrip() + ", request"
            s = s[:m.start(1)] + newline + s[m.end(1):]
    else:
        # fallback: add a safe import near top
        s = "from flask import request\n" + s

# inject hook after app creation
m = re.search(r'^\s*app\s*=\s*Flask\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate app = Flask(...) in vsp_demo_app.py")

inject = f'''
# {MARK}: commercial audit logging (no gunicorn accesslog needed)
try:
    @app.before_request
    def __vsp_api_hitlog_v1n0():
        try:
            # only log VSP API calls
            if request.path and request.path.startswith("/api/vsp/"):
                fp = getattr(request, "full_path", request.path) or request.path
                # trim noisy ts=
                fp = re.sub(r'([?&])ts=\\d+', r'\\1ts=', fp)
                print(f"[VSP_API_HIT] {{request.method}} {{fp}}")
        except Exception:
            pass
except Exception:
    pass
'''

# need re module for sub inside hook, ensure imported
if "import re" not in s:
    # place near top
    s = "import re\n" + s

# place inject right after the line containing "app = Flask("
pos = m.end(0)
# insert after end-of-line
eol = s.find("\n", pos)
if eol == -1: eol = pos
s = s[:eol+1] + inject + "\n" + s[eol+1:]

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK:", str(p))
PY

echo "== [4] restart service =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || { sudo systemctl status "$SVC" --no-pager || true; sudo journalctl -xeu "$SVC" -n 120 --no-pager || true; err "restart failed"; }

echo "== [5] wait for 8910 listen =="
for i in $(seq 1 60); do
  ss -ltnp | grep -q ':8910' && break
  sleep 0.25
done
ss -ltnp | grep -q ':8910' || err "8910 not listening"

echo "== [6] smoke curls generate hits =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null || true
curl -fsS "$BASE/api/vsp/rid_latest" >/dev/null || true
curl -fsS "$BASE/api/vsp/release_latest" >/dev/null || true

echo "== [DONE] Now check journal for [VSP_API_HIT] =="
