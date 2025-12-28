#!/usr/bin/env bash
set -euo pipefail

# avoid polluted git env (your log shows git tries chdir to E:/)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES || true

HERE="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$HERE"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need bash; need date; need python3; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/freeze_${TS}"
mkdir -p "$OUT"
echo "[INFO] freeze dir: $OUT"

# find git repo root by walking up
find_git_root(){
  local d="$PWD"
  while true; do
    if command -v git >/dev/null 2>&1; then
      if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$d" rev-parse --show-toplevel
        return 0
      fi
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  return 1
}

REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(find_git_root || true)"
fi

# snapshot markers
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
grep -n "VSP_P[01]_" "$F" > "$OUT/gateway_markers_p0p1.txt" || true
grep -n "VSP_" "$F" > "$OUT/gateway_markers_all.txt" || true

# run commercial selfcheck if exists
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
  echo "[WARN] selfcheck missing/not executable: $SELF (skip)" | tee "$OUT/selfcheck.warn"
fi

if [ -z "${REPO_ROOT}" ]; then
  echo "[WARN] no git repo detected above $HERE => freeze-only (no commit)" | tee "$OUT/git.warn"
  # produce a minimal patch bundle of key files (for manual diff/review)
  tar -czf "$OUT/ui_freeze_keyfiles.tgz" \
    wsgi_vsp_ui_gateway.py \
    bin/*.sh \
    templates 2>/dev/null || true
  echo "[OK] wrote: $OUT/ui_freeze_keyfiles.tgz"
  exit 0
fi

echo "[INFO] git root: $REPO_ROOT" | tee "$OUT/git_root.txt"
need git

# capture status/diff from repo root
git -C "$REPO_ROOT" status -sb | tee "$OUT/git_status.txt"
git -C "$REPO_ROOT" diff --stat | tee "$OUT/git_diff_stat.txt"
git -C "$REPO_ROOT" diff > "$OUT/git_diff.patch" || true

# stage changes but don't accidentally stage out_ci
git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" reset -q -- out_ci 2>/dev/null || true

MSG="P0/P1: stabilize 8910 probe; runs contract WSGI MW; pin runs root; sha256 degrade-graceful"
if git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "[INFO] nothing staged — no commit created."
else
  git -C "$REPO_ROOT" commit -m "$MSG" | tee "$OUT/git_commit.txt"
  git -C "$REPO_ROOT" rev-parse --short HEAD | tee "$OUT/git_head_after.txt"
  echo "[OK] committed."
fi

echo "[OK] freeze complete: $OUT"
