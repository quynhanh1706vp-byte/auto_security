#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="$(mktemp -d /tmp/vsp_ro_chk_XXXXXX)"; trap 'rm -rf "$tmp"' EXIT

echo "== GET /api/ui/rule_overrides_v2 =="
curl -sS -D "$tmp/hdr_get.txt" -o "$tmp/body_get.bin" "$BASE/api/ui/rule_overrides_v2" || true
echo "--- status line ---"
head -n 1 "$tmp/hdr_get.txt" || true
echo "--- headers (ct/location/len/enc) ---"
grep -Ei '^(content-type:|location:|content-length:|content-encoding:)' "$tmp/hdr_get.txt" || true
echo "--- body head (first 220 bytes, escaped) ---"
python3 - <<'PY'
from pathlib import Path
b=Path("'$tmp'")/"body_get.bin"
data=b.read_bytes()
head=data[:220]
# show printable-ish preview
print(head.decode("utf-8","replace"))
print("BYTES_LEN=",len(data))
PY
echo "--- json parse? ---"
python3 - <<'PY'
import json,sys
from pathlib import Path
b=Path("'$tmp'")/"body_get.bin"
data=b.read_bytes()
try:
    j=json.loads(data.decode("utf-8","strict"))
    print("JSON_OK: ok=",j.get("ok"),"schema=",j.get("schema"),"rules_len=",len(j.get("rules") or []),"ro_mode=",j.get("ro_mode"))
except Exception as e:
    print("JSON_FAIL:",repr(e))
PY

echo
echo "== POST /api/ui/rule_overrides_v2 =="
cat >"$tmp/ro_rules.json" <<'JSON'
{"schema":"rules_v1","rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -sS -o "$tmp/body_post.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @"$tmp/ro_rules.json" "$BASE/api/ui/rule_overrides_v2" || true)"
echo "POST http_code=$code"
head -c 260 "$tmp/body_post.json"; echo
echo "--- json parse post ---"
python3 - <<'PY'
import json
from pathlib import Path
p=Path("'$tmp'")/"body_post.json"
try:
    j=json.loads(p.read_text(encoding="utf-8", errors="replace"))
    print("POST_JSON_OK: ok=",j.get("ok"),"saved=",j.get("saved"),"schema=",j.get("schema"),"rules_len=",len(j.get("rules") or []))
except Exception as e:
    print("POST_JSON_FAIL:",repr(e))
PY

echo
echo "== audit tail =="
tail -n 5 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log 2>/dev/null || true
