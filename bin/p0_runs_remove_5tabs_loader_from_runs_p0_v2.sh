#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")
root = Path("templates")
paths = list(root.rglob("*.html"))

# match script tags that load vsp_fill_real_data_5tabs_p1_v1.js (with or without leading slash)
pat = re.compile(
    r"""(?is)
    \s*<script\b[^>]*\bsrc\s*=\s*(['"])\s*/?static/js/vsp_fill_real_data_5tabs_p1_v1\.js\s*\1[^>]*>\s*</script>\s*
    """,
    re.VERBOSE
)

changed=[]
for p in paths:
    if ".bak_" in p.name:
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    s2, n = pat.subn("\n", s)
    # fallback: nếu ai đó viết dạng lạ (không đóng tag chuẩn), xoá theo dòng chứa filename
    if n == 0 and "vsp_fill_real_data_5tabs_p1_v1.js" in s:
        lines = s.splitlines(True)
        kept=[]
        removed=0
        for ln in lines:
            if "vsp_fill_real_data_5tabs_p1_v1.js" in ln and "<script" in ln:
                removed += 1
                continue
            kept.append(ln)
        s2 = "".join(kept)
        n = removed

    if s2 != s:
        bak = p.with_name(p.name + f".bak_rm5tabs_{TS}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        changed.append((str(p), n))

print(f"[DONE] patched templates: {len(changed)}")
for fn,n in changed[:30]:
    print(" -", fn, "removed_blocks=", n)
if len(changed) > 30:
    print(" ... (more)")

PY

echo "== verify grep in templates (must be empty) =="
grep -RIn --exclude='*.bak_*' "vsp_fill_real_data_5tabs_p1_v1\.js" templates || echo "[OK] no include in templates"

# restart UI
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "[DONE] Now test:"
echo "  curl -sS http://127.0.0.1:8910/runs | grep -n vsp_fill_real_data_5tabs_p1_v1.js || echo OK"
echo "  Open Incognito: http://127.0.0.1:8910/runs"
