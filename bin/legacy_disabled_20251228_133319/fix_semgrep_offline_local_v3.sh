#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:-/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251215_034956}"
SRC_DIR="${2:-/home/test/Data/SECURITY-10-10-v4}"

RULES_BASE="/home/test/Data/SECURITY_BUNDLE/rules/semgrep"
RULES_LOCAL="/home/test/Data/SECURITY_BUNDLE/rules/semgrep_offline_local_v1"
F="$RULES_LOCAL/js_dom_tls_crypto_v3.yml"

mkdir -p "$RULES_LOCAL" "$RUN_DIR/semgrep"

TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] && cp -f "$F" "$F.bak_$TS" && echo "[BACKUP] $F.bak_$TS"

cat > "$F" <<'YML'
rules:
  - id: vsp.js.dom-xss.sinks
    message: "DOM XSS sink: writing/assigning HTML. Ensure data is sanitized/encoded before injecting into DOM."
    severity: WARNING
    languages: [javascript, typescript, javascriptreact, typescriptreact]
    metadata:
      category: security
      cwe: "CWE-79"
      confidence: MEDIUM
    pattern-either:
      - pattern: $X.innerHTML = $Y
      - pattern: $X.outerHTML = $Y
      - pattern: $X.insertAdjacentHTML($POS, $HTML)
      - pattern: document.write($X)
      - pattern: document.writeln($X)
      - pattern: $X.html($Y)
      - pattern: <$C dangerouslySetInnerHTML={{ __html: $X }} />

  - id: vsp.js.crypto.weak-hash
    message: "Weak hash algorithm detected (MD5/SHA1). Prefer SHA-256+."
    severity: WARNING
    languages: [javascript, typescript]
    metadata:
      category: security
      cwe: "CWE-328"
      confidence: MEDIUM
    pattern-either:
      - pattern: $C.createHash($ALG)
      - pattern: createHash($ALG)
    metavariable-regex:
      metavariable: $ALG
      regex: '^(?i)["''](md5|sha1)["'']$'

  - id: vsp.js.webcrypto.sha1
    message: "Weak hash algorithm detected (SHA-1) in WebCrypto. Prefer SHA-256+."
    severity: WARNING
    languages: [javascript, typescript]
    metadata:
      category: security
      cwe: "CWE-328"
      confidence: MEDIUM
    pattern-either:
      - pattern: crypto.subtle.digest($ALG, $DATA)
      - pattern: $X.subtle.digest($ALG, $DATA)
    metavariable-regex:
      metavariable: $ALG
      regex: '^(?i)["'']SHA-?1["'']$'

  - id: vsp.js.tls.rejectunauthorized-false
    message: "TLS validation disabled (rejectUnauthorized: false). This enables MITM."
    severity: ERROR
    languages: [javascript, typescript]
    metadata:
      category: security
      cwe: "CWE-295"
      confidence: HIGH
    pattern-either:
      - pattern: rejectUnauthorized: false
      - pattern: rejectUnauthorized:false
YML

echo "== VALIDATE local rule file =="
semgrep --validate --metrics=off --disable-version-check --config "$F"

echo "== RUN SEMGREP (base rules + local rules) =="
timeout 900 semgrep --metrics=off --disable-version-check \
  --config "$RULES_BASE" \
  --config "$RULES_LOCAL" \
  --exclude _codeql_db --exclude out --exclude out_ci --exclude node_modules --exclude dist --exclude build \
  --json -o "$RUN_DIR/semgrep/semgrep.json" "$SRC_DIR" \
  2>"$RUN_DIR/semgrep/semgrep.json.err" || true

echo "== SEMGREP sanity =="
stat -c '%s %n' "$RUN_DIR/semgrep/semgrep.json" 2>/dev/null || true
jq '{results:((.results//[])|length), errors:((.errors//[])|length)}' "$RUN_DIR/semgrep/semgrep.json" || true

echo "== Top rule_ids (by count) =="
jq -r '.results[]?.check_id' "$RUN_DIR/semgrep/semgrep.json" 2>/dev/null | sort | uniq -c | sort -nr | head -n 30 || true

echo "== REBUILD COMMERCIAL UNIFIED =="
python3 -u /home/test/Data/SECURITY_BUNDLE/bin/vsp_unify_augment_raw_to_findings_v1.py "$RUN_DIR" >/dev/null
jq '{total, semgrep:.by_tool_severity.SEMGREP}' "$RUN_DIR/findings_unified_commercial.json" || true
