#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/commercial_ui_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_inplace_${TS}"
echo "[BACKUP] ${F}.bak_inplace_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("bin/commercial_ui_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

def replace_func(src: str, name: str, new_block: str) -> str:
    # Find "name(){"
    key = f"{name}(){{"
    i = src.find(key)
    if i < 0:
        raise SystemExit(f"[ERR] cannot find function {name}(){{")
    # Walk braces to find matching closing brace
    j = i + len(key)
    depth = 1
    while j < len(src):
        ch = src[j]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                # include closing brace
                j += 1
                break
        j += 1
    if depth != 0:
        raise SystemExit(f"[ERR] brace match failed for {name}")
    return src[:i] + new_block + src[j:]

choose_base = r'''_choose_base(){
  # Prefer current BASE, then IPv4, then localhost, then IPv6.
  local cand=("$BASE" "http://127.0.0.1:8910" "http://localhost:8910" "http://[::1]:8910")
  for b in "${cand[@]}"; do
    [ -n "$b" ] || continue
    # Fast readiness probe first (usually <2s but allow headroom)
    if curl -fsS --connect-timeout 2 --max-time 10 -o /dev/null "$b/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
    # Fallback to /vsp5 which may be slow on warm-up
    if curl -fsS --connect-timeout 2 --max-time 15 -o /dev/null "$b/vsp5" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
  done
  return 1
}
'''

wait_up = r'''wait_up(){
  _choose_base || { red "UI not reachable (all base candidates failed)"; return 1; }

  for i in $(seq 1 40); do
    # Prefer selfcheck (fast, stable)
    if curl_do 12 -o /dev/null "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      pass "UI up (selfcheck): $BASE"
      return 0
    fi
    # Accept /vsp5 too, but give it time
    if curl_do 18 -o /dev/null "$BASE/vsp5" >/dev/null 2>&1; then
      pass "UI up (/vsp5): $BASE"
      return 0
    fi
    sleep 0.25
  done

  red "UI not reachable: $BASE"
  return 1
}
'''

s2 = s
s2 = replace_func(s2, "_choose_base", choose_base)
s2 = replace_func(s2, "wait_up", wait_up)

# Optional: remove any previously appended override blocks to avoid confusion (safe).
for marker in ["VSP_AUDIT_WAITUP_SLOW_V1", "VSP_AUDIT_BASE_FALLBACK_V1", "VSP_AUDIT_NOPROXY_V1"]:
    # just keep; no need to delete aggressively

    pass

p.write_text(s2, encoding="utf-8")
print("[OK] patched _choose_base + wait_up in-place")
PY

echo "[OK] patched $F"
