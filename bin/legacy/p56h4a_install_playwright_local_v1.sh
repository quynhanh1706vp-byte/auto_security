#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need npm

echo "== [P56H4A] install playwright locally in UI folder =="
mkdir -p out_ci

# init package.json if missing
if [ ! -f package.json ]; then
  echo "[INFO] package.json missing -> npm init -y"
  npm init -y >/dev/null
fi

# install playwright
echo "[INFO] npm i -D playwright"
npm i -D playwright

# install chromium used by playwright
echo "[INFO] npx playwright install chromium"
npx playwright install chromium

# quick verify
node -e "require('playwright'); console.log('[OK] playwright require ok')"
echo "[DONE] P56H4A OK"
