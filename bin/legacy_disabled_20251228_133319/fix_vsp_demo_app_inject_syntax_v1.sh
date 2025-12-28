#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
B="$(ls -1t vsp_demo_app.py.bak_vsp4_inject_* 2>/dev/null | head -n1 || true)"
[ -n "$B" ] || { echo "[ERR] no backup vsp_demo_app.py.bak_vsp4_inject_* found"; exit 2; }

echo "== restore broken file from backup =="
cp -f "$B" "$F"
echo "[RESTORE] $F <= $B"

python3 -m py_compile "$F" && echo "[OK] py_compile OK after restore"

echo "== patch VSP4 inject (safe lines, no multiline string hazards) =="
python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_VSP4_INJECT_AFTER_REQUEST_V3" in s:
    print("[OK] already patched V3")
    raise SystemExit(0)

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate Flask() var (app = Flask(...))")
appvar = m.group(1)
stamp = str(int(time.time()))

lines = []
lines.append("")
lines.append("# ================================")
lines.append("# VSP_VSP4_INJECT_AFTER_REQUEST_V3")
lines.append("# ================================")
lines.append("from flask import request, redirect")
lines.append("import re as _vsp_re")
lines.append("")
lines.append("def _vsp__inject_tags_v3(html: str) -> str:")
lines.append("  try:")
lines.append("    # hash normalizer into <head>")
lines.append("    if 'vsp_hash_normalize_v1.js' not in html:")
lines.append(f"      tag = '<script src=\"/static/js/vsp_hash_normalize_v1.js?v={stamp}\"></script>'")
lines.append("      mm = _vsp_re.search(r'<head[^>]*>', html, flags=_vsp_re.I)")
lines.append("      if mm:")
lines.append("        i = mm.end()")
lines.append("        html = html[:i] + '\\n  ' + tag + '\\n' + html[i:]")
lines.append("      else:")
lines.append("        html = tag + '\\n' + html")
lines.append("")
lines.append("    # loader+features before </body>")
lines.append("    if 'vsp_ui_loader_route_v1.js' not in html:")
lines.append(f"      ins = '\\n  <script src=\"/static/js/vsp_ui_features_v1.js?v={stamp}\"></script>\\n' \\")
lines.append(f"            '  <script src=\"/static/js/vsp_ui_loader_route_v1.js?v={stamp}\"></script>\\n'")
lines.append("      if '</body>' in html:")
lines.append("        html = html.replace('</body>', ins + '</body>')")
lines.append("      else:")
lines.append("        html = html + ins")
lines.append("  except Exception:")
lines.append("    pass")
lines.append("  return html")
lines.append("")
lines.append(f"@{appvar}.after_request")
lines.append("def __vsp_after_request_inject_v3(resp):")
lines.append("  try:")
lines.append("    path = (request.path or '').rstrip('/')")
lines.append("    if path == '/vsp4':")
lines.append("      ct = (resp.headers.get('Content-Type','') or '')")
lines.append("      if 'text/html' in ct:")
lines.append("        html = resp.get_data(as_text=True)")
lines.append("        html2 = _vsp__inject_tags_v3(html)")
lines.append("        if html2 != html:")
lines.append("          resp.set_data(html2)")
lines.append("  except Exception:")
lines.append("    pass")
lines.append("  return resp")
lines.append("")

# add root redirect only if missing
if re.search(r'@\s*' + re.escape(appvar) + r'\s*\.route\(\s*[\'"]/\s*[\'"]', s, flags=re.M) is None:
    lines.append(f"@{appvar}.route('/')")
    lines.append("def __vsp_root_redirect_v3():")
    lines.append("  return redirect('/vsp4/#dashboard')")
    lines.append("")

p.write_text(s + "\n" + "\n".join(lines), encoding="utf-8")
print("[OK] appended V3 inject to", p, "appvar=", appvar)
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK after patch"

echo "== restart 8910 (NO restore) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_no_restore_v1.sh

echo "== verify / and /vsp4 tags =="
curl -sSI http://127.0.0.1:8910/ | head -n 8 || true
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_ui_loader_route_v1.js" || echo "[ERR] loader still missing in /vsp4"
curl -sS  http://127.0.0.1:8910/vsp4 | grep -n "vsp_hash_normalize_v1.js" || echo "[ERR] hash normalizer still missing in /vsp4"

echo "[NEXT] mở: http://127.0.0.1:8910/  (tự về /vsp4/#dashboard)"
