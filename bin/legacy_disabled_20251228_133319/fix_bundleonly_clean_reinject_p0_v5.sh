#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_bundleonly_p0_v5_${TS}"
echo "[BACKUP] $APP.bak_bundleonly_p0_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

def is_block_start(ln: str) -> bool:
    t = ln.strip()
    return (
        "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_" in t
        or "vsp_afterreq_bundle_only_vsp4_p0_" in t
        or t.startswith("@app.after_request") and ("bundle_only" in s)
    )

def is_top_level_code(ln: str) -> bool:
    if not ln.strip():
        return False
    if ln.startswith((" ", "\t")):
        return False
    t = ln.strip()
    return (
        t.startswith("@app.")
        or t.startswith("def ")
        or t.startswith("class ")
        or t.startswith("if __name__")
        or t.startswith("# --- ")
    )

# (1) Remove ALL previous bundle-only after_request blocks (any version), robustly.
out = []
i = 0
removed_blocks = 0
while i < len(lines):
    ln = lines[i]
    if is_block_start(ln):
        removed_blocks += 1
        # skip until next top-level code marker (keep it)
        i += 1
        while i < len(lines) and not is_top_level_code(lines[i]):
            i += 1
        continue
    # Also remove any stray bad 'script_re = re.compile(' line that previously broke parser
    if re.search(r'\bscript_re\s*=\s*re\.compile\(', ln):
        i += 1
        continue
    out.append(ln)
    i += 1

s2 = "".join(out)

# (2) Inject a clean bundle-only after_request (P0_V5) at top-level near end.
MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V5"
if MARK not in s2:
    code = f'''
# --- {MARK}: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v5(resp):
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

        # reuse existing ?v=... if present
        m = _re.search(r'/static/js/vsp_[^"\\']+\\?v=(\\d+)', body, _re.I)
        asset_v = m.group(1) if m else "1"

        # remove ALL vsp_*.js script tags (we will re-insert exactly one bundle tag)
        pat = _re.compile(r"""(?is)<script\\b[^>]*\\bsrc\\s*=\\s*(['"])([^'"]*?/static/js/vsp_[^'"]+)\\1[^>]*>\\s*</script\\s*>""")
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
'''
    m2 = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s2)
    ins = m2.start() if m2 else len(s2)
    s2 = s2[:ins] + "\n" + code + "\n" + s2[ins:]

p.write_text(s2, encoding="utf-8")
print("[OK] removed_blocks=", removed_blocks, "and injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
