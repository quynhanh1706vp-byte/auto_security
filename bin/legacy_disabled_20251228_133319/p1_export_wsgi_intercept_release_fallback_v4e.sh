#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rel_v4e_${TS}"
echo "[BACKUP] ${WSGI}.bak_rel_v4e_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

a = s.find("# ===================== VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4")
b = s.find("# ===================== /VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4")
if a < 0 or b < 0 or b <= a:
    raise SystemExit("[ERR] V4 block not found")
blk = s[a:b]

# find the line "if rel.get('ts'):" and insert fallback just before computing t
# We'll replace the small section starting at: suffix = '' ... up to dl = ...
pat = r'^(?P<ind>[ \t]*)rel\s*=\s*_vsp__rel_meta_v4\(\)\s*\n(?P=ind)suffix\s*=\s*\'\'[\s\S]*?(?P=ind)dl\s*=\s*f\"VSP_EXPORT_\{rid_norm or rid0\}\{suffix\}\.tgz\"\s*$'
m = re.search(pat, blk, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate current v4d suffix/dl block inside V4")

ind = m.group("ind")
fallback_tag = time.strftime("%Y%m%d_%H%M%S")

rep = "\n".join([
    ind + "rel = _vsp__rel_meta_v4()",
    ind + "suffix = ''",
    ind + "ts0 = str(rel.get('ts') or '').strip()",
    ind + "if ts0:",
    ind + "    t = ts0.replace(':','').replace('-','').replace('T','_')",
    ind + "    t15 = t[:15]",
    ind + "    if t15: suffix += f\"_rel-{t15}\"",
    ind + "else:",
    ind + f"    suffix += \"_norel-{fallback_tag}\"",
    ind + "sha12 = str(rel.get('sha') or '').strip()[:12]",
    ind + "if sha12: suffix += f\"_sha-{sha12}\"",
    ind + "dl = f\"VSP_EXPORT_{rid_norm or rid0}{suffix}.tgz\"",
])

blk2, n = re.subn(pat, rep, blk, flags=re.M, count=1)
if n != 1:
    raise SystemExit("[ERR] replace failed")
blk = blk2

p.write_text(s[:a] + blk + s[b:], encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] v4e: add NO-PKG fallback tag into filename")
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "Content-Disposition:"
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
