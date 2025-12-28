#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need git

REPO_HTTPS="https://github.com/quynhanh1706vp-byte/auto_security.git"
REPO_SSH="git@github.com:quynhanh1706vp-byte/auto_security.git"

echo "== [1] git status =="
git status -sb || true

echo
echo "== [2] current remotes =="
git remote -v || true

# Ensure branch main
git checkout -B main >/dev/null 2>&1 || true

# If origin missing or points elsewhere -> set to SSH by default
cur_origin="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$cur_origin" ]; then
  echo "[INFO] origin missing -> add origin=$REPO_SSH"
  git remote add origin "$REPO_SSH"
else
  if [[ "$cur_origin" != *"quynhanh1706vp-byte/auto_security"* ]]; then
    echo "[INFO] origin points to '$cur_origin' -> set origin=$REPO_SSH"
    git remote set-url origin "$REPO_SSH"
  else
    echo "[OK] origin already points to auto_security"
  fi
fi

echo
echo "== [3] remotes after fix =="
git remote -v

echo
echo "== [4] optional: add new files (NOT .bak*) =="
# Add only the workflow + helper script; ignore .bak_* by default
git add .github/workflows/vsp_p0_commercial_gate.yml bin/p3_pin_workflow_to_vsp_ui_runner_v1.sh 2>/dev/null || true
git commit -m "ci: pin workflow to vsp-ui runner" 2>/dev/null || true

echo
echo "== [5] test SSH auth (non-fatal) =="
ssh -T git@github.com || true

echo
echo "== [6] push =="
set +e
git push -u origin main
rc=$?
set -e

if [ $rc -ne 0 ]; then
  echo
  echo "[FAIL] push failed. Common causes:"
  echo "  - repo name wrong OR repo is private and this SSH key has no access"
  echo "  - origin URL still wrong"
  echo
  echo "[NEXT] quick checks:"
  echo "  1) open repo in browser: https://github.com/quynhanh1706vp-byte/auto_security"
  echo "  2) verify you can see it while logged in"
  echo "  3) verify SSH key on this VPS is added to your GitHub account (Settings -> SSH and GPG keys)"
  echo
  echo "[ALT] use HTTPS remote (will prompt credentials/PAT if needed):"
  echo "  git remote set-url origin $REPO_HTTPS"
  echo "  git push -u origin main"
  exit $rc
fi

echo "[OK] push succeeded"
