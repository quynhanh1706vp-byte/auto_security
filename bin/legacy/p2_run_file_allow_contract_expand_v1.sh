#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p2_rfallow_contract_${TS}"
echo "[BACKUP] ${APP}.bak_p2_rfallow_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1"
if MARK in s:
    print("[OK] marker exists, skip")
else:
    # Ensure imports exist (json is required)
    if re.search(r'^\s*import\s+json\b', s, re.M) is None and re.search(r'^\s*from\s+.*\s+import\s+.*\bjson\b', s, re.M) is None:
        # insert near top after first block of imports
        m = re.search(r'^(?:from\s+\S+\s+import\s+.*|import\s+\S+)(?:\s*\n(?:from\s+\S+\s+import\s+.*|import\s+\S+))*', s, re.M)
        if m:
            ins = m.end()
            s = s[:ins] + "\nimport json\n" + s[ins:]
            print("[OK] inserted: import json")
        else:
            s = "import json\n" + s
            print("[OK] inserted: import json at BOF")

    # Find app object name (usually app = Flask(...))
    # We'll just inject after the first occurrence of "app = Flask"
    m = re.search(r'^\s*app\s*=\s*Flask\(', s, re.M)
    if not m:
        raise SystemExit("[ERR] cannot find 'app = Flask(' to anchor after_request injection")

    anchor_line_end = s.find("\n", m.start())
    if anchor_line_end < 0:
        anchor_line_end = len(s)

    block = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    @app.after_request
    def _vsp_p2_rfallow_contract_after_request(resp):
        \"\"\"Enrich JSON contract for /api/vsp/run_file_allow without changing HTTP 200 policy.\"\"\"
        try:
            from flask import request
            if request.path != "/api/vsp/run_file_allow":
                return resp

            rid = request.args.get("rid", "") or ""
            path_raw = request.args.get("path", "")
            # keep raw path (do not overwrite with sanitized empty)
            if path_raw is None:
                path_raw = ""

            # Parse JSON body if possible
            txt = resp.get_data(as_text=True) if hasattr(resp, "get_data") else ""
            if not txt:
                return resp

            is_jsonish = False
            ctype = (resp.headers.get("Content-Type") or "").lower()
            if "application/json" in ctype:
                is_jsonish = True
            if (not is_jsonish) and txt.lstrip().startswith("{{"):
                is_jsonish = True

            if not is_jsonish:
                return resp

            try:
                d = json.loads(txt)
            except Exception:
                return resp

            if not isinstance(d, dict):
                return resp

            ok = bool(d.get("ok"))
            err = (d.get("err") or "")
            err_l = err.lower()

            # Semantic http field (NOT actual HTTP status)
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

            # allow list (empty by default; safe for commercial)
            allow = d.get("allow", None)
            if allow is None or not isinstance(allow, list):
                allow = []

            # normalize required keys
            d["ok"] = ok
            d["http"] = int(http)
            d["allow"] = allow
            d["rid"] = rid or d.get("rid", "") or ""
            d["path"] = path_raw if path_raw != "" else (d.get("path", "") or "")

            # keep marker if exists
            if "marker" not in d:
                d["marker"] = "{MARK}"

            out = json.dumps(d, ensure_ascii=False)
            resp.set_data(out)
            resp.headers["Content-Type"] = "application/json; charset=utf-8"
            return resp
        except Exception:
            return resp
    # ===================== /{MARK} =====================
    """).strip("\n") + "\n"

    # inject block after app=Flask(...) line to keep it early and stable
    s = s[:anchor_line_end+1] + block + "\n" + s[anchor_line_end+1:]
    p.write_text(s, encoding="utf-8")
    print("[OK] injected after_request contract enricher:", MARK)

# compile check
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile:", str(p))
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
