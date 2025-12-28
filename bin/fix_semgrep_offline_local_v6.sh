#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:?need RUN_DIR}"
SRC_DIR="${2:?need SRC_DIR}"

RULES_BASE="/home/test/Data/SECURITY_BUNDLE/rules/semgrep"
RULES_LOCAL="/home/test/Data/SECURITY_BUNDLE/rules/semgrep_offline_local_v1"

OUT="$RUN_DIR/semgrep/semgrep.json"
ERR="$RUN_DIR/semgrep/semgrep.json.err"

mkdir -p "$RUN_DIR/semgrep" "$RULES_LOCAL"

echo "== semgrep version =="
semgrep --version || true
echo

quarantine_dir() {
  local dir="$1"
  local ts="$2"
  local bad_dir="$dir/_disabled_bad_$ts"
  mkdir -p "$bad_dir"

  echo "== quarantine invalid rules in: $dir =="
  while IFS= read -r -d '' f; do
    # skip backups + already-disabled dirs
    [[ "$f" == *".bak_"* ]] && continue
    [[ "$f" == *"/_disabled_bad_"* ]] && continue
    if ! semgrep --validate --metrics=off --disable-version-check --config "$f" >/dev/null 2>&1; then
      echo "[BAD] $f -> $bad_dir/"
      mv -f "$f" "$bad_dir/"
    fi
  done < <(find "$dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

  echo "[OK] quarantined into $bad_dir"
  echo
}

TS="$(date +%Y%m%d_%H%M%S)"
# Quarantine BOTH base + local (base thường dính rule không tương thích version semgrep)
[ -d "$RULES_BASE" ] && quarantine_dir "$RULES_BASE" "$TS" || true
[ -d "$RULES_LOCAL" ] && quarantine_dir "$RULES_LOCAL" "$TS" || true

# Create a "compatible old-semgrep" 5-rules pack to boost findings
F_BOOST="$RULES_LOCAL/semgrep_boost_5rules_compat_v1.yml"
cat > "$F_BOOST" <<'YML'
rules:
  - id: vsp.boost.dom_xss_sinks
    message: 'DOM XSS sink: innerHTML/outerHTML/insertAdjacentHTML/document.write. Sanitize/encode before injecting HTML.'
    severity: HIGH
    languages: [javascript, typescript]
    pattern-regex: '(?i)(\binnerHTML\b\s*=|\bouterHTML\b\s*=|insertAdjacentHTML\s*\(|document\.write\s*\()'
    metadata: {category: vsp.domxss, confidence: medium}

  - id: vsp.boost.dangerous_eval
    message: 'Dangerous use of eval (code injection risk).'
    severity: HIGH
    languages: [javascript, typescript, python]
    pattern-regex: '(?i)\beval\s*\('
    metadata: {category: vsp.injection, confidence: medium}

  - id: vsp.boost.os_command_exec
    message: 'Possible OS command execution (review input validation).'
    severity: HIGH
    languages: [python, javascript, typescript]
    pattern-regex: '(?i)(\bos\.system\s*\(|\bsubprocess\.(Popen|run|call)\s*\(|child_process\.(exec|execSync|spawn|spawnSync)\s*\()'
    metadata: {category: vsp.rce, confidence: low}

  - id: vsp.boost.weak_hash
    message: 'Weak hash usage (MD5/SHA1). Prefer SHA-256+.'
    severity: MEDIUM
    languages: [python, javascript, typescript]
    pattern-regex: '(?i)(\bmd5\b|\bsha1\b|createHash\s*\(\s*["'\''](md5|sha1)["'\'']\s*\))'
    metadata: {category: vsp.crypto, confidence: high}

  - id: vsp.boost.tls_insecure
    message: 'Insecure TLS setting (rejectUnauthorized=false / NODE_TLS_REJECT_UNAUTHORIZED=0).'
    severity: MEDIUM
    languages: [javascript, typescript]
    pattern-regex: '(?i)(rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*0)'
    metadata: {category: vsp.tls, confidence: high}
YML

echo "== validate boost pack =="
semgrep --validate --metrics=off --disable-version-check --config "$F_BOOST"
echo

# Build config args safely (base dir + every local yml/yaml excluding backups/disabled)
CFG_ARGS=()
if [ -d "$RULES_BASE" ]; then
  CFG_ARGS+=( --config "$RULES_BASE" )
fi
for f in "$RULES_LOCAL"/*.yml "$RULES_LOCAL"/*.yaml; do
  [ -f "$f" ] || continue
  [[ "$f" == *".bak_"* ]] && continue
  [[ "$f" == *"/_disabled_bad_"* ]] && continue
  CFG_ARGS+=( --config "$f" )
done

echo "== RUN semgrep (base + local clean + boost) =="
: > "$ERR" || true
timeout 900 semgrep --metrics=off --disable-version-check \
  --exclude _codeql_db --exclude out --exclude out_ci --exclude node_modules --exclude dist --exclude build --exclude '*.min.js' \
  "${CFG_ARGS[@]}" \
  --json -o "$OUT" "$SRC_DIR" \
  2>"$ERR" || true

echo "== SEMGREP summary =="
jq '{results:((.results//[])|length), errors:((.errors//[])|length)}' "$OUT" || true
echo

echo "== SEMGREP errors (from semgrep.json) =="
jq -r '.errors[]? | {type:(.type//null), path:(.path//.location.path//null), rule_id:(.rule_id//null), message:(.message//.long_msg//null)}' "$OUT" 2>/dev/null | head -n 80 || true
echo

echo "== SEMGREP stderr tail =="
tail -n 120 "$ERR" 2>/dev/null || true
echo

echo "== SEMGREP sample findings =="
jq -r '.results[0:20][] | {check_id, path:(.path//.extra.path), line:(.start.line//null), severity:(.extra.severity//null), message:(.extra.message//null)}' \
  "$OUT" 2>/dev/null || true
echo

echo "[DONE] out=$OUT err=$ERR"
