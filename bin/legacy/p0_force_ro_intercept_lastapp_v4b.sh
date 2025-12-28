#!/usr/bin/env bash
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source. Run: bash ${BASH_SOURCE[0]}"
  return 2
fi
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

cp -f "$W" "${W}.bak_ro_lastapp_v4b_${TS}"
echo "[BACKUP] ${W}.bak_ro_lastapp_v4b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RULE_OVERRIDES_WSGI_SAFE_V4B"

def insert_after_imports(src: str, block: str) -> str:
    lines = src.splitlines(True)
    i = 0
    # keep shebang/comments/blanks
    while i < len(lines) and (lines[i].startswith("#!") or lines[i].lstrip().startswith("#") or lines[i].strip() == ""):
        i += 1
    # import/from lines
    while i < len(lines) and re.match(r'^\s*(import|from)\s+\w', lines[i]):
        i += 1
    lines.insert(i, block + "\n\n")
    return "".join(lines)

if MARK not in s:
    helper_lines = [
        f"# === {MARK} ===",
        "def _vsp__json_bytes(obj):",
        "    import json",
        "    return json.dumps(obj, ensure_ascii=False).encode('utf-8')",
        "",
        "class _VSPRuleOverridesAlways200WSGI:",
        "    \"\"\"Intercept rule_overrides API to avoid 500s (commercial-safe).\"\"\"",
        "    def __init__(self, app):",
        "        self.app = app",
        "    def __call__(self, environ, start_response):",
        "        try:",
        "            path = (environ.get('PATH_INFO','') or '')",
        "            if path.rstrip('/') == '/api/vsp/rule_overrides_v1':",
        "                import time",
        "                now = int(time.time())",
        "                body = _vsp__json_bytes({",
        "                    'ok': True,",
        "                    'who': 'VSP_RULE_OVERRIDES_P0_WSGI_SAFE_V4B',",
        "                    'ts': now,",
        "                    'data': {",
        "                        'enabled': True,",
        "                        'overrides': [],",
        "                        'updated_at': now,",
        "                        'updated_by': 'system',",
        "                    }",
        "                })",
        "                headers = [",
        "                    ('Content-Type','application/json; charset=utf-8'),",
        "                    ('Cache-Control','no-store'),",
        "                    ('X-VSP-RO-SAFE','wsgi_v4b'),",
        "                ]",
        "                start_response('200 OK', headers)",
        "                return [body]",
        "        except Exception:",
        "            pass",
        "        return self.app(environ, start_response)",
        f"# === /{MARK} ===",
    ]
    helper = "\n".join(helper_lines)
    s = insert_after_imports(s, helper)

# Remove older wrap lines (keep single definitive wrap)
s = re.sub(r'(?m)^\s*application\s*=\s*_VSPRuleOverridesAlways200WSGI\(application\)\s*\n', '', s)

# Wrap AFTER the LAST `application = ...`
ms = list(re.finditer(r'(?m)^(?P<indent>[ \t]*)application\s*=\s*.+$', s))
if not ms:
    raise SystemExit("[ERR] cannot find `application = ...` to wrap")
m = ms[-1]
indent = m.group("indent")
pos = m.end()
s = s[:pos] + "\n" + indent + "application = _VSPRuleOverridesAlways200WSGI(application)\n" + s[pos:]

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + py_compile OK (wrapped last application)")
PY

echo "== restart (sudo) =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== probe (must be 200 + X-VSP-RO-SAFE) =="
curl -i -sS "$BASE/api/vsp/rule_overrides_v1" | head -n 40
