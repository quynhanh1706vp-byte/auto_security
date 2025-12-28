#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need ss; need grep; need sed; need date; need install

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_portguard_${TS}"
echo "[BACKUP] ${UNIT}.bak_portguard_${TS}"

TMP="/tmp/${SVC}.patched_${TS}"
python3 - <<PY
from pathlib import Path
import re, sys

unit = Path("$UNIT")
s = unit.read_text(encoding="utf-8", errors="replace")

MARK="VSP_PORT_GUARD_8910_P0_V2"

# If already patched, still normalize restart policy and exit.
lines = s.splitlines(True)

if "[Service]" not in s:
    raise SystemExit("[ERR] unit missing [Service] section")

# Remove older port-guard blocks if any (v1/v2)
s = re.sub(r'(?s)\n# VSP_PORT_GUARD_8910_P0_V[0-9_]+.*?# /VSP_PORT_GUARD_8910_P0_V[0-9_]+\n\n', "\n", s)

lines = s.splitlines(True)
si = next(i for i,l in enumerate(lines) if l.strip() == "[Service]")

guard = (
    f"\n# {MARK}\n"
    "# Ensure port 8910 is free before gunicorn starts (prevents Errno 98 loops)\n"
    "ExecStartPre=/usr/bin/bash -lc '"
    "set -euo pipefail; "
    "PORT=8910; "
    "if command -v fuser >/dev/null 2>&1; then fuser -k ${PORT}/tcp >/dev/null 2>&1 || true; fi; "
    "pkill -f \"gunicorn .*8910\" >/dev/null 2>&1 || true; "
    "sleep 0.2; "
    "exit 0'\n"
    f"# /{MARK}\n\n"
)

# Insert guard right after [Service]
lines.insert(si+1, guard)
s2 = "".join(lines)

# Normalize restart policy
def set_or_replace(key: str, val: str, text: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}=', text, flags=re.M):
        return re.sub(rf'^\s*{re.escape(key)}=.*$', f'{key}={val}', text, flags=re.M)
    # insert right after [Service]
    return text.replace("[Service]\n", f"[Service]\n{key}={val}\n", 1)

s2 = set_or_replace("Restart", "on-failure", s2)
s2 = set_or_replace("RestartSec", "1", s2)
s2 = set_or_replace("TimeoutStopSec", "8", s2)
s2 = set_or_replace("KillMode", "mixed", s2)

Path("$TMP").write_text(s2, encoding="utf-8")
print("[OK] wrote patched unit to: $TMP")
PY

echo "== install patched unit (sudo) =="
sudo install -m 0644 "$TMP" "$UNIT"

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,60p' || true

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify endpoints =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || true
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,25p' || true

echo "== check NEW bind errors in tail =="
tail -n 220 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null | \
  grep -nE "Address already in use|Errno 98|Connection in use" && \
  { echo "[FAIL] still seeing bind loop in NEW tail"; exit 4; } || echo "[OK] no bind loop in NEW tail"
