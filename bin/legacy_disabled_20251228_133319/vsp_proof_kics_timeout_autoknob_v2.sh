#!/usr/bin/env bash
set -euo pipefail

T="${1:-15}"
PROFILE="${2:-FULL_EXT}"
TARGET="${3:-/home/test/Data/SECURITY-10-10-v4}"
UI="http://127.0.0.1:8910"   # tránh IPv6 localhost

cd /home/test/Data/SECURITY_BUNDLE/ui
RUNNER="/home/test/Data/SECURITY_BUNDLE/bin/run_all_tools_v2.sh"
KICS_SH="/home/test/Data/SECURITY_BUNDLE/bin/run_kics_v2.sh"

[ -f "$RUNNER" ] || { echo "[ERR] missing $RUNNER"; exit 2; }
[ -f "$KICS_SH" ] || { echo "[ERR] missing $KICS_SH"; exit 2; }

echo "[AUTO] Detecting timeout knobs for KICS from runner scripts..."
VARS="$(python3 - <<PY
import re, pathlib

paths=[pathlib.Path("$RUNNER"), pathlib.Path("$KICS_SH")]
cands=set()

for p in paths:
    txt=p.read_text(encoding="utf-8", errors="ignore")
    # focus around KICS / run_kics / timeout
    for m in re.finditer(r"(?is)(.{0,800}kics.{0,800})", txt):
        chunk=m.group(1)
        if "timeout" in chunk or "run_kics" in chunk:
            # find ${VAR:-1800} or ${VAR:-...}
            for v in re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)[:-]", chunk):
                cands.add(v)
            # also VAR=1800 style
            for v in re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*1800\b", chunk):
                cands.add(v)

# prioritize likely names
prio=[]
for name in sorted(cands):
    u=name.upper()
    if "KICS" in u and ("TIMEOUT" in u or "TOOL_TIMEOUT" in u or "VSP_TIMEOUT" in u):
        prio.append(name)
for name in sorted(cands):
    if name not in prio and ("TIMEOUT" in name.upper()):
        prio.append(name)

print(" ".join(prio[:20]))
PY
)"

echo "[AUTO] Candidate ENV vars: ${VARS:-<none-found>}"

# Always set common ones too
export VSP_TIMEOUT_KICS_SEC="$T"
export VSP_KICS_TIMEOUT_SEC="$T"
export KICS_TIMEOUT_SEC="$T"
export VSP_TOOL_TIMEOUT_SEC_KICS="$T"
export VSP_TOOL_TIMEOUT_KICS_SEC="$T"
export VSP_TIMEOUT_SEC_KICS="$T"
export VSP_TOOL_TIMEOUT_SEC="$T"
export VSP_TIMEOUT_SEC="$T"
export VSP_TOOL_TIMEOUT_SEC_DEFAULT="$T"
export VSP_TIMEOUT_SEC_DEFAULT="$T"

# And set detected vars
for v in $VARS; do
  export "$v"="$T"
done

echo "[AUTO] Exported timeout=${T}s (detected + common). Restart 8910 so CI inherits env..."
./bin/start_8910_clean_v2.sh >/dev/null 2>&1 || true

# wait until reachable
for i in {1..40}; do
  if curl -fsS "$UI/" >/dev/null 2>&1; then
    echo "[OK] 8910 reachable at $UI"
    break
  fi
  sleep 0.5
done
curl -fsS "$UI/" >/dev/null 2>&1 || { echo "[ERR] 8910 not reachable"; exit 3; }

echo "[AUTO] Trigger run_v1..."
TMP="$(mktemp)"
HTTP="$(curl -sS -o "$TMP" -w "%{http_code}" -X POST "$UI/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d "{\"mode\":\"local\",\"profile\":\"$PROFILE\",\"target_type\":\"path\",\"target\":\"$TARGET\"}")"
echo "[AUTO] run_v1 HTTP=$HTTP"
cat "$TMP"; echo
[ "$HTTP" = "200" ] || exit 4

RID="$(python3 - <<PY
import json
d=json.load(open("$TMP","r",encoding="utf-8"))
print(d.get("request_id") or d.get("req_id") or d.get("rid") or "")
PY
)"
[ -n "$RID" ] || { echo "[ERR] no RID"; exit 5; }

STATUS="$UI/api/vsp/run_status_v1/$RID"
echo "[OK] RID=$RID"
echo "[OK] STATUS=$STATUS"

echo "[AUTO] Wait ci_run_dir..."
CI_DIR=""
for i in {1..120}; do
  J="$(curl -sS "$STATUS" || true)"
  CI_DIR="$(python3 - <<PY
import json
try:
  d=json.loads("""$J""")
  print(d.get("ci_run_dir") or "")
except Exception:
  print("")
PY
)"
  [ -n "$CI_DIR" ] && break
  sleep 1
done
[ -n "$CI_DIR" ] || { echo "[ERR] no ci_run_dir"; curl -sS "$STATUS" || true; exit 6; }
echo "[OK] CI_DIR=$CI_DIR"

echo "[AUTO] Show current timeout wrapper for KICS (ps)..."
ps -ef | grep -E "timeout .*bin/run_kics_v2\.sh|kics scan" | grep -v grep || true

echo "[AUTO] Tail runner.log around KICS..."
tail -n 80 "$CI_DIR/runner.log" 2>/dev/null | sed 's/\r/\n/g' || true

echo "[AUTO] Expect timeout wrapper now show ${T}s (NOT 1800s). If still 1800s -> we will patch runner to read one canonical var."
