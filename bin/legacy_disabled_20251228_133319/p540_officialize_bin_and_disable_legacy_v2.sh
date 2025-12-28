#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p540_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/log.txt"; }

pick_latest_any(){
  # usage: pick_latest_any "pat1" "pat2" ...
  local best=""
  for pat in "$@"; do
    # shellcheck disable=SC2086
    cand="$(ls -1 $pat 2>/dev/null | sort -V | tail -n1 || true)"
    if [ -n "$cand" ]; then best="$cand"; break; fi
  done
  echo "$best"
}

# --- Detect candidates (do NOT fail if missing) ---
P523="$(pick_latest_any \
  "bin/p523_verify_ui_gate_ops*.sh" \
  "bin/p523*gate*.sh" \
  "bin/p523*.sh" \
  "bin/*p523*.sh" \
)"

# "gate-ish" fallback if P523 missing
GATE_FALLBACK="$(pick_latest_any \
  "bin/p0_gateA_luxe_only_vsp5_no_out*.sh" \
  "bin/p0_gateA*.sh" \
  "bin/p520_commercial_selfcheck*.sh" \
  "bin/p455_commercial_smoke_one_cmd*.sh" \
)"

P525="$(pick_latest_any "bin/p525_verify_release_and_customer_smoke_v*.sh" "bin/p525_verify_release_and_customer_smoke*.sh")"
P532="$(pick_latest_any "bin/p532_pack*.sh" "bin/p39_pack_commercial_release*.sh" "bin/*pack*release*.sh")"
OPS="$(pick_latest_any "bin/vsp_ui_ops_safe_v*.sh" "bin/vsp_ui_ops_safe*.sh")"

log "[P540v2] detected:"
log "  P523=$P523"
log "  GATE_FALLBACK=$GATE_FALLBACK"
log "  P525=$P525"
log "  P532=$P532"
log "  OPS =$OPS"

mkdir -p bin/official

# --- Create official wrappers (stable entrypoints) ---
# ui_gate.sh: prefer P523; else fallback gate; else ops smoke; else create stub.
UI_GATE_WRAPPER="bin/official/ui_gate.sh"
if [ -n "$P523" ]; then
  ln -sfn "../$(basename "$P523")" "$UI_GATE_WRAPPER"
  log "[OK] ui_gate => $P523"
elif [ -n "$GATE_FALLBACK" ]; then
  ln -sfn "../$(basename "$GATE_FALLBACK")" "$UI_GATE_WRAPPER"
  log "[OK] ui_gate => fallback $GATE_FALLBACK"
elif [ -n "$OPS" ]; then
  # wrapper calls ops smoke
  cat > "$UI_GATE_WRAPPER" <<'W'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
bash bin/ops.sh smoke
W
  chmod +x "$UI_GATE_WRAPPER"
  log "[OK] ui_gate => ops smoke wrapper"
else
  cat > "$UI_GATE_WRAPPER" <<'W'
#!/usr/bin/env bash
echo "[ERR] no P523 / fallback gate / ops found. Nothing to run." >&2
exit 2
W
  chmod +x "$UI_GATE_WRAPPER"
  log "[WARN] ui_gate => stub (no gate found)"
fi

# verify_release_and_customer_smoke
if [ -n "$P525" ]; then
  ln -sfn "../$(basename "$P525")" bin/official/verify_release_and_customer_smoke.sh
  log "[OK] verify_release => $P525"
else
  log "[WARN] missing P525; skip verify_release alias"
fi

# pack_release
if [ -n "$P532" ]; then
  ln -sfn "../$(basename "$P532")" bin/official/pack_release.sh
  log "[OK] pack_release => $P532"
else
  log "[WARN] missing pack script (P532/P39); skip pack_release alias"
fi

# ops
if [ -n "$OPS" ]; then
  ln -sfn "../$(basename "$OPS")" bin/official/ops.sh
  log "[OK] ops => $OPS"
else
  log "[WARN] missing ops; skip ops alias"
fi

# --- Top-level shortcuts (stable names people type) ---
ln -sfn "official/ui_gate.sh" bin/ui_gate.sh
[ -f bin/official/verify_release_and_customer_smoke.sh ] && ln -sfn "official/verify_release_and_customer_smoke.sh" bin/verify_release_and_customer_smoke.sh || true
[ -f bin/official/pack_release.sh ] && ln -sfn "official/pack_release.sh" bin/pack_release.sh || true
[ -f bin/official/ops.sh ] && ln -sfn "official/ops.sh" bin/ops.sh || true

log "[OK] shortcuts created (bin/ui_gate.sh etc.)"

# --- Allowlist (do NOT disable our official entrypoints and their targets) ---
allow="$OUT/allow.txt"
{
  # wrappers + shortcuts
  echo "bin/official/ui_gate.sh"
  echo "bin/official/verify_release_and_customer_smoke.sh"
  echo "bin/official/pack_release.sh"
  echo "bin/official/ops.sh"
  echo "bin/ui_gate.sh"
  echo "bin/verify_release_and_customer_smoke.sh"
  echo "bin/pack_release.sh"
  echo "bin/ops.sh"

  # concrete picked targets
  [ -n "$P523" ] && echo "$P523" || true
  [ -n "$GATE_FALLBACK" ] && echo "$GATE_FALLBACK" || true
  [ -n "$P525" ] && echo "$P525" || true
  [ -n "$P532" ] && echo "$P532" || true
  [ -n "$OPS" ] && echo "$OPS" || true

  # keep any syntax gates if present
  [ -f bin/p43_bin_syntax_gate.py ] && echo "bin/p43_bin_syntax_gate.py" || true
  [ -f bin/p43_bin_syntax_gate.sh ] && echo "bin/p43_bin_syntax_gate.sh" || true
} | sed '/^$/d' | sort -u > "$allow"
log "[OK] allowlist => $allow"

# --- Disable executable scripts under bin/ not in allowlist ---
legacy_dir="bin/legacy_disabled_${TS}"
mkdir -p "$legacy_dir"

find bin -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -perm -u+x | sort > "$OUT/executables_before.txt"

disabled=0
while IFS= read -r f; do
  if grep -qx "$f" "$allow"; then
    continue
  fi

  base="$(basename "$f")"
  case "$base" in
    run_all.sh|unify.sh|pack_scan.sh|pack_report.sh) continue ;;
  esac

  cp -f "$f" "$legacy_dir/$base"
  chmod -x "$f" || true
  log "[DISABLE] $f (backup => $legacy_dir/$base)"
  disabled=$((disabled+1))
done < "$OUT/executables_before.txt"

find bin -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -perm -u+x | sort > "$OUT/executables_after.txt"

log "[OK] disabled_count=$disabled"
log "[OK] legacy saved => $legacy_dir"

echo
echo "=== OFFICIAL COMMANDS (use these only) ==="
echo "bash bin/ui_gate.sh"
[ -f bin/verify_release_and_customer_smoke.sh ] && echo "bash bin/verify_release_and_customer_smoke.sh" || true
[ -f bin/pack_release.sh ] && echo "bash bin/pack_release.sh" || true
[ -f bin/ops.sh ] && echo "bash bin/ops.sh smoke" || true
