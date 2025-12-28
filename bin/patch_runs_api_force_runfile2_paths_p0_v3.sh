#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_force_runfile2_v3_${TS}"
echo "[BACKUP] ${F}.bak_force_runfile2_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_FORCE_RUNFILE2_PATHS_P0_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find the run_file2 after_request function body and insert a FINAL rewrite just before dumps()
m_after = re.search(r"def _rf2_after\(resp\):", s)
if not m_after:
    raise SystemExit("[ERR] cannot find _rf2_after(resp)")

m_dumps = re.search(r"\n(\s+body\s*=\s*_json2\.dumps\(data,\s*ensure_ascii=False\)\s*\n)", s)
if not m_dumps:
    raise SystemExit("[ERR] cannot find _json2.dumps(data...) in _rf2_after")

inject = r"""
            # VSP_FORCE_RUNFILE2_PATHS_P0_V3: FINAL normalize (override any earlier after_request)
            for it in items:
                if not isinstance(it, dict):
                    continue
                rid = (it.get("run_id") or it.get("rid") or "").strip()
                if not rid:
                    continue
                has = it.get("has") or {}
                if not isinstance(has, dict):
                    continue

                # rewrite any old run_file url -> run_file2
                for k in ("html_path","json_path","csv_path","sarif_path","summary_path"):
                    v = has.get(k)
                    if isinstance(v, str) and v.startswith("/api/vsp/run_file?"):
                        has[k] = v.replace("/api/vsp/run_file?","/api/vsp/run_file2?",1)

                # fill missing *_path if boolean true
                if has.get("json") is True and not has.get("json_path"):
                    has["json_path"] = _rf2_url(rid, "reports/findings_unified.json")
                if has.get("summary") is True and not has.get("summary_path"):
                    has["summary_path"] = _rf2_url(rid, "reports/run_gate_summary.json")
                if has.get("html") is True and not has.get("html_path"):
                    has["html_path"] = _rf2_url(rid, "reports/index.html")

                it["has"] = has
"""

s2 = s[:m_dumps.start(1)] + inject + s[m_dumps.start(1):]
s2 += f"\n# {MARK}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 0.2

# robust verify (no race)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/verify_runs_json_wait_p0_v1.sh
