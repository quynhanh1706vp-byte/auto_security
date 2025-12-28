#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [P42] scan paste-dính risk in bin/*.sh =="

# files to scan
mapfile -t files < <(find bin -maxdepth 1 -type f -name "*.sh" \
  ! -name "*.bak_*" ! -name "*.disabled_*" -print | sort)

echo
echo "-- (1) heredoc markers check (<<'TAG' ... TAG) --"
bad=0

for f in "${files[@]}"; do
  opens="$(grep -Eo "<<'[^']+'" "$f" | wc -l | tr -d ' ')"
  closes=0

  # Extract tags and count exact closing-tag lines
  while IFS= read -r tag; do
    t="${tag#<<\'}"; t="${t%\'}"
    c="$(grep -E "^[[:space:]]*${t}[[:space:]]*$" "$f" | wc -l | tr -d ' ')"
    closes=$((closes + c))
  done < <(grep -Eo "<<'[^']+'" "$f" | sed "s/^<<'//; s/'$//")

  if [ "${opens:-0}" -gt 0 ] && [ "${closes:-0}" -lt "${opens:-0}" ]; then
    echo "[RISK] $f  heredoc_open=$opens heredoc_close=$closes"
    bad=$((bad+1))
  fi
done

[ "$bad" -eq 0 ] && echo "[OK] no obvious unterminated heredoc markers"

echo
echo "-- (2) bash -n (syntax) --"
fail=0
tmp_err="$(mktemp /tmp/p42_err_XXXXXX.log)"
trap 'rm -f "$tmp_err" >/dev/null 2>&1 || true' EXIT

for f in "${files[@]}"; do
  if bash -n "$f" 2>"$tmp_err"; then
    echo "[OK] $f"
  else
    echo "[FAIL] $f"
    sed -n '1,120p' "$tmp_err"
    fail=$((fail+1))
  fi
done

echo
echo "== [SUMMARY] =="
echo "RISK_HEREDOC=$bad  SYNTAX_FAIL=$fail"
if [ "$fail" -eq 0 ]; then
  echo "[VERDICT] PASS"
else
  echo "[VERDICT] FAIL"
  exit 3
fi
