#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_indent_bundleonly_${TS}"
echo "[BACKUP] $APP.bak_indent_bundleonly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# (0) remove any previous bundle-only blocks (all versions) to avoid indentation garbage
s = re.sub(r'(?s)\n# --- VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_.*?\n(?=(\n# ---|\n@app\.|\ndef |\nclass |\nif __name__|$))', "\n", s)

# (1) remove any stray "script_re = re.compile(...)" lines that previously broke parsing
s = re.sub(r'(?m)^\s*script_re\s*=\s*re\.compile\(.*\)\s*$', '', s)

# (2) repair empty function bodies: insert "pass" if a def has no indented block
lines = s.splitlines(True)

def is_def_line(ln: str) -> bool:
    return re.match(r'^\s*(async\s+def|def)\s+[A-Za-z_]\w*\s*\(.*\)\s*:\s*(#.*)?$', ln) is not None

def is_blank_or_comment(ln: str) -> bool:
    t = ln.strip()
    return (t == "" or t.startswith("#"))

def indent_of(ln: str) -> int:
    return len(ln) - len(ln.lstrip(" \t"))

i = 0
inserted = 0
while i < len(lines):
    ln = lines[i]
    if is_def_line(ln):
        base = indent_of(ln)
        # find next meaningful line
        j = i + 1
        while j < len(lines) and is_blank_or_comment(lines[j]):
            j += 1
        if j >= len(lines) or indent_of(lines[j]) <= base:
            # no body -> insert pass
            pad = (" " * (base + 4))
            lines.insert(i + 1, pad + "pass\n")
            inserted += 1
            i += 2
            continue
    i += 1

s = "".join(lines)

# (3) inject clean bundle-only after_request (no dangerous quoting)
MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V5CLEAN"
if MARK not in s:
    code = f"""
# --- {MARK}: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v5clean(resp):
    try:
        from flask import request
        import re as _re

        path = getattr(request, "path", "") or ""
        if not (path == "/vsp4" or path.startswith("/vsp4/")):
            return resp

        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype:
            return resp
        if getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        m = _re.search(r'/static/js/vsp_[^"\\']+\\?v=(\\d+)', body, _re.I)
        asset_v = m.group(1) if m else "1"

        # drop ALL vsp_*.js script tags (we will re-insert bundle v2 once)
        pat = _re.compile(r\"\"\"(?is)<script\\b[^>]*\\bsrc\\s*=\\s*(['"])([^'"]*?/static/js/vsp_[^'"]+)\\1[^>]*>\\s*</script\\s*>\"\"\")
        body2 = pat.sub("\\n", body)

        bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{asset_v}}"></script>'
        if _re.search(r"(?is)</body\\s*>", body2):
            body2 = _re.sub(r"(?is)</body\\s*>", "\\n"+bundle_tag+"\\n</body>", body2, count=1)
        else:
            body2 += "\\n" + bundle_tag + "\\n"

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
    except Exception:
        pass
    return resp
"""
    m2 = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    ins = m2.start() if m2 else len(s)
    s = s[:ins] + "\n" + code + "\n" + s[ins:]

p.write_text(s, encoding="utf-8")
print("[OK] repaired empty def bodies inserted_pass=", inserted)
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
