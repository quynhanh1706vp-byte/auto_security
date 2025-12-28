#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need ss; need grep; need sed; need date; need install

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

echo "== PRE status (if failing) =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,80p' || true
echo
echo "== PRE journal tail =="
sudo journalctl -u "$SVC" -n 140 --no-pager || true
echo

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_portguard_v4_${TS}"
echo "[BACKUP] ${UNIT}.bak_portguard_v4_${TS}"

TMP="/tmp/${SVC}.patched_${TS}"
export UNIT TMP

python3 - <<'PY'
from pathlib import Path
import os, re

unit = Path(os.environ["UNIT"])
tmp  = Path(os.environ["TMP"])

s = unit.read_text(encoding="utf-8", errors="replace")
if "[Service]" not in s:
    raise SystemExit("[ERR] unit missing [Service] section")

# Remove any previous port-guard blocks we injected (v1/v2/v3)
s = re.sub(r'(?s)\n# VSP_PORT_GUARD_8910_P0_V[0-9_]+.*?# /VSP_PORT_GUARD_8910_P0_V[0-9_]+\n\n', "\n", s)

lines = s.splitlines(True)
si = next(i for i,l in enumerate(lines) if l.strip() == "[Service]")

MARK="VSP_PORT_GUARD_8910_P0_V4"
guard = (
    f"\n# {MARK}\n"
    "# Ensure port 8910 is free before gunicorn starts (systemd-native, no shell quoting)\n"
    "ExecStartPre=-/usr/sbin/fuser -k 8910/tcp\n"
    "ExecStartPre=-/usr/bin/pkill -f gunicorn\\ .*8910\n"
    "ExecStartPre=-/usr/bin/sleep 0.2\n"
    f"# /{MARK}\n\n"
)
lines.insert(si+1, guard)
s2 = "".join(lines)

def set_or_replace(key: str, val: str, text: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}=', text, flags=re.M):
        return re.sub(rf'^\s*{re.escape(key)}=.*$', f'{key}={val}', text, flags=re.M)
    return text.replace("[Service]\n", f"[Service]\n{key}={val}\n", 1)

# Commercial-friendly hardening
s2 = set_or_replace("Restart", "on-failure", s2)
s2 = set_or_replace("RestartSec", "1", s2)
s2 = set_or_replace("TimeoutStopSec", "8", s2)
s2 = set_or_replace("KillMode", "mixed", s2)

tmp.write_text(s2, encoding="utf-8")
print("[OK] wrote patched unit to:", tmp)
PY

echo "== install patched unit (sudo) =="
sudo install -m 0644 "$TMP" "$UNIT"

echo "== daemon-reload =="
sudo systemctl daemon-reload

echo "== restart service =="
if ! sudo systemctl restart "$SVC"; then
  echo "[FAIL] restart failed; showing status + journal"
  sudo systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
  echo
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  echo
  echo "== unit content (top 140 lines) =="
  sudo sed -n '1,140p' "$UNIT" || true
  exit 3
fi

echo "== POST status =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,80p' || true

echo "== verify listen :8910 =="
ss -ltnp | grep -E ':8910\b' || { echo "[ERR] not listening on 8910"; exit 4; }

echo "== quick verify endpoints =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || true
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,25p' || true

echo "== check NEW bind errors in tail =="
tail -n 220 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null | \
  grep -nE "Address already in use|Errno 98|Connection in use" && \
  { echo "[FAIL] still seeing bind loop in NEW tail"; exit 5; } || echo "[OK] no bind loop in NEW tail"
