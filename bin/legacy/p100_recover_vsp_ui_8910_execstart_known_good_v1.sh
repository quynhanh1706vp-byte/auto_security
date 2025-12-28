#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

WORKERS="${VSP_UI_WORKERS:-2}"
THREADS="${VSP_UI_THREADS:-8}"
TIMEOUT="${VSP_UI_TIMEOUT:-120}"

VENV_BIN="/home/test/Data/SECURITY_BUNDLE/.venv/bin"
GUNI="${VENV_BIN}/gunicorn"
PY="${VENV_BIN}/python3"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need ss; need curl; need sed; need head; need tail; need grep

echo "== [P100] pre-diag =="
echo "[INFO] svc=$SVC base=$BASE"
systemctl show -p ActiveState,SubState,MainPID,ExecStart,FragmentPath,DropInPaths "$SVC" | sed 's/; /\n/g' || true
echo "== [P100] ss listen 8910 (before) =="
ss -lntp | grep -E ':(8910)\b' || echo "(no LISTEN on 8910)"

echo "== [P100] unit file (first 120 lines) =="
systemctl cat "$SVC" | head -n 120 || true

# Pick WSGI module
cd "$ROOT"
MOD=""
if [ -f "wsgi_vsp_ui_gateway.py" ]; then
  MOD="wsgi_vsp_ui_gateway:app"
elif [ -f "vsp_demo_app.py" ]; then
  MOD="vsp_demo_app:app"
else
  echo "[ERR] cannot find wsgi_vsp_ui_gateway.py or vsp_demo_app.py"
  exit 2
fi
echo "[INFO] module=$MOD"

# Ensure venv gunicorn exists; fallback to system gunicorn
if [ ! -x "$GUNI" ]; then
  echo "[WARN] missing $GUNI, fallback to PATH gunicorn"
  need gunicorn
  GUNI="$(command -v gunicorn)"
fi

DROP="/etc/systemd/system/${SVC}.d"
CONF="$DROP/override.conf"
echo "== [P100] write drop-in override: $CONF =="
sudo mkdir -p "$DROP"
sudo tee "$CONF" >/dev/null <<EOF
# VSP_P100_KNOWN_GOOD_EXECSTART_V1
[Service]
WorkingDirectory=$ROOT
Environment="PATH=$VENV_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin"
ExecStart=
ExecStart=$GUNI --workers $WORKERS --threads $THREADS --bind 127.0.0.1:8910 --timeout $TIMEOUT --graceful-timeout 30 --access-logfile - --error-logfile - $MOD
EOF

echo "== [P100] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] not active"; systemctl status "$SVC" --no-pager | head -n 80; exit 2; }

echo "== [P100] ss listen 8910 (after restart) =="
ss -lntp | grep -E ':(8910)\b' || { echo "[ERR] still no LISTEN 8910"; systemctl status "$SVC" --no-pager | head -n 120; exit 2; }

echo "== [P100] wait UI up (curl /runs) =="
ok=0
for i in $(seq 1 120); do
  if curl -fsS --connect-timeout 1 --max-time 4 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable at $BASE"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }
echo "[OK] UI reachable: $BASE"

echo "== [P100] smoke runs_v3 JSON (save to file, no pipe break) =="
curl -fsS -D /tmp/p100_runsv3_hdr.txt "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p100_runsv3_body.bin
head -n 25 /tmp/p100_runsv3_hdr.txt || true
$PY - <<'PY'
import json, pathlib
b=pathlib.Path("/tmp/p100_runsv3_body.bin").read_bytes()
s=b.decode("utf-8", errors="replace").strip()
j=json.loads(s)
txt=str(j)
print("ok=", j.get("ok"), "items=", len(j.get("items",[])), "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "== [P100] last journal (80 lines) =="
journalctl -u "$SVC" -n 80 --no-pager | tail -n 80

echo "[OK] P100 done"
