#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WORKERS="${VSP_UI_WORKERS:-2}"
THREADS="${VSP_UI_THREADS:-8}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need python3; need sed

RAW="$(systemctl show -p ExecStart "$SVC" | sed 's/^ExecStart=//')"
[ -n "$RAW" ] || { echo "[ERR] cannot read ExecStart"; exit 2; }

CMD="$(python3 - <<PY
import re,sys
s=sys.stdin.read()
# try argv[]=
m=re.search(r'argv\[\]\s*=\s*([^;}]*)', s)
if m:
    print(m.group(1).strip()); sys.exit(0)
# fallback: take content between { } then strip "path=" etc
m=re.search(r'\{([^}]*)\}', s)
print((m.group(1) if m else s).strip())
PY
<<<"$RAW")"

# normalize: ensure workers/threads flags exist and match env
if echo "$CMD" | grep -q -- ' --workers '; then
  CMD="$(echo "$CMD" | sed -E "s/--workers[[:space:]]+[0-9]+/--workers ${WORKERS}/")"
else
  CMD="$CMD --workers ${WORKERS}"
fi

if echo "$CMD" | grep -q -- ' --threads '; then
  CMD="$(echo "$CMD" | sed -E "s/--threads[[:space:]]+[0-9]+/--threads ${THREADS}/")"
else
  CMD="$CMD --threads ${THREADS}"
fi

echo "== [P95] clean ExecStart =="
echo "$CMD"

DROP="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$DROP"
CONF="$DROP/override.conf"

sudo tee "$CONF" >/dev/null <<EOF
# VSP_P95_CLEAN_EXECSTART_V1
[Service]
ExecStart=
ExecStart=$CMD
EOF

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "[OK] P95 done (workers=${WORKERS} threads=${THREADS})"
