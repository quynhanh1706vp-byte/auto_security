#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_WSGI_EXPORT_V4_BYTESLIKE_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_exportv4_${TS}"
echo "[BACKUP] ${F}.bak_exportv4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK = "VSP_P2_WSGI_EXPORT_V4_BYTESLIKE_V1"

if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

# Find def wsgi_export_v4(...)
m = re.search(r'^\s*def\s+wsgi_export_v4\s*\(.*?\)\s*:\s*$', s, flags=re.M)
if not m:
    print("[ERR] cannot find function: wsgi_export_v4")
    sys.exit(2)

start = m.start()

# Find next top-level def after this function to determine end
m2 = re.search(r'^\s*def\s+\w+\s*\(.*?\)\s*:\s*$', s[m.end():], flags=re.M)
end = m.end() + (m2.start() if m2 else 0)

replacement = textwrap.dedent(f"""
def wsgi_export_v4(payload=None, status=200, headers=None, content_type="application/json"):
    \"\"\"Commercial-safe exporter.
    Fixes: memoryview(bytes-like) crash when payload is dict/list (was causing 500).
    \"\"\"
    # ===================== {MARK} =====================
    try:
        import json
        from flask import Response
    except Exception:
        # extremely defensive fallback
        return payload

    try:
        h = dict(headers or {{}})
        ct = content_type or h.get("Content-Type") or "application/json"
        h["Content-Type"] = ct

        # Normalize body to bytes
        if payload is None:
            body_b = b""
        elif isinstance(payload, (bytes, bytearray, memoryview)):
            body_b = bytes(payload)
        elif isinstance(payload, str):
            body_b = payload.encode("utf-8", errors="replace")
        else:
            # dict/list/number/etc -> JSON
            body_b = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        return Response(body_b, status=int(status), headers=h, mimetype=ct.split(";")[0])
    except Exception as e:
        # last resort JSON
        try:
            body_b = (str(e)).encode("utf-8", errors="replace")
        except Exception:
            body_b = b"export_error"
        return Response(body_b, status=500, mimetype="text/plain")
    # ===================== /{MARK} =====================
""").strip("\n")

s2 = s[:start] + replacement + "\n\n" + s[end:]
p.write_text(s2)
print("[OK] replaced wsgi_export_v4 with safe exporter:", MARK)
PY

python3 -m py_compile "$F"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== quick verify endpoints =="
curl -s -o /dev/null -w "settings_v2 => %{http_code}\n" "$BASE/api/ui/settings_v2" || true
curl -s -o /dev/null -w "rule_overrides_v2 => %{http_code}\n" "$BASE/api/ui/rule_overrides_v2" || true
