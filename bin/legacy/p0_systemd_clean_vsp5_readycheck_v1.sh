#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
D="/etc/systemd/system/${SVC}.d"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need grep; need sed; need date

echo "== drop-ins =="
sudo ls -la "$D" || true
echo

TS="$(date +%Y%m%d_%H%M%S)"
for f in $(sudo ls -1 "$D"/*.conf 2>/dev/null || true); do
  if sudo grep -n "/vsp5" "$f" >/dev/null 2>&1; then
    echo "[FOUND] /vsp5 in $f"
    sudo cp -f "$f" "${f}.bak_${TS}"
    sudo sed -i -E 's/^(ExecStartPost=.*\/vsp5.*)$/# \1  # disabled_by_p0_clean_v1/' "$f"
    echo "[PATCHED] backup => ${f}.bak_${TS}"
  fi
done

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,18p'
echo "[DONE]"
