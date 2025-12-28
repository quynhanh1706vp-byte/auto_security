#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WORKERS="${VSP_UI_WORKERS:-2}"
THREADS="${VSP_UI_THREADS:-8}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need python3; need sed; need tr; need cat; need grep

PID="$(systemctl show -p MainPID --value "$SVC" || true)"
if [ -z "${PID:-}" ] || [ "$PID" = "0" ]; then
  echo "[ERR] MainPID=0; cannot read running cmdline. Start service first."
  exit 2
fi

CMD="$(tr '\0' ' ' < "/proc/$PID/cmdline" | sed 's/[[:space:]]\+/ /g' | sed 's/[[:space:]]$//')"
[ -n "$CMD" ] || { echo "[ERR] empty cmdline"; exit 2; }

# normalize workers/threads in cmdline if gunicorn
if echo "$CMD" | grep -q '\bgunicorn\b'; then
  if echo "$CMD" | grep -q -- ' --workers '; then
    CMD="$(echo "$CMD" | sed -E "s/--workers[[:space:]]+[0-9]+/--workers ${WORKERS}/")"
  else
    CMD="$(echo "$CMD" | sed -E "s/\bgunicorn\b/gunicorn --workers ${WORKERS}/")"
  fi

  if echo "$CMD" | grep -q -- ' --threads '; then
    CMD="$(echo "$CMD" | sed -E "s/--threads[[:space:]]+[0-9]+/--threads ${THREADS}/")"
  else
    CMD="$CMD --threads ${THREADS}"
  fi
fi

echo "== [P97] ExecStart =="
echo "$CMD"

DROP="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$DROP"
CONF="$DROP/override.conf"

sudo tee "$CONF" >/dev/null <<EOF
# VSP_P97_EXECSTART_FROM_MAINPID_V1
[Service]
ExecStart=
ExecStart=$CMD
EOF

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P97] verify ExecStart now =="
systemctl show -p ExecStart "$SVC" | head -n 1

echo "[OK] P97 done (workers=${WORKERS} threads=${THREADS})"
