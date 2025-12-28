#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_wsgi_export_rel_${TS}"
echo "[BACKUP] ${WSGI}.bak_wsgi_export_rel_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

mark = "VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4"
i = s.find(mark)
if i < 0:
    raise SystemExit("[ERR] V4 intercept marker not found; you must have v4 first")

# Insert release meta loader inside the block (safe: add near _vsp__tgz_build_v4)
if "def _vsp__rel_meta_v4" not in s:
    insert_after = "def _vsp__tgz_build_v4"
    j = s.find(insert_after, i)
    if j < 0:
        raise SystemExit("[ERR] cannot locate _vsp__tgz_build_v4 to insert release meta")
    # find line start before that def
    ls = s.rfind("\n", 0, j) + 1
    indent = re.match(r'^(\s*)', s[ls:j]).group(1)

    helper = f"""
{indent}def _vsp__rel_meta_v4():
{indent}    # read release_latest.json from common locations; return dict(ts, sha)
{indent}    try:
{indent}        ui_root = _Path(__file__).resolve().parent
{indent}        cands = [
{indent}            ui_root/"out_ci"/"releases"/"release_latest.json",
{indent}            ui_root/"out"/"releases"/"release_latest.json",
{indent}            ui_root.parent/"out_ci"/"releases"/"release_latest.json",
{indent}            ui_root.parent/"out"/"releases"/"release_latest.json",
{indent}            _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json"),
{indent}            _Path("/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json"),
{indent}        ]
{indent}        for f in cands:
{indent}            if f.exists():
{indent}                j = json.loads(f.read_text(encoding="utf-8", errors="replace"))
{indent}                return {{
{indent}                    "ts": (j.get("ts") or j.get("timestamp") or ""),
{indent}                    "sha": (j.get("sha") or j.get("sha256") or ""),
{indent}                    "package": (j.get("package") or j.get("pkg") or j.get("file") or ""),
{indent}                }}
{indent}    except Exception:
{indent}        pass
{indent}    return {{"ts":"", "sha":"", "package":""}}
"""
    s = s[:ls] + helper.rstrip("\n") + "\n" + s[ls:]
    print("[OK] inserted _vsp__rel_meta_v4()")

# Now patch filename creation: dl = f"VSP_EXPORT_{rid_norm or rid0}.tgz" -> add suffix
pat = r'dl\s*=\s*f"VSP_EXPORT_\{rid_norm or rid0\}\.tgz"'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find dl filename line to patch")
# find indent of that line
line_start = s.rfind("\n", 0, m.start()) + 1
indent = re.match(r'^(\s*)', s[line_start:m.start()]).group(1)

replacement = (
    f'{indent}rel = _vsp__rel_meta_v4()\n'
    f'{indent}suffix = ""\n'
    f'{indent}if rel.get("ts"):\n'
    f'{indent}    t = str(rel["ts"]).replace(":","").replace("-","").replace("T","_")\n'
    f'{indent}    suffix += f"_rel-{{t[:15]}}"\n'
    f'{indent}if rel.get("sha"):\n'
    f'{indent}    suffix += f"_sha-{{str(rel["sha"])[:12]}}"\n'
    f'{indent}dl = f"VSP_EXPORT_{{rid_norm or rid0}}{{suffix}}.tgz"'
)
s2, n = re.subn(pat, replacement, s, count=1)
if n != 1:
    raise SystemExit("[ERR] filename patch failed")
s = s2
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched TGZ filename to include release meta (v4b)")
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== test export TGZ (expect 200 + CD has rel/sha if available) =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "X-VSP-HOTFIX:"
grep -i '^X-VSP-HOTFIX:' /tmp/vsp_exp_hdr.txt || true
echo "Content-Disposition:"
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
