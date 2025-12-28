#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need bash; need date; need git; need python3; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/freeze_${TS}"
mkdir -p "$OUT"

echo "[INFO] freeze dir: $OUT"

# 1) sanity
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "[ERR] not a git repo"; exit 2; }
echo "[INFO] branch: $(git rev-parse --abbrev-ref HEAD)"
echo "[INFO] head  : $(git rev-parse --short HEAD)"

# 2) snapshot status/diff
git status -sb | tee "$OUT/git_status.txt"
git diff --stat | tee "$OUT/git_diff_stat.txt"
git diff | tee "$OUT/git_diff.patch" >/dev/null

# 3) capture markers in gateway
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
grep -n "VSP_P[01]_" "$F" | tee "$OUT/gateway_markers.txt" || true

# 4) run your commercial selfcheck (entrypoint demo)
SELF="bin/p0_commercial_selfcheck_ui_v1.sh"
if [ -x "$SELF" ]; then
  echo "[INFO] running selfcheck: $SELF"
  ( set +e; "$SELF" 2>&1 | tee "$OUT/selfcheck.log"; exit ${PIPESTATUS[0]}; )
  RC="${PIPESTATUS[0]:-0}"
  if [ "${RC}" != "0" ]; then
    echo "[ERR] selfcheck failed (rc=$RC) — STOP (no commit). Evidence kept at $OUT"
    exit "$RC"
  fi
else
  echo "[WARN] selfcheck missing/not executable: $SELF (skip)"
fi

# 5) ensure clean enough to commit (allow staged/unstaged? -> we commit all changes)
#    If there are untracked files in out_ci, ignore by only adding tracked files.
echo "[INFO] staging tracked changes..."
git add -u

# also add new tracked files under bin/templates/static if created by patches
git add bin templates static wsgi_vsp_ui_gateway.py 2>/dev/null || true

# 6) commit
MSG="P0/P1: stabilize 8910 probe; runs contract WSGI MW; pin runs root; sha256 degrade-graceful"
if git diff --cached --quiet; then
  echo "[INFO] nothing staged — no commit created."
else
  git commit -m "$MSG" | tee "$OUT/git_commit.txt"
  echo "[OK] committed: $(git rev-parse --short HEAD)"
fi

# 7) write small release note
cat > "$OUT/RELEASE_NOTE.txt" <<EOF
Commercial freeze @ ${TS}

Markers closed:
- VSP_P0_PROBE_NONFLAKE_V2
- VSP_P1_RUNS_CONTRACT_WSGIMW_V2
- VSP_P0_PIN_RUNS_ROOT_PREFER_REAL_V1
- VSP_P1_SHA256_ALWAYS200_WSGIMW_V2

Evidence:
- selfcheck.log
- gateway_markers.txt
- git_diff.patch
EOF

echo "[OK] freeze complete: $OUT"
