#!/usr/bin/env bash
set -euo pipefail
UNIT="/etc/systemd/system/vsp-ui-8911-dev.service"
sudo cp -f "$UNIT" "${UNIT}.bak_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] ${UNIT}.bak_*"

sudo python3 - <<'PY'
from pathlib import Path
u = Path("/etc/systemd/system/vsp-ui-8911-dev.service")
txt = u.read_text(encoding="utf-8", errors="ignore").splitlines(True)

out=[]
inserted=False
for line in txt:
    out.append(line)
    if (not inserted) and line.startswith("ExecStartPre=/usr/bin/mkdir"):
        # add a pre-check: ensure port is free before starting
        out.append("ExecStartPre=/bin/sh -lc 'ss -ltn | grep -q \":8911\" && echo \"[ERR] :8911 already in use\" && exit 1 || exit 0'\n")
        inserted=True

u.write_text("".join(out), encoding="utf-8")
print("[OK] added port guard ExecStartPre")
PY

sudo systemctl daemon-reload
sudo systemctl restart vsp-ui-8911-dev
sudo systemctl status vsp-ui-8911-dev --no-pager | sed -n '1,30p'
