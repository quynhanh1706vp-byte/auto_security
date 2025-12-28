#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_has_sha_dl_${TS}"
echo "[BACKUP] ${F}.bak_has_sha_dl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_HAS_SHA_AND_DOWNLOAD_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# 1) Make api_run_file support download=1
s2 = re.sub(
    r'^\s*return\s+send_file\s*\(\s*str\s*\(\s*rp\s*\)\s*\)\s*$',
    '    want_dl = (request.args.get("download","") or "").strip().lower() in ("1","true","yes","y")\n'
    '    return send_file(str(rp), as_attachment=want_dl, download_name=rp.name)\n',
    s,
    flags=re.M
)
s = s2

# 2) In _has(): add sha flag + sha_path, and add download=1 to json/summary/txt paths
# We patch the dict that already contains html_path/json_path/summary_path/txt_path
def patch_path(key, add_download):
    # find f"...name=reports%2Fxxx"
    pat = rf'("{key}"\s*:\s*[^,\n]+)'
    return pat

# add download=1 to json_path/summary_path/txt_path if they are run_file urls
for k in ("json_path","summary_path","txt_path"):
    s = re.sub(
        rf'("{k}"\s*:\s*[^,\n]*\/api\/vsp\/run_file\?[^,\n]*)(["\'])',
        lambda m: (m.group(1) + ("&download=1" if "download=1" not in m.group(1) else "") + m.group(2)),
        s
    )

# add sha flag + sha_path near txt_path if not present
if '"sha_path"' not in s:
    s = re.sub(
        r'("txt_path"\s*:\s*[^,\n]+)(\s*[,\n])',
        r'\1,\n                "sha": (run_dir/"reports/SHA256SUMS.txt").exists(),\n'
        r'                "sha_path": f"/api/vsp/run_file?rid={rid}&name=reports%2FSHA256SUMS.txt&download=1"\2',
        s,
        count=1
    )

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK: vsp_runs_reports_bp.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: /api/vsp/runs contains sha_path? =="
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin); h=j["items"][0]["has"]
print("keys:", sorted([k for k in h.keys() if "path" in k or k in ("sha",)]))
print("sha_path:", h.get("sha_path"))
PY

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/run_gate_summary.json&download=1" | head -n 12
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt&download=1" | head -n 12
