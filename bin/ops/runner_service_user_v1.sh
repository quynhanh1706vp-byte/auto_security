#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

UNIT_NAME="${GH_RUNNER_UNIT:-gh-runner.service}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"

detect_runner_root() {
  # explicit override wins
  if [ -n "${RUNNER_ROOT:-}" ] && [ -d "${RUNNER_ROOT}" ]; then
    echo "$RUNNER_ROOT"; return 0
  fi

  # common locations
  for d in \
    "/home/test/actions-runner" \
    "/home/test/actions-runner-"* \
    "$HOME/actions-runner" \
    "$HOME/actions-runner-"* \
    "/opt/actions-runner" \
    "/opt/actions-runner-"* \
  ; do
    [ -d "$d" ] || continue
    [ -f "$d/config.sh" ] && { echo "$d"; return 0; }
  done

  echo ""
  return 1
}

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }

write_unit() {
  local rr="$1"
  mkdir -p "$UNIT_DIR"

  local exec=""
  if [ -x "$rr/run.sh" ]; then
    exec="$rr/run.sh"
  elif [ -x "$rr/run" ]; then
    exec="$rr/run"
  else
    echo "[ERR] runner exec not found under $rr (need run.sh or run)"
    exit 2
  fi

  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=GitHub Actions Runner (user) - commercial ops
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$rr
ExecStart=/usr/bin/env bash -lc '$exec'
Restart=always
RestartSec=2
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT

  echo "[OK] wrote unit: $UNIT_PATH"
}

install() {
  need systemctl

  local rr
  rr="$(detect_runner_root || true)"
  if [ -z "$rr" ]; then
    echo "[FAIL] Cannot auto-detect runner dir."
    echo "Try:"
    echo "  RUNNER_ROOT=/home/test/actions-runner bash $0 install"
    exit 2
  fi

  echo "[INFO] runner_root=$rr"
  write_unit "$rr"

  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT_NAME" >/dev/null
  echo "[OK] enabled+started: $UNIT_NAME"
  systemctl --user --no-pager -l status "$UNIT_NAME" || true

  echo ""
  echo "[NOTE] Boot without login needs (ops-only): sudo loginctl enable-linger $USER"
}

status(){ need systemctl; systemctl --user --no-pager -l status "$UNIT_NAME" || true; }
restart(){ need systemctl; systemctl --user restart "$UNIT_NAME"; }
logs(){ command -v journalctl >/dev/null 2>&1 || { echo "[ERR] missing: journalctl"; exit 2; }; journalctl --user -u "$UNIT_NAME" -n "${N:-200}" --no-pager || true; }
uninstall(){ need systemctl; systemctl --user disable --now "$UNIT_NAME" >/dev/null 2>&1 || true; rm -f "$UNIT_PATH" || true; systemctl --user daemon-reload || true; }

cmd="${1:-install}"
case "$cmd" in
  install|status|restart|logs|uninstall) "$cmd" ;;
  *) echo "Usage: $0 {install|status|restart|logs|uninstall}"; exit 2 ;;
esac
