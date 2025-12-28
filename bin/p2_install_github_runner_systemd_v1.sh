#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   GH_RUNNER_URL   e.g. https://github.com/<ORG>/<REPO>
#   GH_RUNNER_TOKEN token from GitHub UI (expires ~1h)
#
# Optional:
#   GH_RUNNER_NAME   default: vsp-<hostname>
#   GH_RUNNER_LABELS default: vsp-ui,commercial,linux,x64
#   GH_RUNNER_USER   default: test
#   GH_RUNNER_DIR    default: /home/test/actions-runner-vsp

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need tar; need python3; need uname; need hostname

GH_RUNNER_URL="${GH_RUNNER_URL:-}"
GH_RUNNER_TOKEN="${GH_RUNNER_TOKEN:-}"

[ -n "$GH_RUNNER_URL" ] || { echo "[ERR] missing GH_RUNNER_URL"; exit 2; }
[ -n "$GH_RUNNER_TOKEN" ] || { echo "[ERR] missing GH_RUNNER_TOKEN"; exit 2; }

USER_DEF="${GH_RUNNER_USER:-test}"
DIR_DEF="${GH_RUNNER_DIR:-/home/test/actions-runner-vsp}"
NAME_DEF="${GH_RUNNER_NAME:-vsp-$(hostname -s 2>/dev/null || hostname)}"
LABELS_DEF="${GH_RUNNER_LABELS:-vsp-ui,commercial,linux,x64}"

ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || { echo "[ERR] only x64 supported (got $ARCH)"; exit 2; }

echo "[INFO] URL=$GH_RUNNER_URL"
echo "[INFO] NAME=$NAME_DEF"
echo "[INFO] LABELS=$LABELS_DEF"
echo "[INFO] DIR=$DIR_DEF"
echo "[INFO] USER=$USER_DEF"

mkdir -p "$DIR_DEF"
cd "$DIR_DEF"

echo "[INFO] fetching latest actions/runner release..."
json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"

# FIX: use python -c, stdin is JSON only (no mixing code+json)
url="$(python3 -c '
import json,sys
j=json.load(sys.stdin)
for a in j.get("assets",[]):
    n=a.get("name","")
    u=a.get("browser_download_url","")
    if n.endswith(".tar.gz") and "linux-x64" in n:
        print(u)
        raise SystemExit(0)
print("")
' <<<"$json")"

[ -n "$url" ] || { echo "[ERR] failed to locate linux-x64 runner tarball URL"; exit 2; }
echo "[INFO] download: $url"

tgz="actions-runner-linux-x64.tar.gz"
rm -f "$tgz"
curl -fsSL "$url" -o "$tgz"

echo "[INFO] extracting runner..."
mkdir -p _work
tar -xzf "$tgz"

# Best effort deps
if [ -x "./bin/installdependencies.sh" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    echo "[INFO] installing deps (best effort)..."
    sudo ./bin/installdependencies.sh || true
  else
    echo "[INFO] deps script exists but sudo not available; skip"
  fi
fi

# Configure
if [ -f ".runner" ]; then
  echo "[INFO] runner already configured (.runner exists) -> skip config"
else
  echo "[INFO] configuring runner..."
  ./config.sh --unattended \
    --url "$GH_RUNNER_URL" \
    --token "$GH_RUNNER_TOKEN" \
    --name "$NAME_DEF" \
    --labels "$LABELS_DEF" \
    --work "_work"
fi

# Install & start service
if [ -x "./svc.sh" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    echo "[INFO] installing service as user: $USER_DEF"
    sudo ./svc.sh install "$USER_DEF" || sudo ./svc.sh install
    echo "[INFO] starting service..."
    sudo ./svc.sh start
    echo "[INFO] status:"
    sudo ./svc.sh status || true
  else
    echo "[WARN] sudo -n not available; cannot install service automatically."
    echo "       Run:"
    echo "       cd $DIR_DEF && sudo ./svc.sh install $USER_DEF && sudo ./svc.sh start"
  fi
else
  echo "[ERR] svc.sh not found (extract failed?)"
  exit 2
fi

# Optional sudoers allowlist for restarting ONLY vsp-ui-8910.service
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDOERS="/etc/sudoers.d/vsp_runner_systemctl"
  echo "[INFO] writing sudoers allowlist: $SUDOERS"
  sudo tee "$SUDOERS" >/dev/null <<EOF
$USER_DEF ALL=(root) NOPASSWD: /bin/systemctl restart vsp-ui-8910.service, /bin/systemctl is-active vsp-ui-8910.service, /bin/systemctl status vsp-ui-8910.service
EOF
  sudo chmod 0440 "$SUDOERS"
  echo "[OK] sudoers installed"
else
  echo "[INFO] sudoers not installed (no passwordless sudo)"
fi

echo "[OK] runner installed. Next: push repo and run workflow in GitHub Actions."
