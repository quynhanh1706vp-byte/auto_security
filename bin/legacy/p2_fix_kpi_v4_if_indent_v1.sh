#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_kpi_ifindent_${TS}"
echo "[BACKUP] ${F}.bak_kpi_ifindent_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(errors="ignore").splitlines(True)

def ws(s: str) -> str:
    m = re.match(r'^([ \t]*)', s)
    return m.group(1) if m else ""

def fix_block(start_pat: str, print_pat: str, fail_print_pat: str):
    """
    Find:
      if _os.environ.get(...):
         print(skipped)
      else:
         print(failed)
    and normalize indentation based on 'if' line.
    """
    changed = 0
    for i in range(len(lines)):
        if not re.search(start_pat, lines[i]):
            continue
        if_ws = ws(lines[i])
        in_ws = if_ws + "    "

        # fix next ~12 lines locally
        for j in range(i+1, min(len(lines), i+18)):
            t = lines[j].lstrip(" \t")
            if re.match(r'^else:\s*$', t.rstrip("\n")):
                if not lines[j].startswith(if_ws):
                    lines[j] = if_ws + "else:\n"
                    changed += 1
                continue

            if re.search(print_pat, t):
                if not lines[j].startswith(in_ws):
                    lines[j] = in_ws + t
                    changed += 1
                continue

            if re.search(fail_print_pat, t):
                if not lines[j].startswith(in_ws):
                    lines[j] = in_ws + t
                    changed += 1
                continue

            # stop if we leave the tiny if/else area
            if t.strip().startswith(("except", "finally")):
                break
        # only first occurrence per block is enough
        break
    return changed

# 1) mount block
c1 = fix_block(
    r'if\s+_os\.environ\.get\("VSP_SAFE_DISABLE_KPI_V4","1"\)\s*==\s*"1"\s*:',
    r'\[VSP_KPI_V4\]\s*mount skipped',
    r'\[VSP_KPI_V4\]\s*mount failed'
)

# 2) retry block
c2 = fix_block(
    r'if\s+_os\.environ\.get\("VSP_SAFE_DISABLE_KPI_V4","1"\)\s*==\s*"1"\s*:',
    r'\[VSP_KPI_V4\]\s*retry skipped',
    r'\[VSP_KPI_V4\]\s*retry mount under app_context failed'
)

p.write_text("".join(lines), encoding="utf-8")
print("[OK] indent normalized changes:", c1 + c2)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true
sleep 0.6
sudo systemctl status "$SVC" -l --no-pager || true

echo "== quick probe =="
for u in /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "== KPI_V4 log tail =="
sudo journalctl -u "$SVC" -n 120 --no-pager | grep -n "VSP_KPI_V4" | tail -n 30 || true
