#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need ss; need grep; need sed; need date; need install; need curl

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

echo "== DIAG: curl (2s) =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || echo "[curl] FAIL (port likely not open)"

echo
echo "== DIAG: ss listen (sudo) =="
sudo ss -ltnp | grep -E ':8910\b' || echo "[ss] no LISTEN on 8910"

echo
echo "== DIAG: systemd status =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true

echo
echo "== DIAG: journal tail =="
sudo journalctl -u "$SVC" -n 220 --no-pager || true

echo
echo "== DIAG: unit hardening lines =="
sudo grep -nE '^\s*(PrivateNetwork|IPAddressDeny|IPAddressAllow|RestrictAddressFamilies|BindToDevice|NetworkNamespacePath|PrivateUsers|ProtectSystem|ProtectHome|NoNewPrivileges)\b' "$UNIT" || true

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_fixlisten_${TS}"
echo "[BACKUP] ${UNIT}.bak_fixlisten_${TS}"

TMP="/tmp/${SVC}.patched_fixlisten_${TS}"
export UNIT TMP

python3 - <<'PY'
from pathlib import Path
import os, re

unit = Path(os.environ["UNIT"])
tmp  = Path(os.environ["TMP"])
s = unit.read_text(encoding="utf-8", errors="replace")

if "[Service]" not in s:
    raise SystemExit("[ERR] unit missing [Service] section")

# (1) Remove hardening directives that can prevent listening/binding
#     - IPAddressDeny/Allow can block AF_INET binds
#     - RestrictAddressFamilies might omit AF_INET/AF_INET6
#     - PrivateNetwork isolates network namespace (no host listen)
s = re.sub(r'(?m)^\s*IPAddressDeny=.*\n', '', s)
s = re.sub(r'(?m)^\s*IPAddressAllow=.*\n', '', s)
s = re.sub(r'(?m)^\s*BindToDevice=.*\n', '', s)
s = re.sub(r'(?m)^\s*NetworkNamespacePath=.*\n', '', s)

# Force PrivateNetwork=false (or add it)
if re.search(r'(?m)^\s*PrivateNetwork=', s):
    s = re.sub(r'(?m)^\s*PrivateNetwork=.*$', 'PrivateNetwork=false', s)
else:
    s = s.replace("[Service]\n", "[Service]\nPrivateNetwork=false\n", 1)

# Ensure RestrictAddressFamilies includes AF_INET/AF_INET6 (or add it)
raf_line = "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6"
if re.search(r'(?m)^\s*RestrictAddressFamilies=', s):
    s = re.sub(r'(?m)^\s*RestrictAddressFamilies=.*$', raf_line, s)
else:
    s = s.replace("[Service]\n", "[Service]\n" + raf_line + "\n", 1)

# (2) Keep restart behavior sane
def set_or_replace(key: str, val: str, text: str) -> str:
    if re.search(rf'^\s*{re.escape(key)}=', text, flags=re.M):
        return re.sub(rf'^\s*{re.escape(key)}=.*$', f'{key}={val}', text, flags=re.M)
    return text.replace("[Service]\n", f"[Service]\n{key}={val}\n", 1)

s = set_or_replace("Restart", "on-failure", s)
s = set_or_replace("RestartSec", "1", s)
s = set_or_replace("TimeoutStopSec", "8", s)
s = set_or_replace("KillMode", "mixed", s)

# (3) Mark injected block (comment)
mark = "# VSP_FIX_NOT_LISTENING_8910_P0_V5"
if mark not in s:
    s = s.replace("[Service]\n", "[Service]\n" + mark + "\n", 1)

tmp.write_text(s, encoding="utf-8")
print("[OK] wrote patched unit to:", tmp)
PY

echo "== install patched unit (sudo) =="
sudo install -m 0644 "$TMP" "$UNIT"

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

echo
echo "== POST: status =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true

echo
echo "== POST: wait + ss =="
sleep 0.6
sudo ss -ltnp | grep -E ':8910\b' || {
  echo "[FAIL] still not listening on 8910"
  echo "== POST journal tail =="
  sudo journalctl -u "$SVC" -n 260 --no-pager || true
  echo "== show unit (Service section) =="
  sudo awk 'BEGIN{p=0} /^\[Service\]/{p=1} /^\[/{if($0!="[Service]")p=0} {if(p)print NR ":" $0}' "$UNIT" | sed -n '1,220p' || true
  exit 4
}

echo
echo "== POST: curl =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || { echo "[FAIL] curl still failing"; exit 5; }

echo "[OK] 8910 is listening + curl OK"
