#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

REL_VER="${VSP_RELEASE_VER:-2025.12.28}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
OUT_DIR="${OUT_ROOT}/RELEASE_UI_${REL_VER}_${TS}"
PKG_NAME="VSP_UI_${REL_VER}_${TS}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

mkdir -p "$OUT_DIR"
log(){ echo "$*" | tee -a "$OUT_DIR/pack.log"; }

log "== [P521] pack commercial release v2 =="
log "ver=$REL_VER ts=$TS base=$BASE out=$OUT_DIR"

# 0) Gate UI before packing (avoid 'ok rồi mở ra cccc')
if [ -x "bin/p523_ui_commercial_gate_v1.sh" ]; then
  log "== [0] UI gate (P523) =="
  bash bin/p523_ui_commercial_gate_v1.sh | tee -a "$OUT_DIR/pack.log"
else
  log "[WARN] missing P523 gate -> strongly recommended to run it first"
fi

# 1) Run P520 selfcheck if present
if [ -x "bin/p520_commercial_selfcheck_v3.sh" ]; then
  log "== [1] selfcheck P520 =="
  bash bin/p520_commercial_selfcheck_v3.sh | tee -a "$OUT_DIR/p520.log" || { log "[FAIL] P520 failed"; exit 2; }
else
  log "[WARN] bin/p520_commercial_selfcheck_v3.sh not found -> skipped"
fi

# 2) Snapshot git/hash + env
GIT_COMMIT="(no-git)"
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo '(git-err)')"
fi
log "git=$GIT_COMMIT"

cp -f "config/production.env" "$OUT_DIR/production.env.snapshot" 2>/dev/null || true

python3 - <<PY > "$OUT_DIR/env_snapshot.json"
import os, json, platform, time
snap = {
  "ts": "$TS",
  "ver": "$REL_VER",
  "base": "$BASE",
  "platform": platform.platform(),
  "python": platform.python_version(),
  "env_keys": sorted([k for k in os.environ.keys() if k.startswith("VSP_")])
}
print(json.dumps(snap, indent=2, ensure_ascii=False))
PY

# 3) Stage files for release
STAGE="$OUT_DIR/$PKG_NAME"
mkdir -p "$STAGE"

# core app
cp -f vsp_demo_app.py "$STAGE/" 2>/dev/null || true
cp -f wsgi_vsp_ui_gateway.py "$STAGE/" 2>/dev/null || true

# ui assets
mkdir -p "$STAGE/templates" "$STAGE/static" "$STAGE/bin" "$STAGE/config" "$STAGE/docs"
cp -a templates/. "$STAGE/templates/" 2>/dev/null || true
cp -a static/. "$STAGE/static/" 2>/dev/null || true

# scripts (ship all bin except giant outputs)
cp -a bin/. "$STAGE/bin/" 2>/dev/null || true

# config templates
cp -a config/. "$STAGE/config/" 2>/dev/null || true

# systemd + logrotate templates inside package (for customers)
cat > "$STAGE/config/systemd_unit.template" <<EOF
# /etc/systemd/system/vsp-ui-8910.service (template)
[Unit]
Description=VSP UI Gateway (commercial)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
EnvironmentFile=/home/test/Data/SECURITY_BUNDLE/ui/config/production.env
UMask=0027
Restart=always
RestartSec=2
TimeoutStartSec=25
TimeoutStopSec=15
LimitNOFILE=65535
StandardOutput=append:/var/log/vsp-ui/vsp-ui.out.log
StandardError=append:/var/log/vsp-ui/vsp-ui.err.log
ExecStart=/home/test/Data/SECURITY_BUNDLE/.venv/bin/gunicorn -w 2 -b 0.0.0.0:8910 --access-logfile /var/log/vsp-ui/access.log --error-logfile /var/log/vsp-ui/gunicorn.log wsgi_vsp_ui_gateway:app

[Install]
WantedBy=multi-user.target
EOF

cat > "$STAGE/config/logrotate_vsp-ui.template" <<'EOF'
/var/log/vsp-ui/*.log /var/log/vsp-ui/access.log /var/log/vsp-ui/gunicorn.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF

# 4) Release notes (auto)
cat > "$OUT_DIR/RELEASE_NOTES.md" <<EOF
# VSP UI Release

- Version: ${REL_VER}
- Build time: ${TS}
- Git: ${GIT_COMMIT}

## What’s included
- UI Gateway source (templates/static)
- bin/ scripts (ops + selfcheck + pack)
- systemd unit template + logrotate template
- production.env snapshot (example)

## Required endpoints
- \`GET /api/healthz\`
- \`GET /api/readyz\`

## Pre-ship gates
- P523 UI commercial gate: PASS required
- P520 selfcheck: PASS recommended (included log if available)

## Install (high-level)
1. Copy package to target host
2. Create venv + install deps
3. Put \`config/production.env\` in place (edit only this)
4. Install systemd unit + enable + start
5. Verify:
   - ${BASE}/api/healthz
   - ${BASE}/api/readyz
EOF


# === P527_PACK_CONTRACT_GATE_V1: refuse to pack if missing required files ===
req_in_stage=(
  "$STAGE/config/systemd_unit.template"
  "$STAGE/config/logrotate_vsp-ui.template"
  "$STAGE/config/production.env"
)
for rf in "${req_in_stage[@]}"; do
  if [ ! -f "$rf" ]; then
    echo "[FAIL] missing required in stage: $rf" >&2
    echo "[HINT] ensure config/production.env exists AND templates written before tar" >&2
    find "$STAGE" -maxdepth 3 -type f | head -n 120 >&2 || true
    exit 2
  fi
done
echo "[OK] pack contract satisfied (templates + production.env present)"
# === end P527 gate ===


# 5) Build tgz + sha256
cd "$OUT_DIR"
tar -czf "${PKG_NAME}.tgz" "$PKG_NAME"
sha256sum "${PKG_NAME}.tgz" > SHA256SUMS

log "== [DONE] =="
log "artifact: $OUT_DIR/${PKG_NAME}.tgz"
log "sha256 : $OUT_DIR/SHA256SUMS"
