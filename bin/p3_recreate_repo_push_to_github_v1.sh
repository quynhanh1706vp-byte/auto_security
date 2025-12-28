#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need git

# REQUIRED: set your new repo URL here (SSH recommended)
# Example (SSH): git@github.com:quynhanh1706vp-byte/vsp_security_bundle_ui.git
# Example (HTTPS): https://github.com/quynhanh1706vp-byte/vsp_security_bundle_ui.git
REPO_URL="${REPO_URL:-}"

[ -n "$REPO_URL" ] || {
  echo "[ERR] missing REPO_URL env. Example:"
  echo "  export REPO_URL='git@github.com:quynhanh1706vp-byte/vsp_security_bundle_ui.git'"
  exit 2
}

# init git if needed
if [ ! -d .git ]; then
  git init
  echo "[OK] git init"
fi

# ensure main branch
git checkout -B main

# add all + commit if no commits yet / or dirty changes
git add -A
if git diff --cached --quiet; then
  echo "[INFO] nothing new to commit"
else
  git commit -m "bootstrap: VSP UI P0 gate + GitHub Actions workflow"
  echo "[OK] committed"
fi

# set remote origin to new repo
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
  echo "[OK] updated origin => $REPO_URL"
else
  git remote add origin "$REPO_URL"
  echo "[OK] added origin => $REPO_URL"
fi

# push
git push -u origin main
echo "[OK] pushed to origin main"

echo
echo "NEXT (token): GitHub repo -> Settings -> Actions -> Runners -> New self-hosted runner"
echo "Copy the registration token (expires ~1 hour) and run p2_install_github_runner_systemd_v1.sh"
