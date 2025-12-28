#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p2_rfallow_contract_v2_${TS}"
echo "[BACKUP] ${APP}.bak_p2_rfallow_contract_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

OPEN = "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 ====================="
CLOSE = "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 ====================="

# 1) ensure import json
if re.search(r'^\s*import\s+json\b', s, re.M) is None:
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*|import\s+\S+)(?:\s*\n(?:from\s+\S+\s+import\s+.*|import\s+\S+))*', s, re.M)
    if m:
        s = s[:m.end()] + "\nimport json\n" + s[m.end():]
    else:
        s = "import json\n" + s

# 2) remove old block (if exists)
if OPEN in s and CLOSE in s:
    pre, mid = s.split(OPEN, 1)
    _, post = mid.split(CLOSE, 1)
    s = (pre.rstrip() + "\n\n" + post.lstrip())
    print("[OK] removed old P2 block V1")
else:
    print("[OK] old P2 block not found (skip remove)")

# 3) find app = Flask(...) anchor
m = re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', s, re.M)
if not m:
    # fallback: any 'app = Flask(' line
    m = re.search(r'^\s*app\s*=\s*Flask\(', s, re.M)
if not m:
    raise SystemExit("[ERR] cannot find 'app = Flask' anchor")

line_end = s.find("\n", m.end())
if line_end < 0:
    line_end = len(s)

block = textwrap.dedent(r"""
# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================
@app.after_request
def _vsp_p2_rfallow_contract_after_request(resp):
    """
    Enrich contract ONLY for wrapper responses from /api/vsp/run_file_allow.
    Do NOT modify raw JSON files like run_gate_summary.json.
    """
    try:
        from flask import request
        if request.path != "/api/vsp/run_file_allow":
            return resp

        # Only touch JSON responses
        txt = resp.get_data(as_text=True) if hasattr(resp, "get_data") else ""
        if not txt:
            return resp

        ctype = (resp.headers.get("Content-Type") or "").lower()
        if ("application/json" not in ctype) and (not txt.lstrip().startswith("{")):
            return resp

        try:
            d = json.loads(txt)
        except Exception:
            return resp

        if not isinstance(d, dict):
            return resp

        # Wrapper detection: must include at least one of these
        if not ("path" in d or "marker" in d or "err" in d):
            return resp

        rid = request.args.get("rid", "") or d.get("rid", "") or ""
        path_raw = request.args.get("path", "")
        if path_raw is None:
            path_raw = d.get("path", "") or ""

        ok = bool(d.get("ok"))
        err = (d.get("err") or "")
        err_l = err.lower()

        http = d.get("http", None)
        if http is None:
            if ok:
                http = 200
            elif ("not allowed" in err_l) or ("forbidden" in err_l) or ("deny" in err_l):
                http = 403
            elif ("not found" in err_l) or ("missing" in err_l) or ("no such" in err_l):
                http = 404
            else:
                http = 400

        allow = d.get("allow", None)
        if allow is None or not isinstance(allow, list):
            allow = []

        d["ok"] = ok
        d["http"] = int(http)
        d["allow"] = allow
        d["rid"] = rid
        d["path"] = path_raw
        if "marker" not in d:
            d["marker"] = "VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE"

        resp.set_data(json.dumps(d, ensure_ascii=False))
        resp.headers["Content-Type"] = "application/json; charset=utf-8"
        return resp
    except Exception:
        return resp
# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================
""").strip("\n") + "\n"

# inject right after app init line
s = s[:line_end+1] + block + "\n" + s[line_end+1:]
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] injected V2 SAFE + py_compile")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
