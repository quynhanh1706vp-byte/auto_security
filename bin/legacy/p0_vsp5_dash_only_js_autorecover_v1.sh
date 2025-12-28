#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [0] node --check current =="
if node --check "$JS" >/tmp/vsp_js_check.out 2>&1; then
  echo "[OK] current JS compiles (no SyntaxError). Nothing to recover."
else
  echo "[ERR] current JS SyntaxError:"
  sed -n '1,6p' /tmp/vsp_js_check.out || true

  echo "== [1] snapshot broken =="
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$JS" "${JS}.bak_broken_${TS}"
  echo "[BACKUP] ${JS}.bak_broken_${TS}"

  echo "== [2] find latest compiling backup =="
  GOOD=""
  for f in $(ls -1t static/js/vsp_dash_only_v1.js.bak_* 2>/dev/null || true); do
    if node --check "$f" >/dev/null 2>&1; then
      GOOD="$f"
      break
    fi
  done

  if [ -z "$GOOD" ]; then
    echo "[FATAL] No compiling backup found for $JS (cannot auto-recover)."
    echo "Tip: list backups: ls -1t static/js/vsp_dash_only_v1.js.bak_* | head"
    exit 3
  fi

  echo "[OK] restore from: $GOOD"
  cp -f "$GOOD" "$JS"

  echo "== [3] verify restored compiles =="
  node --check "$JS"
  echo "[OK] restored JS compiles"
fi

echo "== [4] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Now hard refresh /vsp5 (Ctrl+Shift+R)."
