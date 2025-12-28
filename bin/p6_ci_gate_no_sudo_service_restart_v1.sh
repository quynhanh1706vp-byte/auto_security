#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/ci/vsp_ci_p0_gate.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p6_${TS}"
echo "[OK] backup => ${F}.bak_p6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/ci/vsp_ci_p0_gate.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the whole "ensure service" block with a curl-based health check (no sudo)
pat = r'log "== \[B\] ensure service ==".*?log "== \[C1\] preflight audit =="'
m = re.search(pat, s, flags=re.S)
if not m:
    print("[WARN] pattern not found; not patched")
    raise SystemExit(0)

replacement = r'''log "== [B] ensure service (no-sudo) =="
if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/healthz" >/dev/null 2>&1; then
  log "[OK] healthz ok: $BASE/healthz"
else
  # fallback: try homepage
  curl -fsS --connect-timeout 2 --max-time 4 "$BASE/vsp5" >/dev/null 2>&1 || {
    log "[ERR] UI not reachable at $BASE (need service running)."
    exit 3
  }
  log "[OK] UI reachable: $BASE/vsp5"
fi

log "== [C1] preflight audit =="'''
s2 = re.sub(pat, replacement, s, flags=re.S)

p.write_text(s2, encoding="utf-8")
print("[OK] patched CI gate to no-sudo mode")
PY

bash -n "$F"
echo "[OK] bash -n ok"
