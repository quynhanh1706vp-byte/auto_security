#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

REL_VER="${VSP_RELEASE_VER:-2025.12.28}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
OUT_DIR="${OUT_ROOT}/RELEASE_UI_${REL_VER}_${TS}"
PKG="VSP_UI_${REL_VER}_${TS}"
STAGE="${OUT_DIR}/${PKG}"

mkdir -p "$STAGE"/{bin,config,static,templates,reports,docs}
log(){ echo "$*" | tee -a "$OUT_DIR/pack_clean.log"; }

GIT_SHA="(no-git)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "(no-git)")"
fi

log "== [P531] clean pack =="
log "ver=$REL_VER ts=$TS out=$OUT_DIR git=$GIT_SHA"

# ensure production.env exists (minimal)
if [ ! -f config/production.env ]; then
  cat > config/production.env <<'ENV'
VSP_UI_BASE=http://127.0.0.1:8910
VSP_UI_SVC=vsp-ui-8910.service
VSP_DATA_ROOT=/home/test/Data/SECURITY_BUNDLE
VSP_P504_TTL=30
VSP_P504_MAX_MB=64
VSP_CSP_ENFORCE=1
VSP_CSP_REPORT=1
ENV
  log "[WARN] config/production.env missing -> generated minimal defaults"
fi

# templates
cat > "$STAGE/config/systemd_unit.template" <<'UNIT'
[Unit]
Description=VSP UI Gateway (commercial)
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
EnvironmentFile=/home/test/Data/SECURITY_BUNDLE/ui/config/production.env
ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn -w 2 -b 0.0.0.0:8910 wsgi_vsp_ui_gateway:app
Restart=always
RestartSec=2
TimeoutStartSec=20
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

cat > "$STAGE/config/logrotate_vsp-ui.template" <<'LR'
/var/log/vsp-ui/*.log {
  rotate 14
  daily
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
LR

# copy essentials (exclude out_ci)
cp -a bin "$STAGE/" 2>/dev/null || true
cp -a static "$STAGE/" 2>/dev/null || true
cp -a templates "$STAGE/" 2>/dev/null || true
cp -a config/production.env "$STAGE/config/production.env"

# app entrypoints
[ -f vsp_demo_app.py ] && cp -f vsp_demo_app.py "$STAGE/" || true
[ -f wsgi_vsp_ui_gateway.py ] && cp -f wsgi_vsp_ui_gateway.py "$STAGE/" || true
[ -f requirements.txt ] && cp -f requirements.txt "$STAGE/" || true
[ -f README.md ] && cp -f README.md "$STAGE/docs/" || true

# release notes
cat > "$STAGE/RELEASE_NOTES.md" <<EOF
# VSP UI Release $REL_VER ($TS)

- Git: $GIT_SHA
- Package: $PKG
- Includes: templates/, static/, bin/, config/production.env + systemd/logrotate templates
- Gates: P523 + P520 should be run on target after install
EOF

# pack
( cd "$OUT_DIR" && tar -czf "${PKG}.tgz" "${PKG}" )
( cd "$OUT_DIR" && sha256sum "${PKG}.tgz" > SHA256SUMS )

log "[OK] artifact=$OUT_DIR/${PKG}.tgz"
log "[OK] sha256=$OUT_DIR/SHA256SUMS"

# verify tar contains required files
need=(
  "config/systemd_unit.template"
  "config/logrotate_vsp-ui.template"
  "config/production.env"
  "RELEASE_NOTES.md"
  "bin/p523_ui_commercial_gate_v1.sh"
)
for x in "${need[@]}"; do
  if tar -tzf "$OUT_DIR/${PKG}.tgz" | grep -Fq "/$x"; then
    log "[OK] tgz has $x"
  else
    log "[FAIL] tgz missing $x"
    exit 2
  fi
done

log "== [DONE] P531 PASS =="
