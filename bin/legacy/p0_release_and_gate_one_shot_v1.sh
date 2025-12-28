#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need python3; need date; need systemctl; need tar; need sha256sum

echo "== [1/4] compile gate + restart =="
bash bin/p0_wsgi_compile_gate_then_restart_v1.sh

echo "== [2/4] commercial selfcheck (4 tabs) =="
bash bin/p0_commercial_selfcheck_4tabs_v3c.sh

echo "== [3/4] pack UI commercial release =="
bash bin/p0_pack_ui_commercial_release_v1.sh | tee /tmp/vsp_ui_release_last.log

echo "== [4/4] show last package paths =="
PKG="$(grep -oE 'out_release/UI_COMMERCIAL_[0-9]{8}_[0-9]{6}\.tgz' /tmp/vsp_ui_release_last.log | tail -n1 || true)"
if [ -n "${PKG:-}" ]; then
  echo "[OK] PACKAGE: $PKG"
  echo "[OK] SHA256  : ${PKG%.tgz}.sha256"
  echo "[OK] MANIFEST: ${PKG%.tgz}.manifest.txt"
else
  echo "[WARN] cannot detect PKG from log; see /tmp/vsp_ui_release_last.log"
fi
