#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

mkdir -p bin/legacy

pick_legacy(){
  # pick newest matching script in bin/legacy
  local pat="$1"
  ls -1t bin/legacy/$pat 2>/dev/null | head -n1 || true
}

write_exec(){
  local f="$1"; shift
  cat > "$f" <<EOF
$*
EOF
  chmod +x "$f"
  echo "[OK] wrote +x $f"
}

# --- resolve legacy targets (fallback by newest match) ---
P550="$(pick_legacy 'p550_gate_run_to_report_v1*.sh')"
P525="$(pick_legacy 'p525_verify_release_and_customer_smoke_v*.sh')"
P39="$(pick_legacy 'p39_pack_commercial_release_v*.sh')"
P559="$(pick_legacy 'p559_commercial_preflight_audit_v*.sh')"

# sanity: gate must exist in legacy
if [ -z "$P550" ]; then
  echo "[ERR] cannot find legacy p550 gate under bin/legacy/p550_gate_run_to_report_v1*.sh"
  exit 2
fi

# 1) ui_gate.sh
write_exec bin/ui_gate.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo \"[ui_gate] using: $P550\"
bash \"$P550\"
"

# 2) verify_release_and_customer_smoke.sh
# prefer P525 if exists; else just run ui_gate as minimal contract
if [ -n "$P525" ]; then
  write_exec bin/verify_release_and_customer_smoke.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
bash bin/ui_gate.sh
echo \"[verify] using: $P525\"
bash \"$P525\"
"
else
  write_exec bin/verify_release_and_customer_smoke.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo \"[verify] legacy p525 not found; running ui_gate only\"
bash bin/ui_gate.sh
"
fi

# 3) pack_release.sh
# enforce: must PASS gate before packing. prefer legacy p39 pack if exists.
if [ -n "$P39" ]; then
  write_exec bin/pack_release.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# Hard gate: must pass before pack
bash bin/ui_gate.sh

echo \"[pack_release] using: $P39\"
bash \"$P39\"
"
else
  write_exec bin/pack_release.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
bash bin/ui_gate.sh
echo \"[pack_release] legacy p39 pack not found; gate passed but no pack script available\"
exit 3
"
fi

# 4) preflight_audit.sh (official alias)
if [ -n "$P559" ]; then
  write_exec bin/preflight_audit.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo \"[preflight] using: $P559\"
bash \"$P559\"
"
else
  write_exec bin/preflight_audit.sh "#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo \"[preflight] legacy p559 not found\"
exit 4
"
fi

echo "[OK] p562 done. Entry points:"
ls -l bin/ui_gate.sh bin/verify_release_and_customer_smoke.sh bin/pack_release.sh bin/ops.sh bin/preflight_audit.sh 2>/dev/null || true
