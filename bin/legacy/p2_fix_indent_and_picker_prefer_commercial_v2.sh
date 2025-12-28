#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head; need ls

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

# 1) Restore from last known-good backup (the one created right before the bad patch)
bak="$(ls -1t vsp_demo_app.py.bak_picker_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  bak="$(ls -1t vsp_demo_app.py.bak_rescue_v3_disk_* 2>/dev/null | head -n 1 || true)"
fi
[ -n "$bak" ] || err "no backup found (bak_picker_* or bak_rescue_v3_disk_*)"

cp -f "$bak" "$APP"
ok "restored $APP from $bak"

python3 -m py_compile "$APP"
ok "py_compile OK after restore"

# 2) Patch ONLY inside VSP_V3_FROM_DISK_OVERRIDE_V2 block
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_b = "# ===== VSP_V3_FROM_DISK_OVERRIDE_V2 ====="
tag_e = "# ===== /VSP_V3_FROM_DISK_OVERRIDE_V2 ====="
ib = s.find(tag_b)
ie = s.find(tag_e)
if ib < 0 or ie < 0 or ie <= ib:
    raise SystemExit("[ERR] cannot locate VSP_V3_FROM_DISK_OVERRIDE_V2 block")

block = s[ib:ie]

def replace_list_in_func(block: str, func_name: str, var_name: str, new_lines: list[str]) -> tuple[str,bool]:
    # isolate function text inside block (top-level defs start at column 0)
    m = re.search(rf"(?m)^def\s+{re.escape(func_name)}\b.*?:\s*$", block)
    if not m:
        return block, False
    start = m.start()
    # end at next top-level "def " or end of block
    m2 = re.search(r"(?m)^def\s+\w+\b", block[m.end():])
    end = (m.end() + m2.start()) if m2 else len(block)
    fn = block[start:end]

    # find the list assignment
    m3 = re.search(rf"(?m)^(\s*){re.escape(var_name)}\s*=\s*\[\s*$", fn)
    if not m3:
        return block, False
    indent = m3.group(1)
    # find closing bracket line at same indent
    m4 = re.search(rf"(?m)^{re.escape(indent)}\]\s*$", fn[m3.end():])
    if not m4:
        return block, False
    list_start = m3.start()
    list_end = m3.end() + m4.end()

    # build replacement
    rep = indent + var_name + " = [\n"
    for line in new_lines:
        rep += indent + "    " + line + "\n"
    rep += indent + "]\n"

    fn2 = fn[:list_start] + rep + fn[list_end:]
    block2 = block[:start] + fn2 + block[end:]
    return block2, True

# Prefer commercial/unified first
new_rels = [
    '"reports/findings_unified_commercial.json",',
    '"report/findings_unified_commercial.json",',
    '"findings_unified_commercial.json",',
    '"unified/findings_unified.json",',
    '"reports/findings_unified.json",',
    '"report/findings_unified.json",',
    '"findings_unified.json",',
    '"reports/findings.json",',
    '"report/findings.json",',
]

new_patterns = [
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified_commercial.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified_commercial.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified_commercial.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/unified/findings_unified.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified.json",',
    'f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified.json",',
]

block2, ok1 = replace_list_in_func(block, "_vsp_guess_paths_for_rid", "rels", new_rels)
block3, ok2 = replace_list_in_func(block2, "_vsp_find_findings_file", "patterns", new_patterns)

if not ok1:
    raise SystemExit("[ERR] cannot patch rels in _vsp_guess_paths_for_rid")
if not ok2:
    raise SystemExit("[ERR] cannot patch patterns in _vsp_find_findings_file")

s2 = s[:ib] + block3 + s[ie:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched inside disk override: rels+patterns (prefer commercial/unified)")
PY

python3 -m py_compile "$APP"
ok "py_compile OK after patch"

# 3) Restart
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.7
  systemctl is-active "$SVC" >/dev/null 2>&1 && ok "service active: $SVC" || echo "[WARN] service not active; check: systemctl status $SVC"
fi

# 4) Verify
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
ok "RID=$RID"

curl -fsS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=5&offset=0" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("from_path=",j.get("from_path"),"total_findings=",j.get("total_findings"),"items_len=",len(j.get("items") or []),"sev=",j.get("sev"))'

ok "DONE. Ctrl+F5 /vsp5?rid=$RID"
