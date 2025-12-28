#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251219_092640}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_V1"

cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove unwrap inject MWs (they conflict with existing /vsp5 wrappers)
patterns = [
    r"\n# --- VSP_P0_RFA_UNWRAP_INJECT_V1B ---.*?# VSP_P0_RFA_UNWRAP_INJECT_V1B\n",
    r"\n# --- VSP_P0_RFA_UNWRAP_INJECT_V1C ---.*?# VSP_P0_RFA_UNWRAP_INJECT_V1C\n",
    r"\n# --- VSP_P0_RFA_UNWRAP_INJECT_V1 ---.*?# VSP_P0_RFA_UNWRAP_INJECT_V1\n",
]
s2=s
for pat in patterns:
    s2=re.sub(pat, "\n", s2, flags=re.DOTALL)

# 2) Make strict run_file_allow responses backward compatible:
#    if payload has {"data":{...}} then also copy data keys to top-level (when not colliding).
#    Patch both V1 and V2 blocks by injecting after payload={"ok":True,...,"data":data}
def inject_backcompat(src: str) -> str:
    # target the exact payload line in both MWs
    pat = r'(payload\s*=\s*\{\s*"ok"\s*:\s*True[^}]*"data"\s*:\s*data\s*\}\s*)'
    def repl(m):
        block = m.group(1)
        add = r'''
        # BACKCOMPAT: mirror data keys to top-level for old UI JS
        try:
            if isinstance(data, dict):
                for _k,_v in data.items():
                    if _k not in payload:
                        payload[_k]=_v
        except Exception:
            pass
'''
        return block + add
    return re.sub(pat, repl, src, flags=re.DOTALL)

s3 = inject_backcompat(s2)

if "VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_V1" not in s3:
    s3 = s3.rstrip() + "\n\n# VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_V1\n"
p.write_text(s3, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] removed unwrap MW + patched run_file_allow backcompat + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.8
fi

echo "== [VERIFY] /vsp5 should be 200 =="
curl -fsSI "$BASE/vsp5?rid=$RID" | head -n 5

echo "== [VERIFY] run_file_allow wrapper + top-level mirror =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); 
print("ok=",j.get("ok"),"has_data=",isinstance(j.get("data"),dict),
      "has_counts_top=",("counts_total" in j),
      "from=",j.get("from"))'

echo "== [VERIFY] findings_unified backcompat (top-level findings present) =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin);
print("ok=",j.get("ok"),"has_data=",isinstance(j.get("data"),dict),
      "top_findings=",isinstance(j.get("findings"),list),
      "data_findings=",isinstance((j.get("data") or {}).get("findings"),list))'

ok "DONE"
