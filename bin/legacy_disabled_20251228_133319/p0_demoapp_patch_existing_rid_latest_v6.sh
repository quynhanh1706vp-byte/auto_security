#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ridlatest_v6_${TS}"
echo "[BACKUP] ${APP}.bak_ridlatest_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_PATCH_EXISTING_RID_LATEST_V6"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

# detect app var used in decorators
appvar = "app"
m = re.search(r'^\s*(app|application)\s*=\s*Flask\s*\(', s, flags=re.M)
if m:
    appvar = m.group(1)

lines = s.splitlines(True)

def find_route_block(path: str):
    # find decorator line for the exact route
    pat = re.compile(r'^\s*@\s*' + re.escape(appvar) + r'\.route\(\s*[\'"]' + re.escape(path) + r'[\'"]')
    for i, ln in enumerate(lines):
        if pat.search(ln):
            # skip stacked decorators until def
            j = i
            while j < len(lines) and lines[j].lstrip().startswith("@"):
                j += 1
            if j >= len(lines) or not re.match(r'^\s*def\s+\w+\s*\(', lines[j]):
                continue
            # block ends at next top-level decorator/def/class/if __main__
            k = j + 1
            while k < len(lines):
                ln2 = lines[k]
                if re.match(r'^(?:@|def |class |if __name__\s*==\s*[\'"]__main__[\'"]\s*:)', ln2):
                    break
                k += 1
            return i, k
    return None

hit = find_route_block("/api/vsp/rid_latest")
if not hit:
    print("[ERR] cannot find existing @%s.route('/api/vsp/rid_latest'...) in %s" % (appvar, p))
    print("Tip: grep -n \"rid_latest\" vsp_demo_app.py")
    sys.exit(2)

i, k = hit

tmpl = r'''
# ===================== __MARKER__ =====================
@__APPVAR__.route("/api/vsp/rid_latest", methods=["GET"])
@__APPVAR__.route("/api/vsp/latest_rid", methods=["GET"])
def vsp_rid_latest_v6():
    """Always return latest RID by proxying /api/vsp/rid_latest_gate_root (tool truth)."""
    from flask import jsonify, request
    import json
    import urllib.request

    base = (request.url_root or request.host_url or "").rstrip("/")
    url = base + "/api/vsp/rid_latest_gate_root"
    try:
        with urllib.request.urlopen(url, timeout=3.0) as r:
            raw = r.read() or b"{}"
        data = json.loads(raw.decode("utf-8", "replace"))
        if isinstance(data, dict) and data.get("rid"):
            return jsonify(data)
        sample = raw[:240].decode("utf-8", "replace")
        return jsonify({
            "ok": False, "rid": None, "gate_root": None, "degraded": True,
            "served_by": __file__, "upstream": url, "upstream_sample": sample
        })
    except Exception as e:
        return jsonify({
            "ok": False, "rid": None, "gate_root": None, "degraded": True,
            "served_by": __file__, "upstream": url, "err": str(e)
        })
# ===================== /__MARKER__ =====================

'''

replacement = tmpl.replace("__APPVAR__", appvar).replace("__MARKER__", marker)

lines2 = lines[:i] + [replacement] + lines[k:]
p.write_text("".join(lines2), encoding="utf-8")
print("[OK] patched existing /api/vsp/rid_latest handler at lines", i+1, "-", k, "appvar=", appvar)
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: rid_latest must now include rid =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 280; echo
echo "== smoke: rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 280; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
