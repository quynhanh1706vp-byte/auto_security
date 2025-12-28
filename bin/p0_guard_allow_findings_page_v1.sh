#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_GUARD_ALLOW_FINDINGS_PAGE_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_guardfp_${TS}"
echo "[BACKUP] ${W}.bak_guardfp_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P0_GUARD_ALLOW_FINDINGS_PAGE_V1"
if mark in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

lines = s.splitlines(True)

# find "not allowed" return lines
na_idx = []
for i, ln in enumerate(lines):
    if "not allowed" in ln and ("path" in ln or "PATH_INFO" in ln or "request" in ln):
        na_idx.append(i)

if not na_idx:
    # fallback: any line containing "not allowed"
    for i, ln in enumerate(lines):
        if "not allowed" in ln:
            na_idx.append(i)
    if not na_idx:
        raise SystemExit("[ERR] cannot find 'not allowed' in file")

patched = 0
target = '/api/vsp/findings_page'

def patch_if_line(i):
    global patched
    ln = lines[i]
    if target in ln:
        return False
    if (("if " in ln) and ("path" in ln) and ("not in" in ln) and ln.rstrip().endswith(":")):
        # inject before colon
        ln2 = ln.rstrip("\n")
        ln2 = ln2[:-1] + f' and path != "{target}":\n'
        lines[i] = ln2
        return True
    return False

for idx in na_idx[:8]:
    # search backward up to 35 lines for relevant 'if ... path ... not in ...:'
    found = False
    for j in range(max(0, idx-35), idx)[::-1]:
        if patch_if_line(j):
            patched += 1
            found = True
            break
    if found:
        continue

# fallback: patch first global condition containing startswith('/api/vsp/') and 'not in'
if patched == 0:
    for i, ln in enumerate(lines):
        if ("startswith" in ln and "/api/vsp/" in ln and "not in" in ln and "path" in ln and ln.rstrip().endswith(":")):
            if target not in ln:
                ln2 = ln.rstrip("\n")
                ln2 = ln2[:-1] + f' and path != "{target}":\n'
                lines[i] = ln2
                patched += 1
                break

# append marker
lines.append(f"\n# ===================== {mark} =====================\n")
lines.append(f"# patched_if_lines={patched}\n")
lines.append(f"# allow bypass for {target} even under outer guard\n")
lines.append(f"# ===================== /{mark} =====================\n")

p.write_text("".join(lines), encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] guard patched; patched_if_lines=", patched)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke SAFE /api/vsp/findings_page (must NOT be 'not allowed') =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"

H="/tmp/vsp_fp_hdr.$$"
B="/tmp/vsp_fp_body.$$"
U="$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3&debug=1"
HTTP="$(curl -sS -D "$H" -o "$B" -w "%{http_code}" "$U" || true)"
echo "[HTTP]=$HTTP bytes=$(wc -c <"$B" 2>/dev/null || echo 0)"
echo "---- BODY (first 200) ----"; head -c 200 "$B"; echo
rm -f "$H" "$B" || true

echo "[DONE]"
