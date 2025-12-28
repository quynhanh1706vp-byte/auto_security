#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_mfroot_${TS}"
echo "[BACKUP] ${W}.bak_mfroot_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1"
end   = "# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1"
i = s.find(start)
j = s.find(end)
if i < 0 or j < 0 or j < i:
    print("[ERR] cannot locate V2 FS APPEND block to patch")
    raise SystemExit(2)

blk = s[i:j]

# 1) expand roots list
new_roots = r'''_VSP_MF_ROOTS = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1",
    ]'''

blk2, n = re.subn(r"_VSP_MF_ROOTS\s*=\s*\[[\s\S]*?\]\s*", new_roots+"\n", blk, count=1)
if n != 1:
    print("[ERR] cannot patch _VSP_MF_ROOTS list")
    raise SystemExit(2)

# 2) patch finder: try root/rid and also one-level nested: root/*/rid
finder_pat = r"def _vsp_mf_find_run_dir\(rid: str\):[\s\S]*?return None"
finder_new = r"""def _vsp_mf_find_run_dir(rid: str):
        # try direct root/rid
        for root in _VSP_MF_ROOTS:
            try:
                d = Path(root) / rid
                if d.is_dir():
                    return d
            except Exception:
                pass
        # fallback: one-level nested root/*/rid (some layouts group runs by project)
        for root in _VSP_MF_ROOTS:
            try:
                rr = Path(root)
                if not rr.is_dir():
                    continue
                for sub in rr.iterdir():
                    if not sub.is_dir():
                        continue
                    d = sub / rid
                    if d.is_dir():
                        return d
            except Exception:
                pass
        return None"""

blk3, n2 = re.subn(finder_pat, finder_new, blk2, count=1)
if n2 != 1:
    print("[ERR] cannot patch finder function")
    raise SystemExit(2)

s2 = s[:i] + blk3 + s[j:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched manifest v2 roots + finder")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke manifest (lite) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"),"run_dir=",j.get("run_dir"))'

echo "[DONE]"
