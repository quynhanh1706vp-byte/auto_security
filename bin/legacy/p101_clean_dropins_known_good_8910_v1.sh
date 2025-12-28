#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

WORKERS="${VSP_UI_WORKERS:-2}"
THREADS="${VSP_UI_THREADS:-8}"
TIMEOUT="${VSP_UI_TIMEOUT:-120}"
KEEPALIVE="${VSP_UI_KEEPALIVE:-5}"

GUNI="$ROOT/.venv/bin/gunicorn"
[ -x "$GUNI" ] || { echo "[ERR] missing gunicorn: $GUNI"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need ss; need curl; need date; need head; need sed; need grep; need mkdir; need cp

TS="$(date +%Y%m%d_%H%M%S)"
EVID="$ROOT/out_ci/p101_${TS}"
mkdir -p "$EVID"

echo "== [P101] snapshot current unit + dropins =="
systemctl cat "$SVC" > "$EVID/systemctl_cat.txt" || true
systemctl show -p ActiveState,SubState,MainPID,ExecStart,FragmentPath,DropInPaths "$SVC" | sed 's/; /\n/g' > "$EVID/systemctl_show.txt" || true
echo "[OK] saved: $EVID/systemctl_cat.txt, $EVID/systemctl_show.txt"

DROP="/etc/systemd/system/${SVC}.d"
echo "== [P101] list drop-ins =="
sudo ls -la "$DROP" > "$EVID/dropins_ls.txt" 2>&1 || true
cat "$EVID/dropins_ls.txt" || true

echo "== [P101] disable ALL existing drop-ins (rename -> .disabled_TS) =="
if sudo test -d "$DROP"; then
  for f in $(sudo ls "$DROP" 2>/dev/null | grep -E '\.conf$' || true); do
    sudo mv -f "$DROP/$f" "$DROP/$f.disabled_$TS"
    echo "[DISABLED] $f -> $f.disabled_$TS"
  done
else
  sudo mkdir -p "$DROP"
fi

echo "== [P101] write single known-good drop-in (00-known-good.conf) =="
CONF="$DROP/00-known-good.conf"
sudo tee "$CONF" >/dev/null <<EOF
# VSP_P101_KNOWN_GOOD_8910_V1
[Service]
WorkingDirectory=$ROOT
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=VSP_UI_BASE=$BASE
UMask=027
ReadWritePaths=$ROOT/out_ci

ExecStart=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=
PIDFile=$ROOT/out_ci/ui_8910.pid

ExecStartPre=/bin/bash -lc 'mkdir -p $ROOT/out_ci && chmod 775 $ROOT/out_ci || true'
ExecStart=$GUNI wsgi_vsp_ui_gateway:application --workers $WORKERS --worker-class gthread --threads $THREADS --timeout $TIMEOUT --graceful-timeout 15 --chdir $ROOT --pythonpath $ROOT --bind 127.0.0.1:8910 --pid $ROOT/out_ci/ui_8910.pid --access-logfile $ROOT/out_ci/ui_8910.access.log --error-logfile $ROOT/out_ci/ui_8910.error.log --keep-alive $KEEPALIVE
ExecStop=/bin/kill -s SIGINT \$MAINPID
ExecStopPost=/usr/sbin/fuser -k 8910/tcp || true
EOF

echo "== [P101] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] not active"; systemctl status "$SVC" --no-pager | head -n 120; exit 2; }

echo "== [P101] wait LISTEN :8910 =="
ok=0
for i in $(seq 1 80); do
  if ss -lntp 2>/dev/null | grep -qE ':(8910)\b'; then ok=1; break; fi
  sleep 0.1
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] still no LISTEN 8910 after wait"
  systemctl status "$SVC" --no-pager | head -n 160 || true
  journalctl -u "$SVC" -n 120 --no-pager | tail -n 120 || true
  exit 2
fi
ss -lntp | grep -E ':(8910)\b' || true

echo "== [P101] wait HTTP up (/runs) =="
ok=0
for i in $(seq 1 120); do
  if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] HTTP not reachable"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }
echo "[OK] HTTP reachable: $BASE"

echo "== [P101] smoke runs_v3 JSON (save then parse; no pipe break) =="
curl -fsS -D "$EVID/runs_v3_hdr.txt" "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o "$EVID/runs_v3_body.json" || true
head -n 25 "$EVID/runs_v3_hdr.txt" || true
python3 - <<PY
import json, pathlib
b=pathlib.Path("$EVID/runs_v3_body.json").read_text(encoding="utf-8", errors="replace").strip()
print("body_len=", len(b), "head=", b[:120].replace("\n","\\n"))
j=json.loads(b)
txt=str(j)
print("ok=", j.get("ok"), "items=", len(j.get("items",[])), "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "== [P101] done. Evidence: $EVID =="
