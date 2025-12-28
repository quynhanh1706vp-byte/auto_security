#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need curl

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_csuite_wsgi_v5_${TS}"
echo "[BACKUP] ${W}.bak_csuite_wsgi_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
lines=s.splitlines(True)
N=len(lines)

# Only touch the tail to avoid breaking core Flask decorators earlier in file
tail = 4000
start = max(0, N-tail)

pat = re.compile(r'^\s*@(?P<obj>app|application)\.(before_request|after_request|route)\b')
disabled = 0
for i in range(start, N):
    if pat.match(lines[i]):
        # comment out only tail decorators (these are the ones that crash when app==middleware)
        lines[i] = re.sub(r'^(\s*)@', r'\1# P0_DISABLED_TAIL_DECORATOR @', lines[i])
        disabled += 1

marker = "VSP_P0_CSUITE_WSGI_REDIRECT_V5"
whole = "".join(lines)
if marker not in whole:
    lines.append("\n")
    lines.append(f"# {marker}\n")
    lines.append("def __vsp_p0_csuite_redirect_wsgi(_wsgi_app):\n")
    lines.append("  \"\"\"WSGI redirect for /c/* -> canonical tabs. No Flask decorators.\"\"\"\n")
    lines.append("  mapping = {\n")
    lines.append("    '/c': '/vsp5',\n")
    lines.append("    '/c/': '/vsp5',\n")
    lines.append("    '/c/dashboard': '/vsp5',\n")
    lines.append("    '/c/runs': '/runs',\n")
    lines.append("    '/c/data_source': '/data_source',\n")
    lines.append("    '/c/settings': '/settings',\n")
    lines.append("    '/c/rule_overrides': '/rule_overrides',\n")
    lines.append("  }\n")
    lines.append("  def _app(environ, start_response):\n")
    lines.append("    try:\n")
    lines.append("      path = (environ.get('PATH_INFO') or '')\n")
    lines.append("      if path.startswith('/c'):\n")
    lines.append("        tgt = mapping.get(path)\n")
    lines.append("        if tgt:\n")
    lines.append("          qs = environ.get('QUERY_STRING') or ''\n")
    lines.append("          loc = tgt + (('?' + qs) if qs else '')\n")
    lines.append("          start_response('302 Found', [\n")
    lines.append("            ('Location', loc),\n")
    lines.append("            ('Cache-Control','no-store'),\n")
    lines.append("            ('Content-Type','text/plain; charset=utf-8'),\n")
    lines.append("          ])\n")
    lines.append("          return [b'Redirecting...']\n")
    lines.append("    except Exception:\n")
    lines.append("      pass\n")
    lines.append("    return _wsgi_app(environ, start_response)\n")
    lines.append("  return _app\n\n")
    lines.append("try:\n")
    lines.append("  _wsgi = globals().get('application')\n")
    lines.append("  if callable(_wsgi):\n")
    lines.append("    application = __vsp_p0_csuite_redirect_wsgi(_wsgi)\n")
    lines.append("except Exception:\n")
    lines.append("  pass\n")

p.write_text("".join(lines), encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched tail decorators disabled=", disabled, "lines=", N)
PY

echo "== [Restart best-effort, NO password prompt] =="
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC"
else
  echo "[WARN] sudo needs password (skipping restart to avoid CLI prompt)."
  echo "Run manually:"
  echo "  sudo systemctl daemon-reload"
  echo "  sudo systemctl restart $SVC"
fi

echo "== [Wait port] =="
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5?rid=$RID" >/dev/null 2>&1; then
    echo "[OK] UI up: $BASE/vsp5?rid=$RID"
    break
  fi
  sleep 0.2
done

echo "== [Smoke /c/* redirect] =="
for pth in /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" -L --connect-timeout 1 --max-time 6 "$BASE$pth?rid=$RID" || true)"
  echo "$pth => $code"
done

echo "[DONE] v5 csuite redirect via WSGI (no Flask decorators at tail)."
