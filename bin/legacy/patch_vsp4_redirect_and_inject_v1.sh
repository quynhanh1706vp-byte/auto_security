#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re

# find candidate flask app files (contain "/vsp4" and "Flask(")
cands=[]
for p in Path(".").rglob("*.py"):
    try:
        s=p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "/vsp4" in s and "Flask(" in s:
        cands.append(p)

if not cands:
    # fallback: any Flask app file
    for p in Path(".").rglob("*.py"):
        s=p.read_text(encoding="utf-8", errors="ignore")
        if "Flask(" in s:
            cands.append(p)
            break

if not cands:
    raise SystemExit("[ERR] cannot find any Flask app python file")

# patch the first best candidate
p=cands[0]
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_VSP4_INJECT_AFTER_REQUEST_V1" in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit(f"[ERR] cannot find Flask() instance var in {p}")
appvar=m.group(1)

snippet = f"""

# ================================
# VSP_VSP4_INJECT_AFTER_REQUEST_V1
# ================================
try:
  from flask import request, redirect
except Exception:
  request = None
  redirect = None

def _vsp__inject_tags(html: str) -> str:
  try:
    # 1) ensure hash normalizer in <head>
    if "vsp_hash_normalize_v1.js" not in html:
      tag = '<script src="/static/js/vsp_hash_normalize_v1.js?v=V1"></script>'
      m = re.search(r'<head[^>]*>', html, flags=re.I)
      if m:
        i = m.end()
        html = html[:i] + "\\n  " + tag + "\\n" + html[i:]
      else:
        html = tag + "\\n" + html

    # 2) ensure loader+features before </body>
    if "vsp_ui_loader_route_v1.js" not in html:
      ins = '\\n  <script src="/static/js/vsp_ui_features_v1.js?v=V1"></script>\\n' \\
            '  <script src="/static/js/vsp_ui_loader_route_v1.js?v=V1"></script>\\n'
      if "</body>" in html:
        html = html.replace("</body>", ins + "</body>")
      else:
        html += ins
  except Exception:
    pass
  return html

# redirect root "/" => /vsp4/#dashboard (avoid user opening minimal black page)
if "@{appvar}.route(\\"/\")" not in s and "@app.route(\\"/\")" not in s:
  pass

# add route only if no existing root route decorator
if re.search(r'@\\s*{appvar}\\s*\\.route\\(\\s*[\\\'\\"]\\/\\s*[\\\'\\"]', s) is None:
  s += f'''
@{appvar}.route("/")
def __vsp_root_redirect_v1():
  try:
    return redirect("/vsp4/#dashboard")
  except Exception:
    return "redirect missing", 302
'''

@{appvar}.after_request
def __vsp_after_request_inject_v1(resp):
  try:
    if request is None:
      return resp
    path = (request.path or "").rstrip("/")
    if path == "/vsp4":
      # only html
      ct = (resp.headers.get("Content-Type","") or "")
      if "text/html" in ct:
        html = resp.get_data(as_text=True)
        html2 = _vsp__inject_tags(html)
        if html2 != html:
          resp.set_data(html2)
  except Exception:
    pass
  return resp
"""

# We need re module in snippet; ensure it's imported
if "import re" not in s:
    # add near top
    s = "import re\n" + s

# append snippet safely (as raw, with correct indentation)
# We'll just append a cleaned snippet that doesn't rely on outer s variable.
clean = """
# ================================
# VSP_VSP4_INJECT_AFTER_REQUEST_V1
# ================================
from flask import request, redirect
import re as _re

def _vsp__inject_tags(html: str) -> str:
  try:
    if "vsp_hash_normalize_v1.js" not in html:
      tag = '<script src="/static/js/vsp_hash_normalize_v1.js?v=V1"></script>'
      m = _re.search(r'<head[^>]*>', html, flags=_re.I)
      if m:
        i = m.end()
        html = html[:i] + "\\n  " + tag + "\\n" + html[i:]
      else:
        html = tag + "\\n" + html

    if "vsp_ui_loader_route_v1.js" not in html:
      ins = '\\n  <script src="/static/js/vsp_ui_features_v1.js?v=V1"></script>\\n' \\
            '  <script src="/static/js/vsp_ui_loader_route_v1.js?v=V1"></script>\\n'
      if "</body>" in html:
        html = html.replace("</body>", ins + "</body>")
      else:
        html += ins
  except Exception:
    pass
  return html

@{appvar}.after_request
def __vsp_after_request_inject_v1(resp):
  try:
    path = (request.path or "").rstrip("/")
    if path == "/vsp4":
      ct = (resp.headers.get("Content-Type","") or "")
      if "text/html" in ct:
        html = resp.get_data(as_text=True)
        html2 = _vsp__inject_tags(html)
        if html2 != html:
          resp.set_data(html2)
  except Exception:
    pass
  return resp
""".replace("{appvar}", appvar)

# add root redirect only if missing
if re.search(r'@\s*' + re.escape(appvar) + r'\s*\.route\(\s*[\'"]/\s*[\'"]', s, flags=re.M) is None:
    clean += f"""

@{appvar}.route("/")
def __vsp_root_redirect_v1():
  return redirect("/vsp4/#dashboard")
"""

# backup + write
bak = p.with_suffix(p.suffix + f".bak_inject_{TS}")
bak.write_text(s, encoding="utf-8")
p.write_text(s + "\n\n" + clean + "\n", encoding="utf-8")
print("[OK] patched:", p, " backup:", bak)
PY

python3 -m py_compile $(python3 - <<'PY'
from pathlib import Path
# compile common entrypoints quickly
c=[]
for p in Path(".").rglob("*.py"):
  if p.name.endswith(".bak"): 
    continue
  c.append(str(p))
print(" ".join(c[:50]))
PY
) >/dev/null 2>&1 || true

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "== verify / and /vsp4 =="
curl -sSI http://127.0.0.1:8910/ | head -n 5 || true
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_ui_loader_route_v1.js" || echo "[ERR] loader still missing in /vsp4"
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_hash_normalize_v1.js" || echo "[ERR] hash normalizer missing in /vsp4"

echo "[NEXT] mở: http://127.0.0.1:8910/ (nó sẽ tự về /vsp4/#dashboard)"
