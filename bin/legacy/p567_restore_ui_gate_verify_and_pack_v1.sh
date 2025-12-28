#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p567_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/run.log"; }

log "== [P567] restore ui_gate + verify + patch pack_release =="

mkdir -p bin/legacy official

# pick newest legacy script
pick_legacy(){ ls -1t bin/legacy/$1 2>/dev/null | head -n1 || true; }

P550="$(pick_legacy 'p550_gate_run_to_report_v1*.sh')"
P525="$(pick_legacy 'p525_verify_release_and_customer_smoke_v*.sh')"

[ -n "$P550" ] || { echo "[ERR] missing legacy P550 under bin/legacy/p550_gate_run_to_report_v1*.sh"; exit 2; }

# 1) official/ui_gate.sh
cat > official/ui_gate.sh <<EOS
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[ui_gate] using: $P550"
bash "$P550"
EOS
chmod +x official/ui_gate.sh
bash -n official/ui_gate.sh
ln -sf ../official/ui_gate.sh bin/ui_gate.sh
log "[OK] restored official/ui_gate.sh + symlink bin/ui_gate.sh"

# 2) official/verify_release_and_customer_smoke.sh
if [ -n "$P525" ]; then
  cat > official/verify_release_and_customer_smoke.sh <<EOS
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
bash official/ui_gate.sh
echo "[verify] using: $P525"
bash "$P525"
EOS
else
  cat > official/verify_release_and_customer_smoke.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[verify] legacy p525 not found; run ui_gate only"
bash official/ui_gate.sh
EOS
fi
chmod +x official/verify_release_and_customer_smoke.sh
bash -n official/verify_release_and_customer_smoke.sh
ln -sf ../official/verify_release_and_customer_smoke.sh bin/verify_release_and_customer_smoke.sh
log "[OK] restored official/verify_release_and_customer_smoke.sh + symlink"

# 3) Patch official/pack_release.sh to call official/ui_gate.sh and copy artifacts broadly
if [ -f official/pack_release.sh ]; then
  cp -f official/pack_release.sh official/pack_release.sh.bak_p567_${TS}
  log "[OK] backup official/pack_release.sh -> .bak_p567_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re
p=Path("official/pack_release.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# make gate call robust
s=re.sub(r'\bbash\s+bin/ui_gate\.sh\b', 'bash official/ui_gate.sh', s)
s=re.sub(r'\bbash\s+bin/ui_gate\.sh\b', 'bash official/ui_gate.sh', s)

# broaden artifact copy: copy any *.html/*.pdf/*.tgz in p550_latest (maxdepth 1)
if "copied=0" in s and "report_*.html" in s:
    s=re.sub(
        r'for f in "\$p550_latest"/report_\*\.html "\$p550_latest"/report_\*\.pdf "\$p550_latest"/support_bundle_\*\.tgz; do',
        'for f in "$p550_latest"/*.html "$p550_latest"/*.pdf "$p550_latest"/*.tgz; do',
        s
    )

p.write_text(s, encoding="utf-8")
print("[OK] patched official/pack_release.sh")
PY

  bash -n official/pack_release.sh
  log "[OK] patched + syntax ok: official/pack_release.sh"
else
  log "[WARN] missing official/pack_release.sh (but bin/pack_release.sh symlink exists?)"
fi

# ensure bin/pack_release.sh points to official
ln -sf ../official/pack_release.sh bin/pack_release.sh
chmod +x official/pack_release.sh || true

# 4) Relock numeric-only (move bin/p[0-9]*.sh into legacy, keep pack/preflight safe)
if [ -x bin/relock_numeric_only.sh ]; then
  log "== relock numeric-only =="
  bash bin/relock_numeric_only.sh | tee -a "$OUT/relock.log" || true
else
  log "[WARN] missing bin/relock_numeric_only.sh"
fi

# 5) Run pack + preflight
log "== run pack_release =="
bash bin/pack_release.sh | tee -a "$OUT/pack_release.log" || true

log "== run preflight =="
bash bin/preflight_audit.sh | tee -a "$OUT/preflight.log" || true

log "== [P567] DONE OUT=$OUT =="
echo "OUT=$OUT"
