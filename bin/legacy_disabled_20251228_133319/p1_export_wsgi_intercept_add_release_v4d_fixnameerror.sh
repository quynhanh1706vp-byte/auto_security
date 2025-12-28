#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need ls

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] restore latest bak_wsgi_export_rel_* =="
BAK="$(ls -1t ${WSGI}.bak_wsgi_export_rel_* 2>/dev/null | head -n1 || true)"
if [ -z "${BAK}" ]; then
  echo "[ERR] no backup found: ${WSGI}.bak_wsgi_export_rel_*"
  exit 2
fi
cp -f "$BAK" "$WSGI"
echo "[OK] restored: $BAK -> $WSGI"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_wsgi_export_rel_v4d_${TS}"
echo "[BACKUP] ${WSGI}.bak_wsgi_export_rel_v4d_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start_m = "# ===================== VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4"
end_m   = "# ===================== /VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4"
a = s.find(start_m)
b = s.find(end_m)
if a < 0 or b < 0 or b <= a:
    raise SystemExit("[ERR] V4 intercept block markers not found")

blk = s[a:b]

# helper
if "def _vsp__rel_meta_v4" not in blk:
    m = re.search(r'^(?P<ind>[ \t]*)def _vsp__tgz_build_v4\s*\(', blk, flags=re.M)
    if not m:
        raise SystemExit("[ERR] cannot find def _vsp__tgz_build_v4() inside V4 block")
    ind = m.group("ind")
    helper = (
        ind + "def _vsp__rel_meta_v4():\n" +
        ind + "    # read release_latest.json from common locations; return dict(ts, sha, package)\n" +
        ind + "    try:\n" +
        ind + "        ui_root = _Path(__file__).resolve().parent\n" +
        ind + "        cands = [\n" +
        ind + "            ui_root/'out_ci'/'releases'/'release_latest.json',\n" +
        ind + "            ui_root/'out'/'releases'/'release_latest.json',\n" +
        ind + "            ui_root.parent/'out_ci'/'releases'/'release_latest.json',\n" +
        ind + "            ui_root.parent/'out'/'releases'/'release_latest.json',\n" +
        ind + "            _Path('/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json'),\n" +
        ind + "            _Path('/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json'),\n" +
        ind + "        ]\n" +
        ind + "        for f in cands:\n" +
        ind + "            if f.exists():\n" +
        ind + "                j = json.loads(f.read_text(encoding='utf-8', errors='replace'))\n" +
        ind + "                return {\n" +
        ind + "                    'ts': (j.get('ts') or j.get('timestamp') or ''),\n" +
        ind + "                    'sha': (j.get('sha') or j.get('sha256') or ''),\n" +
        ind + "                    'package': (j.get('package') or j.get('pkg') or j.get('file') or ''),\n" +
        ind + "                }\n" +
        ind + "    except Exception:\n" +
        ind + "        pass\n" +
        ind + "    return {'ts':'', 'sha':'', 'package':''}\n\n"
    )
    blk = blk[:m.start()] + helper + blk[m.start():]
    print("[OK] inserted _vsp__rel_meta_v4()")

# patch dl line inside V4 block
dl_pat = r'^(?P<ind>[ \t]*)dl\s*=\s*f"VSP_EXPORT_\{rid_norm or rid0\}\.tgz"\s*$'
m2 = re.search(dl_pat, blk, flags=re.M)
if not m2:
    raise SystemExit("[ERR] cannot find dl filename line inside V4 block")
ind = m2.group("ind")

rep = "\n".join([
    ind + "rel = _vsp__rel_meta_v4()",
    ind + "suffix = ''",
    ind + "if rel.get('ts'):",
    ind + "    t = str(rel['ts']).replace(':','').replace('-','').replace('T','_')",
    ind + "    t15 = t[:15]",
    ind + "    if t15: suffix += f\"_rel-{t15}\"",
    ind + "sha12 = str(rel.get('sha') or '')[:12]",
    ind + "if sha12: suffix += f\"_sha-{sha12}\"",
    ind + "dl = f\"VSP_EXPORT_{rid_norm or rid0}{suffix}.tgz\"",
])

blk = re.sub(dl_pat, rep, blk, flags=re.M, count=1)
print("[OK] patched TGZ dl filename (v4d)")

s2 = s[:a] + blk + s[b:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK:", p)
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== [1] test export TGZ header =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "X-VSP-HOTFIX:"
grep -i '^X-VSP-HOTFIX:' /tmp/vsp_exp_hdr.txt || true
echo "Content-Disposition:"
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
