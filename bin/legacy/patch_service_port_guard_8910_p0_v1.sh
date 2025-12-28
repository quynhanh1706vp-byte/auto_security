#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"
cd /home/test/Data/SECURITY_BUNDLE/ui

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need ss; need grep; need sed; need date

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_portguard_${TS}"
echo "[BACKUP] ${UNIT}.bak_portguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

u = Path("/etc/systemd/system/vsp-ui-8910.service")
s = u.read_text(encoding="utf-8", errors="replace")

MARK="VSP_PORT_GUARD_8910_P0_V1"
if MARK in s:
    print("[OK] already patched")
else:
    # Ensure [Service] exists
    if "[Service]" not in s:
        raise SystemExit("[ERR] unit missing [Service] section")

    lines = s.splitlines(True)

    # Find [Service] line index
    si = next(i for i,l in enumerate(lines) if l.strip() == "[Service]")

    # Insert guard block right after [Service] (before ExecStart)
    guard = (
        f"\n# {MARK}\n"
        "# Ensure port 8910 is free before gunicorn starts (prevents Errno 98 loops)\n"
        "ExecStartPre=/usr/bin/bash -lc '"
        "set -euo pipefail; "
        "PORT=8910; "
        # kill anything holding the port
        "if command -v fuser >/dev/null 2>&1; then fuser -k ${PORT}/tcp >/dev/null 2>&1 || true; fi; "
        # best-effort kill stray gunicorn bound to 8910
        "pkill -f \"gunicorn .*:8910|gunicorn .*8910\" >/dev/null 2>&1 || true; "
        "sleep 0.2; "
        "exit 0'\n"
        "# /" + MARK + "\n\n"
    )

    insert_at = si + 1
    lines.insert(insert_at, guard)

    s2 = "".join(lines)

    # Harden restart policy (commercial-friendly)
    # If Restart not present, add; if present and too aggressive, normalize.
    if re.search(r'^\s*Restart=', s2, flags=re.M):
        s2 = re.sub(r'^\s*Restart=.*$', 'Restart=on-failure', s2, flags=re.M)
    else:
        s2 = s2.replace("[Service]\n", "[Service]\nRestart=on-failure\n", 1)

    if re.search(r'^\s*RestartSec=', s2, flags=re.M):
        s2 = re.sub(r'^\s*RestartSec=.*$', 'RestartSec=1', s2, flags=re.M)
    else:
        s2 = s2.replace("Restart=on-failure\n", "Restart=on-failure\nRestartSec=1\n", 1)

    # Make stop more deterministic
    if "TimeoutStopSec" not in s2:
        s2 = s2.replace("[Service]\n", "[Service]\nTimeoutStopSec=8\n", 1)
    if "KillMode" not in s2:
        s2 = s2.replace("[Service]\n", "[Service]\nKillMode=mixed\n", 1)

    u.write_text(s2, encoding="utf-8")
    print("[OK] patched unit with port-guard + restart hardening")
PY

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 3; }

echo "== verify endpoints =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || true
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,25p' || true
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=5 | head -c 300; echo

echo "== check NEW bind errors after restart =="
tail -n 200 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null | \
  grep -nE "Address already in use|Errno 98|Connection in use|Can't connect" && \
  { echo "[FAIL] still seeing bind/connect loop in NEW tail"; exit 4; } || echo "[OK] no bind/connect loop in NEW tail"
