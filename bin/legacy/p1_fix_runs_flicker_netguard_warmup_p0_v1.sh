#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")
tpl_dir = Path("templates")
if not tpl_dir.exists():
    print("[ERR] templates/ not found")
    raise SystemExit(2)

targets = []
for p in sorted(tpl_dir.rglob("*.html")):
    s = p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P1_NETGUARD_GLOBAL_V7B" in s or "__vsp_p1_netguard_global_v7b" in s:
        targets.append(p)

if not targets:
    print("[ERR] no templates contain NETGUARD V7B marker")
    raise SystemExit(2)

changed = 0
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s

    # 1) Remove initial fake-hold: Date.now()+2500 => Date.now()
    s, n1 = re.subn(
        r'let\s+holdUntil\s*=\s*Date\.now\(\)\s*\+\s*2500\s*;\s*//\s*grace\s*on\s*first\s*load/restart',
        'let holdUntil = Date.now(); // no initial hold (avoid fake FAIL flicker)',
        s
    )

    # 2) Warm-up logic: during hold, ONLY serve cache if it's good (ok===true).
    #    If no good cache => DO NOT early-return, allow real fetch to run.
    pat = re.compile(
        r'if\s*\(\s*now\s*<\s*holdUntil\s*\)\s*\{\s*'
        r'const\s+cached\s*=\s*_load\(u\)\s*\|\|\s*\{ok:false,'
        r'\s*note:"degraded-cache-empty"\}\s*;'
        r'\s*return\s+_resp\(\s*cached\s*,\s*\{"X-VSP-Hold":"1","X-VSP-Cache":"1"\}\s*\)\s*;'
        r'\s*\}',
        re.S
    )

    def repl(_m):
        return (
            'if (now < holdUntil) {\n'
            '          const cached = _load(u);\n'
            '          // commercial: only serve cache during hold if it is a previously-good payload\n'
            '          if (cached && cached.ok === true) {\n'
            '            return _resp(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1"});\n'
            '          }\n'
            '          // warm-up: no good cache => allow real fetch (prevents RUNS API FAIL flicker)\n'
            '        }'
        )

    s2, n2 = pat.subn(repl, s)

    # Nếu pattern hơi khác (không có object degraded-cache-empty), patch thêm biến thể mềm hơn:
    # if(now<holdUntil){ const cached=_load(u); return _resp(cached||..., {...}); }
    if n2 == 0:
        pat2 = re.compile(
            r'if\s*\(\s*now\s*<\s*holdUntil\s*\)\s*\{\s*'
            r'const\s+cached\s*=\s*_load\(u\)\s*;'
            r'\s*return\s+_resp\(\s*cached\s*\|\|.*?\)\s*;'
            r'\s*\}',
            re.S
        )
        s2, n2b = pat2.subn(repl, s2)
        n2 = n2b

    if s2 != orig:
        bak = p.with_name(p.name + f".bak_netguard_warmup_{ts}")
        bak.write_text(orig, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        changed += 1
        print(f"[OK] patched: {p}  (holdInitFix={n1} holdBlockFix={n2})  backup={bak.name}")
    else:
        print(f"[SKIP] unchanged: {p}")

print("[DONE] templates patched:", changed, "/", len(targets))
print("NEXT: restart UI then Ctrl+F5 /runs (flicker should stop).")
PY
