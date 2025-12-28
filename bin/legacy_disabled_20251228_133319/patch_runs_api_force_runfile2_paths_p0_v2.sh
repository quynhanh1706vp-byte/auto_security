#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_force_runfile2_${TS}"
echo "[BACKUP] ${F}.bak_force_runfile2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_FORCE_RUNFILE2_PATHS_P0_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We patch the after_request in run_file2 block by adding a second rewrite pass:
# - If has.json_path etc points to /api/vsp/run_file -> rewrite to run_file2
# - If summary=true but summary_path missing -> set to run_file2 default
needle = r"def _rf2_after\(resp\):"
m = re.search(needle, s)
if not m:
    raise SystemExit("[ERR] cannot find _rf2_after(resp) in file")

# Insert just before encoding body (before `body = _json2.dumps(...)`)
ins_pat = r"(\s+body\s*=\s*_json2\.dumps\(data,\s*ensure_ascii=False\)\s*\n)"
m2 = re.search(ins_pat, s)
if not m2:
    raise SystemExit("[ERR] cannot find json dumps in _rf2_after")

inject = r"""
            # VSP_FORCE_RUNFILE2_PATHS_P0_V2: normalize path fields and fill missing *_path
            for it in items:
                if not isinstance(it, dict):
                    continue
                has = it.get("has") or {}
                if not isinstance(has, dict):
                    continue
                rid = (it.get("run_id") or it.get("rid") or "").strip()
                if not rid:
                    continue

                # rewrite run_file -> run_file2
                for k in ("html_path","json_path","csv_path","sarif_path","summary_path"):
                    v = has.get(k)
                    if isinstance(v, str) and v.startswith("/api/vsp/run_file?"):
                        has[k] = v.replace("/api/vsp/run_file?","/api/vsp/run_file2?",1)

                # fill missing paths if boolean says true
                if has.get("json") is True and not has.get("json_path"):
                    has["json_path"] = _rf2_url(rid, "reports/findings_unified.json")
                if has.get("summary") is True and not has.get("summary_path"):
                    has["summary_path"] = _rf2_url(rid, "reports/run_gate_summary.json")
                if has.get("html") is True and not has.get("html_path"):
                    has["html_path"] = _rf2_url(rid, "reports/index.html")
                if has.get("csv") is True and not has.get("csv_path"):
                    has["csv_path"] = _rf2_url(rid, "reports/findings_unified.csv")
                if has.get("sarif") is True and not has.get("sarif_path"):
                    has["sarif_path"] = _rf2_url(rid, "reports/findings_unified.sarif")

                it["has"] = has
"""
s2 = s[:m2.start(1)] + inject + s[m2.start(1):]
# add marker comment near top of injected area
s2 = s2.replace("VSP_FORCE_RUNFILE2_PATHS_P0_V2", "VSP_FORCE_RUNFILE2_PATHS_P0_V2") + f"\n# {MARK}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== verify paths now use run_file2 =="
curl -sS "http://127.0.0.1:8910/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("has=", it.get("has"))
PY
