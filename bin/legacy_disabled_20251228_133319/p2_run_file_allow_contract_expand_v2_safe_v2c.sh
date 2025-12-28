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
cp -f "$APP" "${APP}.bak_p2_rfallow_contract_v2c_${TS}"
echo "[BACKUP] ${APP}.bak_p2_rfallow_contract_v2c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) ensure import json exists
if re.search(r'^\s*import\s+json\b', s, re.M) is None:
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*|import\s+\S+)(?:\s*\n(?:from\s+\S+\s+import\s+.*|import\s+\S+))*', s, re.M)
    if m:
        s = s[:m.end()] + "\nimport json\n" + s[m.end():]
    else:
        s = "import json\n" + s

# 2) remove older blocks if present (V1 and V2_SAFE)
def drop_block(txt: str, open_mark: str, close_mark: str) -> str:
    if open_mark in txt and close_mark in txt:
        pre, mid = txt.split(open_mark, 1)
        _, post = mid.split(close_mark, 1)
        return pre.rstrip() + "\n\n" + post.lstrip()
    return txt

s = drop_block(
    s,
    "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 =====================",
    "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 =====================",
)
s = drop_block(
    s,
    "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
    "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
)

# 3) find anchor after app = Flask(...)
m = re.search(r'^\s*app\s*=\s*Flask\(', s, re.M)
if not m:
    raise SystemExit("[ERR] cannot find anchor: app = Flask(")
line_end = s.find("\n", m.start())
if line_end < 0:
    line_end = len(s)

# 4) build injection block without triple-quote traps
block_lines = [
    "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
    "@app.after_request",
    "def _vsp_p2_rfallow_contract_after_request(resp):",
    "    # Enrich contract ONLY for wrapper responses from /api/vsp/run_file_allow.",
    "    # Do NOT modify raw JSON files like run_gate_summary.json.",
    "    try:",
    "        from flask import request",
    "        if request.path != \"/api/vsp/run_file_allow\":",
    "            return resp",
    "",
    "        txt = resp.get_data(as_text=True) if hasattr(resp, \"get_data\") else \"\"",
    "        if not txt:",
    "            return resp",
    "",
    "        ctype = (resp.headers.get(\"Content-Type\") or \"\").lower()",
    "        if (\"application/json\" not in ctype) and (not txt.lstrip().startswith(\"{\")):",
    "            return resp",
    "",
    "        try:",
    "            d = json.loads(txt)",
    "        except Exception:",
    "            return resp",
    "        if not isinstance(d, dict):",
    "            return resp",
    "",
    "        # Wrapper detection: must include at least one of these keys",
    "        if not (\"path\" in d or \"marker\" in d or \"err\" in d):",
    "            return resp",
    "",
    "        rid = (request.args.get(\"rid\", \"\") or d.get(\"rid\", \"\") or \"\")",
    "        path_raw = request.args.get(\"path\", \"\")",
    "        if path_raw is None or path_raw == \"\":",
    "            path_raw = (d.get(\"path\", \"\") or \"\")",
    "",
    "        ok = bool(d.get(\"ok\"))",
    "        err = (d.get(\"err\") or \"\")",
    "        err_l = err.lower()",
    "",
    "        http = d.get(\"http\", None)",
    "        if http is None:",
    "            if ok:",
    "                http = 200",
    "            elif (\"not allowed\" in err_l) or (\"forbidden\" in err_l) or (\"deny\" in err_l):",
    "                http = 403",
    "            elif (\"not found\" in err_l) or (\"missing\" in err_l) or (\"no such\" in err_l):",
    "                http = 404",
    "            else:",
    "                http = 400",
    "",
    "        allow = d.get(\"allow\", None)",
    "        if allow is None or not isinstance(allow, list):",
    "            allow = []",
    "",
    "        d[\"ok\"] = ok",
    "        d[\"http\"] = int(http)",
    "        d[\"allow\"] = allow",
    "        d[\"rid\"] = rid",
    "        d[\"path\"] = path_raw",
    "        if \"marker\" not in d:",
    "            d[\"marker\"] = \"VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE\"",
    "",
    "        resp.set_data(json.dumps(d, ensure_ascii=False))",
    "        resp.headers[\"Content-Type\"] = \"application/json; charset=utf-8\"",
    "        return resp",
    "    except Exception:",
    "        return resp",
    "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
    "",
]
block = "\n".join(block_lines)

# inject right AFTER the 'app = Flask(' line (keep stable)
insert_at = s.find("\n", m.end())
if insert_at < 0:
    insert_at = len(s)
s = s[:insert_at+1] + block + s[insert_at+1:]

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] injected V2_SAFE (v2c) + py_compile")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
