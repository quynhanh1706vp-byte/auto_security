#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sudo; need systemctl; need curl

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfilegw_v1p3b_${TS}"
ok "backup: ${F}.bak_runfilegw_v1p3b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_RUN_FILE_CONTRACT_WSGI_V1P3B"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

snippet = textwrap.dedent(r'''
# ==================== VSP_P0_RUN_FILE_CONTRACT_WSGI_V1P3B ====================
# Commercial contract: FE calls /api/vsp/run_file?rid=...&name=...
# Gateway maps logical name -> internal file and redirects to run_file_allow.
try:
    import re as _re
    from flask import request as _rq, redirect as _rd, jsonify as _jz
except Exception:
    _re = None
    _rq = None
    _rd = None
    _jz = None

@app.get("/api/vsp/run_file")
def vsp_run_file_contract_w1p3b():
    try:
        rid = (_rq.args.get("rid") or "").strip()
        name = (_rq.args.get("name") or "").strip()
        if not rid or not name:
            return _jz({"ok": False, "error": "missing rid/name"}), 400

        MAP = {
          "gate_summary": "run_gate_summary.json",
          "gate_json": "run_gate.json",
          "findings_unified": "findings_unified.json",
          "findings_html": "reports/findings_unified.html",
          "run_manifest": "run_manifest.json",
          "run_evidence_index": "run_evidence_index.json",
        }
        path = MAP.get(name, "")

        # allow raw safe filenames (no slash) as escape hatch
        if not path:
            if "/" in name or "\\" in name:
                return _jz({"ok": False, "error": "invalid name"}), 400
            if not _re or not _re.match(r'^[a-zA-Z0-9_.-]{1,120}$', name):
                return _jz({"ok": False, "error": "invalid name"}), 400
            path = name

        return _rd(f"/api/vsp/run_file_allow?rid={rid}&path={path}", code=302)
    except Exception as e:
        try:
            return _jz({"ok": False, "error": str(e)}), 500
        except Exception:
            return ("error", 500)
# ==================== /VSP_P0_RUN_FILE_CONTRACT_WSGI_V1P3B ====================
''')

# Insert after app = Flask(...) if found; else append near end.
m = re.search(r'^\s*app\s*=\s*Flask\s*\(', s, flags=re.M)
if m:
    # insert after that line
    ln_end = s.find("\n", m.end())
    if ln_end < 0: ln_end = m.end()
    s2 = s[:ln_end+1] + "\n" + snippet + "\n" + s[ln_end+1:]
else:
    # fallback: append (safe)
    s2 = s + "\n\n" + snippet + "\n"

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] injected + py_compile OK")
PY

ok "py_compile OK: $F"

sudo systemctl daemon-reload || true
sudo systemctl restart vsp-ui-8910.service
ok "restarted vsp-ui-8910.service"

echo "== [SMOKE] run_file should return 302 (not 404) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=VSP_CI_20251218_114312&name=gate_summary" | head -n 20
