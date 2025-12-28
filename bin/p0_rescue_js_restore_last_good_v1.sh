#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need node; need sed; need head

TS="$(date +%Y%m%d_%H%M%S)"

FILES=()
[ -f static/js/vsp_bundle_commercial_v2.js ] && FILES+=(static/js/vsp_bundle_commercial_v2.js)
[ -f static/js/vsp_bundle_commercial_v1.js ] && FILES+=(static/js/vsp_bundle_commercial_v1.js)
[ -f static/js/vsp_dashboard_gate_story_v1.js ] && FILES+=(static/js/vsp_dashboard_gate_story_v1.js)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no target JS found under static/js"; exit 2; }

node_ok(){ node --check "$1" >/dev/null 2>&1; }

restore_one(){
  local f="$1"
  cp -f "$f" "${f}.bak_before_js_rescue_${TS}"
  echo "[BACKUP] ${f}.bak_before_js_rescue_${TS}"

  mapfile -t CANDS < <(ls -1t "$f" "${f}.bak_"* 2>/dev/null || true)
  local good=""
  for c in "${CANDS[@]}"; do
    if node_ok "$c"; then
      good="$c"
      echo "[GOOD] $c"
      break
    else
      echo "[BAD ] $c"
    fi
  done
  [ -n "$good" ] || { echo "[ERR] no node-check-good backup for $f"; exit 2; }

  if [ "$good" != "$f" ]; then
    cp -f "$good" "$f"
    echo "[RESTORED] $f <= $good"
  else
    echo "[KEEP] current $f already node --check OK"
  fi

  # sanitize: any line starting with "#" -> "//"
  sed -i 's/^[[:space:]]*#[[:space:]]*/\/\/ /' "$f" || true

  node --check "$f" >/dev/null
  echo "[OK] node --check OK (final): $f"
}

for f in "${FILES[@]}"; do restore_one "$f"; done

echo "== done =="
echo "NOW in browser console run:"
echo "  localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "Then Ctrl+F5 /vsp5 (or open Incognito)."
