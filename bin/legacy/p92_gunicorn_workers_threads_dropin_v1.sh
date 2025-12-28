#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WORKERS="${VSP_UI_WORKERS:-2}"
THREADS="${VSP_UI_THREADS:-4}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need grep; need sed; need awk

echo "== [P92] read current ExecStart =="
EX="$(systemctl show -p ExecStart "$SVC" | sed 's/^ExecStart=//')"
[ -n "$EX" ] || { echo "[ERR] cannot read ExecStart for $SVC"; exit 2; }
echo "$EX" | head -n 1

# Extract the first command between { } (systemd show format)
CMD="$(echo "$EX" | sed -n 's/.*{\([^}]*\)}.*/\1/p' | head -n 1)"
[ -n "$CMD" ] || CMD="$EX"

# If already has --workers/--threads, keep them; else inject.
if echo "$CMD" | grep -q -- '--workers'; then
  NEW="$CMD"
else
  NEW="$(echo "$CMD" | sed -E "s/\bgunicorn\b/gunicorn --workers ${WORKERS} --threads ${THREADS}/")"
fi

echo "== [P92] new ExecStart preview =="
echo "$NEW"

DROP="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$DROP"
CONF="$DROP/override.conf"

echo "== [P92] write drop-in: $CONF =="
sudo tee "$CONF" >/dev/null <<EOF
# VSP_P92_GUNICORN_TUNE_V1
[Service]
ExecStart=
ExecStart=$NEW
EOF

echo "== [P92] reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; systemctl status "$SVC" --no-pager | head -n 60; exit 2; }

echo "[OK] P92 done (workers=${WORKERS} threads=${THREADS})"
