#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="$(mktemp -d /tmp/vsp_ro_chk_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export VSP_TMP_DIR="$tmp"

echo "== GET /api/ui/rule_overrides_v2 =="
curl -sS -D "$tmp/hdr_get.txt" -o "$tmp/body_get.bin" "$BASE/api/ui/rule_overrides_v2" || true

echo "--- status line ---"
head -n 1 "$tmp/hdr_get.txt" || true

echo "--- headers (ct/location/len/enc) ---"
grep -Ei '^(content-type:|location:|content-length:|content-encoding:)' "$tmp/hdr_get.txt" || true

echo "--- body head (first 220 bytes preview) ---"
python3 - <<'PY'
import os
from pathlib import Path
b = Path(os.environ["VSP_TMP_DIR"]) / "body_get.bin"
data = b.read_bytes()
head = data[:220]
print(head.decode("utf-8","replace"))
print("BYTES_LEN=", len(data))
PY

echo "--- json parse? ---"
python3 - <<'PY'
import os, json
from pathlib import Path
b = Path(os.environ["VSP_TMP_DIR"]) / "body_get.bin"
raw = b.read_text(encoding="utf-8", errors="replace")
try:
    j = json.loads(raw)
    print("JSON_OK:", "ok=", j.get("ok"), "schema=", j.get("schema"),
          "rules_len=", len(j.get("rules") or []), "ro_mode=", j.get("ro_mode"))
except Exception as e:
    print("JSON_FAIL:", repr(e))
PY

echo
echo "== POST /api/ui/rule_overrides_v2 =="
cat >"$tmp/ro_rules.json" <<'JSON'
{"schema":"rules_v1","rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON

code="$(curl -sS -o "$tmp/body_post.json" -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' --data-binary @"$tmp/ro_rules.json" \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "POST http_code=$code"
head -c 260 "$tmp/body_post.json"; echo

echo "--- audit tail ---"
tail -n 5 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log 2>/dev/null || true
