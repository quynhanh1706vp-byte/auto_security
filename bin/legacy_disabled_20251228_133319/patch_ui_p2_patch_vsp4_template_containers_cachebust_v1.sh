#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PYFILE="vsp_demo_app.py"
[ -f "$PYFILE" ] || { echo "[ERR] missing $PYFILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
CACHEV="${TS}"

echo "[INFO] TS=$TS cachev=$CACHEV"

python3 - <<'PY'
from pathlib import Path
import re, sys

pyf = Path("vsp_demo_app.py")
t = pyf.read_text(encoding="utf-8", errors="ignore")

# find route /vsp4 then first render_template(...) after it
m = re.search(r'@app\.route\(\s*["\']/vsp4["\']\s*\)[\s\S]{0,4000}?render_template\(\s*["\']([^"\']+)["\']', t)
if not m:
    print("[ERR] cannot detect render_template() for /vsp4 in vsp_demo_app.py")
    sys.exit(2)

tpl_name = m.group(1)
print("[OK] detected template:", tpl_name)

# locate actual template file (search common dirs)
cands = []
for base in [Path("templates"), Path("my_flask_app/templates"), Path("my_flask_app/my_flask_app/templates")]:
    p = base / tpl_name
    if p.exists():
        cands.append(p)

# also fallback: search by filename
if not cands:
    for p in Path(".").rglob(tpl_name):
        if p.is_file() and any(x in str(p) for x in ["/templates/","\\templates\\"]):
            cands.append(p)

if not cands:
    print("[ERR] template not found on disk:", tpl_name)
    sys.exit(3)

tpl_path = cands[0]
print("[OK] template path:", tpl_path)

# patch template
html = tpl_path.read_text(encoding="utf-8", errors="ignore")
orig = html

TAG = "<!-- VSP_P2_TPL_CONTAINERS_CACHEBUST_V1 -->"
if TAG not in html:
    # 1) add stable containers (best-effort, non-destructive)
    inject = f"""
{TAG}
<script>
  // Ensure stable containers for JS/router (commercial hardening)
  (function(){{
    function ensure(id, parentSel, attrs){{
      if (document.getElementById(id)) return;
      var host = document.querySelector(parentSel) || document.body;
      var d = document.createElement("div");
      d.id = id;
      if (attrs) {{
        for (var k in attrs) d.setAttribute(k, attrs[k]);
      }}
      host.appendChild(d);
    }}

    // dashboard main container
    document.addEventListener("DOMContentLoaded", function(){{
      ensure("vsp-dashboard-main", "body", {{"data-vsp-main":"dashboard"}});
      // datasource content container
      ensure("vsp4-datasource", "body", {{"data-tab-content":"datasource"}});
    }});
  }})();
</script>
"""
    # put before </body> if possible
    if "</body>" in html:
        html = html.replace("</body>", inject + "\n</body>", 1)
    else:
        html = html + "\n" + inject + "\n"

# 2) cache-bust static js/css (append ?v=CACHEV if no query present)
# We'll add a placeholder token __VSP_CACHEV__ then replace from shell via env later.
html = re.sub(r'(src="[^"]+\.(?:js)")(?!\?)', r'\1?v=__VSP_CACHEV__', html)
html = re.sub(r"(src='[^']+\.(?:js)')(?!\?)", r"\1?v=__VSP_CACHEV__", html)
html = re.sub(r'(href="[^"]+\.(?:css)")(?!\?)', r'\1?v=__VSP_CACHEV__', html)
html = re.sub(r"(href='[^']+\.(?:css)')(?!\?)", r"\1?v=__VSP_CACHEV__", html)

# avoid double-appending when already has ?v=
html = html.replace("?v=__VSP_CACHEV__?v=__VSP_CACHEV__", "?v=__VSP_CACHEV__")

tpl_path.write_text(html, encoding="utf-8")
print("[OK] patched template (containers + cachebust placeholders)")
PY

# Replace placeholder with current TS (cache-bust)
python3 - <<PY
from pathlib import Path
import re
CACHEV="${CACHEV}"
# find which template was patched by checking marker
targets=[]
for p in [Path("templates"), Path("my_flask_app/templates"), Path("my_flask_app/my_flask_app/templates")]:
    if p.exists():
        for f in p.rglob("*.html"):
            txt=f.read_text(encoding="utf-8", errors="ignore")
            if "__VSP_CACHEV__" in txt:
                targets.append(f)
for f in targets:
    txt=f.read_text(encoding="utf-8", errors="ignore").replace("__VSP_CACHEV__", CACHEV)
    f.write_text(txt, encoding="utf-8")
    print("[OK] cachev applied:", f)
PY

echo "[DONE] Template containers + cache-busting applied."
echo "Next: restart 8910 if needed, then hard refresh Ctrl+Shift+R and test:"
echo "  http://127.0.0.1:8910/vsp4"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
