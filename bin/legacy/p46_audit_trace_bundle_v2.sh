#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
AUDIT="bin/commercial_ui_audit_v3b.sh"
[ -f "$AUDIT" ] || { echo "[ERR] missing $AUDIT"; exit 2; }

OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
D="$OUT/audit_trace_${TS}"
mkdir -p "$D"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need bash; need curl; need grep; need head; need tail; need awk; need sed; need tar
command -v systemctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true

echo "== [AUDIT TRACE] ==" | tee "$D/trace.log"
echo "[INFO] BASE=$BASE" | tee -a "$D/trace.log"
echo "[INFO] AUDIT=$AUDIT" | tee -a "$D/trace.log"

# Snapshot service/port state (useful for evidence)
{
  echo "== systemctl status (short) =="
  systemctl is-active vsp-ui-8910.service 2>/dev/null || true
  systemctl show vsp-ui-8910.service -p ExecStart -p DropInPaths -p MainPID --no-pager 2>/dev/null || true
  echo
  echo "== ss ports =="
  ss -lntp 2>/dev/null | egrep '(:8910|gunicorn|python)' || true
} > "$D/system_state.txt" 2>&1 || true

# Pre-probe key endpoints + capture headers/body snippet
probe(){
  local p="$1"
  local name="$(echo "$p" | tr '/?' '__')"
  curl -sS -D "$D/h_${name}.txt" --connect-timeout 2 --max-time 6 "$BASE$p" \
    | head -n 60 > "$D/b_${name}.txt" || true
}
probe "/vsp5"
probe "/runs"
probe "/data_source"
probe "/settings"
probe "/rule_overrides"
probe "/api/vsp/selfcheck_p0"

# Run audit with bash -x to locate exact failing command
set +e
VSP_UI_BASE="$BASE" bash -x "$AUDIT" >"$D/audit_stdout.txt" 2>"$D/audit_stderr.txt"
rc=$?
set -e
echo "[RC] $rc" | tee -a "$D/trace.log"

# Combine + highlight likely failure lines
cat "$D/audit_stdout.txt" "$D/audit_stderr.txt" > "$D/audit_all.txt" || true

echo "== [HIGHLIGHTS] ==" | tee -a "$D/trace.log"
# common failure patterns
grep -nE '(\[FAIL\]|\[ERR\]|FAIL|ERROR|not reachable|missing|expected|rc=|HTTP/|curl: \()' "$D/audit_all.txt" \
  | head -n 120 | tee -a "$D/trace.log" || true

# If failed, show tail for context
if [ "$rc" -ne 0 ]; then
  echo "== [TAIL 120] ==" | tee -a "$D/trace.log"
  tail -n 120 "$D/audit_all.txt" | tee -a "$D/trace.log" >/dev/null || true
fi

# Pack bundle
TAR="$OUT/audit_trace_${TS}.tar.gz"
tar -czf "$TAR" -C "$OUT" "audit_trace_${TS}"
echo "[OK] bundle: $TAR"
echo "[OK] folder: $D"
exit "$rc"
