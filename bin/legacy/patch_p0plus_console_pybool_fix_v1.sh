#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3

# (A) Patch templates: add a safe shim + sanitize common Py literals in inline JS
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "${TPL}.bak_pybool_${TS}"
echo "[BACKUP] ${TPL}.bak_pybool_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK="VSP_PYBOOL_SHIM_P0PLUS_V1"
shim = """
<!-- VSP_PYBOOL_SHIM_P0PLUS_V1 -->
<script>
  // Back-compat guard: prevent "True is not defined" if a Python literal leaks into JS.
  // Real fix is below (sanitize), this is just a last line of defense.
  window.True = true; window.False = false; window.None = null;
</script>
""".strip() + "\n"

if MARK not in s:
    # inject early in <head> for best chance to run before other JS
    if "<head" in s:
        s = re.sub(r"(<head[^>]*>\s*)", r"\1\n"+shim, s, count=1, flags=re.I)
    else:
        s = shim + s

# sanitize obvious leaked tokens in inline scripts/templates (conservative patterns)
# (we avoid blind global replace to not mutate user-facing strings too much)
repls = [
    (r"(:\s*)True(\b)",  r"\1true\2"),
    (r"(:\s*)False(\b)", r"\1false\2"),
    (r"(:\s*)None(\b)",  r"\1null\2"),
    (r"(=\s*)True(\b)",  r"\1true\2"),
    (r"(=\s*)False(\b)", r"\1false\2"),
    (r"(=\s*)None(\b)",  r"\1null\2"),
    (r"(\[\s*)True(\b)", r"\1true\2"),
    (r"(\[\s*)False(\b)",r"\1false\2"),
    (r"(\[\s*)None(\b)", r"\1null\2"),
    (r"(,\s*)True(\b)",  r"\1true\2"),
    (r"(,\s*)False(\b)", r"\1false\2"),
    (r"(,\s*)None(\b)",  r"\1null\2"),
    (r"(\(\s*)True(\b)", r"\1true\2"),
    (r"(\(\s*)False(\b)",r"\1false\2"),
    (r"(\(\s*)None(\b)", r"\1null\2"),
]
for pat, rep in repls:
    s = re.sub(pat, rep, s)

tpl.write_text(s, encoding="utf-8")
print("[OK] template shim + sanitize done")
PY

# (B) Patch JS bundles similarly (conservative patterns)
JS_DIR="static/js"
[ -d "$JS_DIR" ] || { echo "[ERR] missing dir: $JS_DIR"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path("static/js")
files = sorted(root.rglob("*.js"))
if not files:
    print("[WARN] no js files under static/js"); sys.exit(0)

repls = [
    (r"(:\s*)True(\b)",  r"\1true\2"),
    (r"(:\s*)False(\b)", r"\1false\2"),
    (r"(:\s*)None(\b)",  r"\1null\2"),
    (r"(=\s*)True(\b)",  r"\1true\2"),
    (r"(=\s*)False(\b)", r"\1false\2"),
    (r"(=\s*)None(\b)",  r"\1null\2"),
    (r"(\[\s*)True(\b)", r"\1true\2"),
    (r"(\[\s*)False(\b)",r"\1false\2"),
    (r"(\[\s*)None(\b)", r"\1null\2"),
    (r"(,\s*)True(\b)",  r"\1true\2"),
    (r"(,\s*)False(\b)", r"\1false\2"),
    (r"(,\s*)None(\b)",  r"\1null\2"),
    (r"(\(\s*)True(\b)", r"\1true\2"),
    (r"(\(\s*)False(\b)",r"\1false\2"),
    (r"(\(\s*)None(\b)", r"\1null\2"),
]

changed=0
for p in files:
    s = p.read_text(encoding="utf-8", errors="replace")
    s2 = s
    for pat, rep in repls:
        s2 = re.sub(pat, rep, s2)
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        changed += 1
print(f"[OK] sanitized js files changed={changed}/{len(files)}")
PY

# (C) Syntax checks (best-effort)
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check runs js" || echo "[WARN] node check failed (still try UI)"
fi

echo "[NEXT] restart UI: sudo systemctl restart vsp-ui-8910.service (or your restart script)"
