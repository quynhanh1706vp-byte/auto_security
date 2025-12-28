#!/usr/bin/env bash
set -euo pipefail

SRC_CI="/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251219_092640"
SRC_UI="/home/test/Data/SECURITY_BUNDLE/out/VSP_CI_20251219_092640"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need jq; need python3; need ls; need wc; need sed

echo "== PATHS =="
echo "[CI ] $SRC_CI"
echo "[UI ] $SRC_UI"
echo

one(){
  local root="$1"
  echo "=============================="
  echo "ROOT: $root"
  echo "=============================="

  # quick sizes
  for f in \
    findings_unified.json \
    findings_unified_commercial.json \
    semgrep/semgrep.json \
    grype/grype.json \
    codeql/codeql_js.sarif \
    codeql/codeql_py.sarif \
  ; do
    if [ -f "$root/$f" ]; then
      printf "%8s  %s\n" "$(wc -c < "$root/$f")" "$f"
    else
      printf "%8s  %s\n" "-" "$f"
    fi
  done
  echo

  # counts
  if [ -f "$root/semgrep/semgrep.json" ]; then
    echo -n "semgrep.results = "
    jq -r '(.results|length) // (.runs[0].results|length) // 0' "$root/semgrep/semgrep.json" 2>/dev/null || echo 0
  else
    echo "semgrep.results = (missing)"
  fi

  if [ -f "$root/grype/grype.json" ]; then
    echo -n "grype.matches  = "
    jq -r '(.matches|length) // 0' "$root/grype/grype.json" 2>/dev/null || echo 0
  else
    echo "grype.matches  = (missing)"
  fi

  for sar in "$root"/codeql/*.sarif; do
    [ -f "$sar" ] || continue
    echo -n "codeql.sarif.results ($(basename "$sar")) = "
    jq -r '([.runs[]?.results[]?] | length) // 0' "$sar" 2>/dev/null || echo 0
  done

  if [ -f "$root/findings_unified.json" ]; then
    echo -n "unified.findings = "
    jq -r '(.findings|length) // (.items|length) // (length) // 0' "$root/findings_unified.json" 2>/dev/null || echo 0
  else
    echo "unified.findings = (missing)"
  fi

  echo
}

one "$SRC_CI"
one "$SRC_UI"

echo "== NOTE =="
echo "- Nếu tất cả counts = 0 => CSV 47 bytes là 'data thật' (header-only)."
echo "- Nếu tool counts > 0 nhưng unified = 0 => unify/paths đang lỗi => cần regen unified."
