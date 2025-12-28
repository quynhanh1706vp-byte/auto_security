#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

# tìm file template/html có export-rid
H="$(grep -RIl --include='*.html' --include='*.jinja' --include='*.j2' --include='*.tmpl' 'export-rid' templates 2>/dev/null | head -n1 || true)"
[ -n "${H:-}" ] || { echo "[ERR] cannot find template containing export-rid under templates/"; exit 2; }

cp -f "$H" "$H.bak_export_rid_guard_${TS}"
echo "[BACKUP] $H.bak_export_rid_guard_${TS}"

python3 - <<PY
from pathlib import Path
import re

p=Path("$H")
s=p.read_text(encoding="utf-8", errors="replace")

# guard mọi dạng: document.getElementById('export-rid').textContent = rid || "(none)";
pat = re.compile(
  r"document\.getElementById\(\s*['\"]export-rid['\"]\s*\)\.textContent\s*=\s*rid\s*\|\|\s*['\"]\(?none\)?['\"]\s*;",
  re.I
)

def repl(m):
  return 'var __er=document.getElementById("export-rid"); if(__er) __er.textContent = (rid || "(none)");'

s2, n = pat.subn(repl, s)

# fallback: nếu code viết kiểu "mentById("export-rid")..." (do minify/cắt), guard luôn
s2 = s2.replace('getElementById("export-rid").textContent = rid || "(none)";',
                'var __er=document.getElementById("export-rid"); if(__er) __er.textContent = (rid || "(none)");')
s2 = s2.replace("getElementById('export-rid').textContent = rid || '(none)';",
                'var __er=document.getElementById("export-rid"); if(__er) __er.textContent = (rid || "(none)");')

p.write_text(s2, encoding="utf-8")
print("[OK] patched", n, "pattern hits in", p)
PY

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R on /vsp4. Error Cannot set properties of null must be gone."
