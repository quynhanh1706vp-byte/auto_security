#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p540_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/log.txt"; }

pick_latest(){
  local pat="$1"
  # version-sort (v1,v2,v3...) then pick last
  ls -1 bin/$pat 2>/dev/null | sort -V | tail -n1 || true
}

# ---- 1) pick latest "official" implementations (auto) ----
P523="$(pick_latest 'p523_verify_ui_gate_ops*.sh')"
P525="$(pick_latest 'p525_verify_release_and_customer_smoke_v*.sh')"
P532="$(pick_latest 'p532_pack*.sh')"
OPS="$(pick_latest 'vsp_ui_ops_safe_v*.sh')"

log "[P540] detected:"
log "  P523=$P523"
log "  P525=$P525"
log "  P532=$P532"
log "  OPS =$OPS"

# hard requirements (you can relax later)
[ -n "$P523" ] || { log "[FAIL] missing P523 under bin/"; exit 2; }
[ -n "$P525" ] || { log "[FAIL] missing P525v* under bin/"; exit 2; }
[ -n "$P532" ] || { log "[WARN] missing P532 pack script under bin/ (skip pack alias)"; }
[ -n "$OPS"  ] || { log "[WARN] missing vsp_ui_ops_safe_v* under bin/ (skip ops alias)"; }

# ---- 2) create stable aliases (the ONLY names people should use) ----
mkdir -p bin/official
ln -sfn "../$P523" bin/official/ui_gate.sh
ln -sfn "../$P525" bin/official/verify_release_and_customer_smoke.sh
[ -n "$P532" ] && ln -sfn "../$P532" bin/official/pack_release.sh || true
[ -n "$OPS"  ] && ln -sfn "../$OPS"  bin/official/ops.sh || true

# optional: legacy-friendly top-level shortcuts
ln -sfn "official/ui_gate.sh" bin/ui_gate.sh
ln -sfn "official/verify_release_and_customer_smoke.sh" bin/verify_release_and_customer_smoke.sh
[ -n "$P532" ] && ln -sfn "official/pack_release.sh" bin/pack_release.sh || true
[ -n "$OPS"  ] && ln -sfn "official/ops.sh" bin/ops.sh || true

log "[OK] official aliases created under bin/official + top-level shortcuts."

# ---- 3) build allowlist: official targets + a small safe baseline ----
allow="$OUT/allow.txt"
{
  echo "bin/$P523"
  echo "bin/$P525"
  [ -n "$P532" ] && echo "bin/$P532" || true
  [ -n "$OPS"  ] && echo "bin/$OPS"  || true

  # stable aliases
  echo "bin/official/ui_gate.sh"
  echo "bin/official/verify_release_and_customer_smoke.sh"
  [ -n "$P532" ] && echo "bin/official/pack_release.sh" || true
  [ -n "$OPS"  ] && echo "bin/official/ops.sh" || true

  echo "bin/ui_gate.sh"
  echo "bin/verify_release_and_customer_smoke.sh"
  [ -n "$P532" ] && echo "bin/pack_release.sh" || true
  [ -n "$OPS"  ] && echo "bin/ops.sh" || true

  # keep these “meta” scripts if exist
  [ -f bin/p43_bin_syntax_gate.py ] && echo "bin/p43_bin_syntax_gate.py" || true
  [ -f bin/p43_bin_syntax_gate.sh ] && echo "bin/p43_bin_syntax_gate.sh" || true
} | sed '/^$/d' | sort -u > "$allow"
log "[OK] allowlist => $allow"

# ---- 4) disable executable scripts not in allowlist ----
legacy_dir="bin/legacy_disabled_${TS}"
mkdir -p "$legacy_dir"

# list executable files under bin/ (sh, py)
find bin -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -perm -u+x | sort > "$OUT/executables_before.txt"

disabled=0
while IFS= read -r f; do
  # skip allowlist
  if grep -qx "$f" "$allow"; then
    continue
  fi

  base="$(basename "$f")"
  # never touch these by default
  case "$base" in
    run_all.sh|unify.sh|pack_scan.sh|pack_report.sh) continue ;;
  esac

  log "[DISABLE] $f -> $legacy_dir/$base (and remove +x)"
  cp -f "$f" "$legacy_dir/$base"
  chmod -x "$f" || true
  disabled=$((disabled+1))
done < "$OUT/executables_before.txt"

find bin -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -perm -u+x | sort > "$OUT/executables_after.txt"
log "[OK] disabled_count=$disabled"
log "[OK] legacy saved => $legacy_dir"
log "[OK] review: $OUT/executables_before.txt vs $OUT/executables_after.txt"

echo
echo "=== OFFICIAL COMMANDS ==="
echo "bash bin/ui_gate.sh"
echo "bash bin/verify_release_and_customer_smoke.sh"
[ -n "$P532" ] && echo "bash bin/pack_release.sh" || true
[ -n "$OPS"  ] && echo "bash bin/ops.sh <smoke|...>" || true
