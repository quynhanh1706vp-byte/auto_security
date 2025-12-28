#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="bin/p1_release_pack_and_register_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixman_${TS}"
echo "[BACKUP] ${F}.bak_fixman_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_release_pack_and_register_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FIX_MANIFEST_BLOCK_V1"

# Replace the python heredoc that used ${RID!r} etc with a safe argv-based version
pat = re.compile(r'python3\s+-\s+<<PY\s*\n(?:.*\n)*?PY\s*', re.M)

replacement = r'''python3 - "$RID" "$PKG" "$RUN_DIR" "$MAN" <<'PY'
import sys, json, os, time, hashlib
rid, pkg, run_dir, man = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for ch in iter(lambda: f.read(1024*1024), b''):
            h.update(ch)
    return h.hexdigest()

m = {
  "ok": True,
  "rid": rid,
  "created_ts": int(time.time()),
  "package_path": pkg,
  "package_sha256": sha256(pkg) if os.path.exists(pkg) else None,
  "run_dir": run_dir,
  "notes": "P1 release package for commercial UI",
  "download_url": f"/api/vsp/release_download?rid={rid}",
  "audit_url": f"/api/vsp/release_audit?rid={rid}"
}
with open(man, "w", encoding="utf-8") as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
print("[OK] manifest:", man)
PY
# ''' + MARK + r'''
'''

s2, n = pat.subn(replacement, s, count=1)
if n == 0:
    raise SystemExit("[ERR] could not locate python heredoc block to replace")
p.write_text(s2, encoding="utf-8")
print("[OK] patched manifest block:", MARK)
PY

bash -n "$F" && echo "[OK] bash -n: syntax OK"
grep -n "VSP_P1_FIX_MANIFEST_BLOCK_V1" "$F" | head -n 2 || true
