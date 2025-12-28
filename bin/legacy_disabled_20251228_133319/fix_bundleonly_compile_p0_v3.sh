#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_bundleonly_compile_${TS}"
echo "[BACKUP] $APP.bak_bundleonly_compile_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# (A) Brutal remove any broken bundle-only v1/v2 remnants that contain the bad regex line
# 1) remove whole blocks by markers if exist
for mark in [
    "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V1",
    "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V2",
]:
    i = s.find(f"# --- {mark}")
    if i != -1:
        # cut until next top-level marker/decorator/main guard
        j = len(s)
        for pat in ["\n# --- ", "\n@app.", "\nif __name__"]:
            k = s.find(pat, i+10)
            if k != -1:
                j = min(j, k)
        s = s[:i] + "\n" + s[j:]

# 2) remove any stray bad line(s) containing script_re = re.compile(...["\']...)
lines = s.splitlines(True)
out = []
removed_lines = 0
for ln in lines:
    if "script_re = re.compile" in ln and ("[\"\\']" in ln or "['\\\"]" in ln):
        removed_lines += 1
        continue
    # also remove keep_or_drop / keep_or_drop(match) lines if they look like leftover from v1
    if "def keep_or_drop" in ln and "bundle-only" in s:
        # keep it unless it's inside removed marker (already removed). do nothing here.
        pass
    out.append(ln)
s = "".join(out)

# (B) Inject clean bundle-only v3 after_request (no regex quoting traps)
MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V3"
if MARK not in s:
    code = f"""
# --- {MARK}: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v3(resp):
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

        # keep existing v=... if present
        m = _re.search(r'src="[^"]*/static/js/vsp_[^"]+\\?v=(\\d+)"', body, _re.I)
        asset_v = m.group(1) if m else "1"

        # drop any <script ... src=".../static/js/vsp_*.js..."></script>
        parts = body.split("<script")
        if len(parts) > 1:
            kept = [parts[0]]
            for chunk in parts[1:]:
                seg = "<script" + chunk
                low = seg.lower()
                # only consider external scripts
                if 'src="' not in low and "src='" not in low:
                    kept.append(seg)
                    continue
                # drop vsp scripts
                if "/static/js/vsp_" in low or "static/js/vsp_" in low:
                    end = low.find("</script>")
                    if end == -1:
                        continue
                    # drop it entirely
                    continue
                kept.append(seg)
            body2 = "".join(kept)
        else:
            body2 = body

        # insert exactly one bundle tag
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
    m = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    ins = m.start() if m else len(s)
    s = s[:ins] + "\n" + code + "\n" + s[ins:]

p.write_text(s, encoding="utf-8")
print("[OK] cleaned broken lines:", removed_lines, "and injected P0_V3")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
