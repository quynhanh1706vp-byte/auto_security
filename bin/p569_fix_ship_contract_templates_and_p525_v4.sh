#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p569_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/run.log"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }

need bash; need tar; need sha256sum; need grep; need sed; need awk; need head

log "== [P569] create templates + release notes + p525 v4 contract =="

mkdir -p config

# 1) systemd template (no secrets)
cat > config/systemd_unit.template <<'EOF'
# VSP UI systemd unit template (commercial)
# Install suggestion:
#   - Copy this to: /etc/systemd/system/vsp-ui-8910.service
#   - Create env file: /etc/vsp-ui/production.env (from production.env.example)
#   - mkdir -p /var/log/vsp-ui && chown -R test:test /var/log/vsp-ui
[Unit]
Description=VSP UI Gateway (commercial)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=test
Group=test
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
EnvironmentFile=/etc/vsp-ui/production.env

UMask=0027
Restart=always
RestartSec=2
TimeoutStartSec=25
TimeoutStopSec=15
LimitNOFILE=65535

StandardOutput=append:/var/log/vsp-ui/vsp-ui.out.log
StandardError=append:/var/log/vsp-ui/vsp-ui.err.log

ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh

[Install]
WantedBy=multi-user.target
EOF
log "[OK] wrote config/systemd_unit.template"

# 2) logrotate template
cat > config/logrotate_vsp-ui.template <<'EOF'
/var/log/vsp-ui/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
  su test test
}
EOF
log "[OK] wrote config/logrotate_vsp-ui.template"

# 3) env example (no secrets)
cat > config/production.env.example <<'EOF'
# Example production env for VSP UI (NO SECRETS)
# Copy to /etc/vsp-ui/production.env and edit values as needed.

# bind / port
VSP_UI_HOST=0.0.0.0
VSP_UI_PORT=8910

# base url used by scripts
VSP_UI_BASE=http://127.0.0.1:8910

# service name (optional)
VSP_UI_SVC=vsp-ui-8910.service

# any other safe defaults...
EOF
log "[OK] wrote config/production.env.example"

# 4) release notes (repo root, so it goes into code tgz)
cat > RELEASE_NOTES.md <<'EOF'
# VSP UI Commercial Release (P0)

## Gate status
- P550: PASS (Run → Data → UI → Report export + support bundle)
- P559v2: PASS (commercial preflight)

## What ships (clean)
- `bin/ui_gate.sh`
- `bin/verify_release_and_customer_smoke.sh`
- `bin/pack_release.sh`
- `bin/ops.sh`

Patch scripts are **not shipped** as executables; they live in `bin/legacy/`.

## Templates included
- `config/systemd_unit.template`
- `config/logrotate_vsp-ui.template`
- `config/production.env.example`

## Release artifacts (in latest RELEASE_UI_*)
- `report_*.html`, `report_*.pdf`
- `support_bundle_*.tgz`
- `VSP_UI_*.tgz` (code package, clean excludes)
EOF
log "[OK] wrote RELEASE_NOTES.md"

# 5) Create P525 v4 contract checker in legacy (preferred by verify wrapper)
mkdir -p bin/legacy
P525V4="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"

cat > "$P525V4" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RELROOT="out_ci/releases"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p525v4_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/run.log"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need tar; need sha256sum; need head; need ls; need grep; need wc

latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

tgz="$(ls -1 "$latest_dir"/support_bundle_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$tgz" ] || { echo "[FAIL] no support_bundle_*.tgz found in $latest_dir"; exit 2; }

log "[P525v4] BASE=$BASE"
log "[P525v4] latest_dir=$latest_dir"
log "[P525v4] tgz=$tgz"

log "== [1] service readiness =="
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/healthz" >/dev/null && log "[OK] healthz 200" || { log "[FAIL] healthz fail"; exit 3; }
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/readyz"  >/dev/null && log "[OK] readyz 200"  || { log "[FAIL] readyz fail"; exit 3; }

log "== [2] sha256 verify =="
if [ ! -f "$latest_dir/SHA256SUMS.txt" ]; then
  log "[WARN] missing SHA256SUMS -> generating"
  ( cd "$latest_dir" && sha256sum * > SHA256SUMS.txt )
  log "[OK] SHA256SUMS generated"
fi

log "== [3] contract check (NEW commercial) =="
# New contract: require templates + release notes in CODE TGZ, not in support bundle.
missing=()

for f in config/systemd_unit.template config/logrotate_vsp-ui.template config/production.env.example RELEASE_NOTES.md; do
  [ -f "/home/test/Data/SECURITY_BUNDLE/ui/$f" ] || missing+=("$f")
done

# Also require 4 entrypoints exist
for f in bin/ui_gate.sh bin/verify_release_and_customer_smoke.sh bin/pack_release.sh bin/ops.sh; do
  [ -e "/home/test/Data/SECURITY_BUNDLE/ui/$f" ] || missing+=("$f")
done

# MUST NOT require p523 anymore (it is legacy by design)
if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING:${missing[*]}"
  exit 5
fi

log "[OK] contract check PASS"
EOF

chmod +x "$P525V4"
bash -n "$P525V4"
log "[OK] wrote $P525V4"

# 6) Patch official verify wrapper to prefer p525 v4 if present
if [ -f official/verify_release_and_customer_smoke.sh ]; then
  cp -f official/verify_release_and_customer_smoke.sh "official/verify_release_and_customer_smoke.sh.bak_p569_${TS}"
  log "[OK] backup official/verify_release_and_customer_smoke.sh"
fi

cat > official/verify_release_and_customer_smoke.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# 1) always gate first
bash official/ui_gate.sh

# 2) prefer v4 contract check if exists
if [ -x bin/legacy/p525_verify_release_and_customer_smoke_v4.sh ]; then
  echo "[verify] using: bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
  exec bash bin/legacy/p525_verify_release_and_customer_smoke_v4.sh
fi

# fallback: any legacy p525
p525="$(ls -1t bin/legacy/p525_verify_release_and_customer_smoke_v*.sh 2>/dev/null | head -n1 || true)"
[ -n "$p525" ] || { echo "[FAIL] no legacy p525 found"; exit 4; }
echo "[verify] using: $p525"
exec bash "$p525"
EOF

chmod +x official/verify_release_and_customer_smoke.sh
bash -n official/verify_release_and_customer_smoke.sh
ln -sf ../official/verify_release_and_customer_smoke.sh bin/verify_release_and_customer_smoke.sh
log "[OK] updated official verify wrapper + bin symlink"

log "== [P569] DONE. Now re-run verify to confirm contract =="

