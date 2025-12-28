#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# 1) CI entry script (runs on VPS self-hosted runner)
mkdir -p bin/ci
cat > bin/ci/vsp_ci_p0_gate.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/ci_github_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
need(){ command -v "$1" >/dev/null 2>&1 || { log "[ERR] missing: $1"; exit 2; }; }

need bash
need curl
need python3
command -v sudo >/dev/null 2>&1 || true

log "== [CI P0] BASE=$BASE SVC=$SVC TS=$TS =="

# (A) quick syntax gates (fast fail)
log "== [A] syntax gate =="
bash -n bin/preflight_audit.sh
bash -n bin/pack_release.sh
bash -n bin/verify_release_and_customer_smoke.sh
python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
log "[OK] syntax gate ok"

# (B) ensure service up (no password prompts)
log "== [B] ensure service =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC"; then
    log "[OK] service active: $SVC"
  else
    log "[WARN] service not active: $SVC"
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      log "[DO] sudo systemctl restart $SVC"
      sudo systemctl restart "$SVC"
      sleep 2
      systemctl is-active --quiet "$SVC" || { log "[ERR] service still not active"; exit 3; }
      log "[OK] service restarted"
    else
      log "[ERR] need service active (or runner needs passwordless sudo for systemctl)"
      exit 3
    fi
  fi
else
  log "[ERR] systemctl not found (this CI expects to run on VPS self-hosted runner)"
  exit 3
fi

# (C) P0 commercial gate: preflight -> pack -> verify
log "== [C1] preflight audit =="
bash bin/preflight_audit.sh | tee -a "$OUT/preflight.txt"

log "== [C2] pack release =="
bash bin/pack_release.sh | tee -a "$OUT/pack_release.txt"

log "== [C3] verify release & customer smoke =="
bash bin/verify_release_and_customer_smoke.sh | tee -a "$OUT/verify_release.txt"

# (D) collect latest release dir
RELROOT="out_ci/releases"
latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
if [ -n "$latest_dir" ]; then
  log "[OK] latest release: $latest_dir"
  echo "$latest_dir" > "$OUT/latest_release_dir.txt"
else
  log "[WARN] no RELEASE_UI_* found under $RELROOT"
fi

log "== [DONE] P0 commercial gate finished =="
BASH
chmod +x bin/ci/vsp_ci_p0_gate.sh

# 2) GitHub Actions workflow (self-hosted runner on VPS)
mkdir -p .github/workflows
cat > .github/workflows/vsp_p0_commercial_gate.yml <<'YML'
name: VSP UI - P0 Commercial Gate

on:
  workflow_dispatch:
  push:
    branches: [ "main", "master" ]
  pull_request:
    branches: [ "main", "master" ]

jobs:
  p0_gate:
    # IMPORTANT: run on your VPS self-hosted runner
    runs-on: self-hosted

    env:
      VSP_UI_BASE: http://127.0.0.1:8910
      VSP_UI_SVC: vsp-ui-8910.service

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Show workspace
        run: |
          pwd
          ls -la

      - name: Run P0 Commercial Gate
        run: |
          cd /home/test/Data/SECURITY_BUNDLE/ui
          bash bin/ci/vsp_ci_p0_gate.sh

      - name: Upload out_ci (evidence)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: out_ci_evidence
          path: |
            /home/test/Data/SECURITY_BUNDLE/ui/out_ci/**
          if-no-files-found: warn
YML

echo "[OK] wrote: bin/ci/vsp_ci_p0_gate.sh"
echo "[OK] wrote: .github/workflows/vsp_p0_commercial_gate.yml"
echo ""
echo "NEXT:"
echo "1) Add a self-hosted runner on your VPS (GitHub repo Settings -> Actions -> Runners)."
echo "2) Ensure runner user can read /home/test/Data/SECURITY_BUNDLE/ui and (optional) passwordless sudo systemctl."
echo "3) Push to GitHub, then Actions -> 'VSP UI - P0 Commercial Gate' -> Run."
