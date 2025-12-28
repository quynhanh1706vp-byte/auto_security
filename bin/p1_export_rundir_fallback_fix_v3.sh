#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

APP="vsp_demo_app.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rundirfix_v3_${TS}"
echo "[BACKUP] ${APP}.bak_rundirfix_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

fn = "api_vsp_run_export_v3_commercial_real_v1"
m = re.search(r'^(?P<ind>\s*)def\s+' + re.escape(fn) + r'\s*\(rid\)\s*:\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find export handler def api_vsp_run_export_v3_commercial_real_v1(rid):")

ind = m.group("ind")
start = m.start()

# end = next def with indent <= current indent (best-effort)
rest = s[m.end():]
m2 = re.search(r'^\s*def\s+\w+\s*\(', rest, flags=re.M)
end = m.end() + (m2.start() if m2 else len(rest))
blk = s[start:end]
lines = blk.splitlines(True)

marker = "VSP_P1_EXPORT_RUNDIR_HANDLER_RESOLVED_FALLBACK_V3"

# locate the RUN_DIR_NOT_FOUND payload with "resolved": None (export handler's failure)
idx_payload = None
for i, line in enumerate(lines):
    if '"RUN_DIR_NOT_FOUND"' in line and '"resolved"' in line:
        idx_payload = i
        break
if idx_payload is None:
    # fallback: look for resolved None line
    for i, line in enumerate(lines):
        if '"resolved": None' in line or "'resolved': None" in line:
            idx_payload = i
            break
if idx_payload is None:
    raise SystemExit("[ERR] cannot locate payload with resolved=None inside export handler")

# find nearest preceding if-not var
var = None
if_i = None
if_ind = ""
for j in range(idx_payload, -1, -1):
    mm = re.match(r'^(\s*)if\s+not\s+([A-Za-z_]\w*)\s*:\s*$', lines[j])
    if mm:
        if_ind = mm.group(1)
        var = mm.group(2)
        if_i = j
        break
if var is None:
    # try "if <var> is None:"
    for j in range(idx_payload, -1, -1):
        mm = re.match(r'^(\s*)if\s+([A-Za-z_]\w*)\s+is\s+None\s*:\s*$', lines[j])
        if mm:
            if_ind = mm.group(1)
            var = mm.group(2)
            if_i = j
            break
if var is None:
    raise SystemExit("[ERR] cannot find guarding if-not/if-is-None before payload")

# avoid double-inject
if marker in blk:
    print("[OK] already has marker:", marker)
else:
    inj = []
    inj.append(f"{if_ind}# --- {marker} (var={var}) ---\n")
    inj.append(f"{if_ind}try:\n")
    inj.append(f"{if_ind}    __rid = str(rid).strip() if rid is not None else ''\n")
    inj.append(f"{if_ind}    __rid_norm = ''\n")
    inj.append(f"{if_ind}    try:\n")
    inj.append(f"{if_ind}        import re as __re\n")
    inj.append(f"{if_ind}        mm = __re.search(r'(\\d{{8}}_\\d{{6}})', __rid)\n")
    inj.append(f"{if_ind}        __rid_norm = (mm.group(1) if mm else '').strip()\n")
    inj.append(f"{if_ind}    except Exception:\n")
    inj.append(f"{if_ind}        __rid_norm = ''\n")
    inj.append(f"{if_ind}    __cand = _vsp__resolve_run_dir_for_export(__rid, __rid_norm)\n")
    inj.append(f"{if_ind}    if __cand:\n")
    inj.append(f"{if_ind}        {var} = __cand\n")
    inj.append(f"{if_ind}        try:\n")
    inj.append(f"{if_ind}            how = 'fs_fallback'\n")
    inj.append(f"{if_ind}        except Exception:\n")
    inj.append(f"{if_ind}            pass\n")
    inj.append(f"{if_ind}except Exception:\n")
    inj.append(f"{if_ind}    pass\n")
    inj.append(f"{if_ind}# --- /{marker} ---\n")

    lines[if_i:if_i] = inj
    blk2 = "".join(lines)
    s = s[:start] + blk2 + s[end:]
    print(f"[OK] injected fallback before guard; var={var}")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== test export (RID + RIDN) =="
RID="RUN_20251120_130310"
RIDN="20251120_130310"

for X in "$RID" "$RIDN"; do
  echo "-- rid=$X --"
  curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
    "$BASE/api/vsp/run_export_v3?rid=$X&fmt=tgz" \
    -w "\nHTTP=%{http_code}\n"
  echo "CD:"
  grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
  echo "BODY:"
  head -c 160 /tmp/vsp_exp_body.bin; echo
done
