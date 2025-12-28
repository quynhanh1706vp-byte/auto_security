#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re

tpl_root = Path("templates")
if not tpl_root.is_dir():
    raise SystemExit("[ERR] templates/ not found")

# Match exactly the V6 netguard block
rx = re.compile(
    r"\s*<!--\s*VSP_P1_NETGUARD_GLOBAL_V6\s*-->\s*"
    r"<script[^>]*\bid\s*=\s*['\"]VSP_P1_NETGUARD_GLOBAL_V6['\"][^>]*>.*?</script>\s*",
    flags=re.I | re.S
)

changed = []
for f in tpl_root.rglob("*.html"):
    s = f.read_text(encoding="utf-8", errors="replace")
    if "VSP_P1_NETGUARD_GLOBAL_V6" not in s:
        continue
    s2, n = rx.subn("\n", s)
    if n <= 0:
        # if pattern slightly different, do a safer fallback remove by markers
        # remove from <!-- V6 --> to </script> that contains id=VSP_P1_NETGUARD_GLOBAL_V6
        a = s.find("<!-- VSP_P1_NETGUARD_GLOBAL_V6 -->")
        if a != -1:
            b = s.find("</script>", a)
            if b != -1:
                s2 = s[:a] + "\n" + s[b+9:]
                n = 1
    if n > 0 and s2 != s:
        bak = f.with_name(f.name + f".bak_purge_v6_{Path().cwd().name}")
        i=0
        while bak.exists():
            i += 1
            bak = f.with_name(f.name + f".bak_purge_v6_{i}")
        bak.write_text(s, encoding="utf-8")
        f.write_text(s2, encoding="utf-8")
        changed.append(str(f))

print("[OK] purged V6 in files:", len(changed))
for x in changed:
    print(" -", x)
PY

sudo systemctl restart vsp-ui-8910.service && echo "[OK] restarted: vsp-ui-8910.service"
echo "[DONE] purged V6 templates; V7C middleware remains source-of-truth"
