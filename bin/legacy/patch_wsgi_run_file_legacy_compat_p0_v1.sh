#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfile_compat_${TS}"
echo "[BACKUP] ${F}.bak_runfile_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUN_FILE_LEGACY_COMPAT_MW_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find where application object exists (best-effort)
m = re.search(r'^\s*application\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*$', s, flags=re.M)
insert_at = None
if m:
    insert_at = m.end()
else:
    # fallback: append near EOF
    insert_at = len(s)

block = r'''
# {MARK}
# Accept legacy /api/vsp/run_file?run_id=...&path=... by rewriting to rid/name at WSGI layer.
try:
    from urllib.parse import parse_qs, urlencode
except Exception:
    parse_qs = None
    urlencode = None

class _VspRunFileLegacyCompatMW:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO", "") or ""
            if path == "/api/vsp/run_file" and parse_qs and urlencode:
                qs = environ.get("QUERY_STRING", "") or ""
                q = parse_qs(qs, keep_blank_values=True)
                # If legacy keys exist but new keys missing => map
                if (("run_id" in q) or ("path" in q)) and (("rid" not in q) and ("name" not in q)):
                    if "run_id" in q:
                        q["rid"] = q.get("run_id")
                    if "path" in q:
                        q["name"] = q.get("path")
                    # Keep all keys (including run_id/path) to be safe
                    pairs = []
                    for k, vs in q.items():
                        for v in vs:
                            pairs.append((k, v))
                    environ["QUERY_STRING"] = urlencode(pairs, doseq=True)
        except Exception:
            pass
        return self.app(environ, start_response)

application = _VspRunFileLegacyCompatMW(application)
'''.replace("{MARK}", MARK)

out = s[:insert_at] + "\n" + block + "\n" + s[insert_at:]
p.write_text(out, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart service"
sudo systemctl restart vsp-ui-8910.service
sleep 0.6
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 12
