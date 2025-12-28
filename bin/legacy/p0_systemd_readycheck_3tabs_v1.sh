#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need curl

D="/etc/systemd/system/${SVC}.d"
F="${D}/override_readycheck_tabs.conf"

sudo mkdir -p "$D"

sudo tee "$F" >/dev/null <<EOF
[Service]
# Commercial READY: require 3 tabs + 2 APIs reachable (avoid "0 bytes green")
ExecStartPost=
ExecStartPost=/bin/bash -lc 'for i in \$(seq 1 90); do \
  curl -fsS --connect-timeout 1 ${BASE}/runs >/dev/null && \
  curl -fsS --connect-timeout 1 ${BASE}/data_source >/dev/null && \
  curl -fsS --connect-timeout 1 ${BASE}/settings >/dev/null && \
  curl -fsS --connect-timeout 1 ${BASE}/api/vsp/runs?limit=1 >/dev/null && \
  curl -fsS --connect-timeout 1 ${BASE}/api/vsp/release_latest >/dev/null && \
  exit 0; \
  sleep 0.25; \
done; echo "[READY] tabs/apis not reachable" >&2; exit 1'
EOF

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,18p'
echo "[DONE] readycheck installed at $F"
