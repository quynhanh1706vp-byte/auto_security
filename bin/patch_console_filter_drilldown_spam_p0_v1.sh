#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH CONSOLE SPAM FILTER (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

FILTER_MARK="VSP_CONSOLE_FILTER_DRILLDOWN_P0_V1"
FILTER_JS='(function(){try{if(window.__VSP_CONSOLE_FILTER_DD_P0)return;window.__VSP_CONSOLE_FILTER_DD_P0=1;var needle="drilldown real impl accepted";function wrap(k){try{var orig=console[k];if(typeof orig!=="function")return;console[k]=function(){try{var a0=arguments&&arguments.length?String(arguments[0]):"";if(a0&&a0.indexOf(needle)!==-1){if(window.__VSP_DD_ACCEPTED_ONCE)return;window.__VSP_DD_ACCEPTED_ONCE=1;}}catch(_e){}return orig.apply(this,arguments);};}catch(_){}}["log","info","debug","warn"].forEach(wrap);}catch(_){}})();'

# (1) Inject filter early into ALL top-level templates (before </head>)
python3 - <<PY
from pathlib import Path
import datetime, re

tpl_dir = Path("templates")
mark = "${FILTER_MARK}"
filter_tag = f"<script>/*{mark}*/{${'FILTER_JS'}!r}</script>"

def inject(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")
    low = s.lower()
    if "<html" not in low:
        return False
    if mark in s:
        return False
    if "</head>" in low:
        # insert right before </head> so it runs before any later inline scripts
        new = re.sub(r"(?is)</head\s*>", "\n" + filter_tag + "\n</head>", s, count=1)
    else:
        # fallback: prepend
        new = filter_tag + "\n" + s
    if new != s:
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bak = path.with_suffix(path.suffix + f".bak_consolefilter_{ts}")
        bak.write_text(s, encoding="utf-8")
        path.write_text(new, encoding="utf-8")
        print("[OK] injected filter into", path.as_posix())
        return True
    return False

patched = 0
if tpl_dir.exists():
    for p in sorted(tpl_dir.rglob("*.html")):
        try:
            if inject(p):
                patched += 1
        except Exception as e:
            print("[WARN] fail", p.as_posix(), e)
print("[DONE] templates_patched=", patched)
PY

# (2) Also prepend the same filter into bundle (optional safety)
B="static/js/vsp_bundle_commercial_v1.js"
if [ -f "$B" ]; then
  cp -f "$B" "$B.bak_consolefilter_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
mark="${FILTER_MARK}"
if mark in s:
  print("[OK] bundle already has filter (skip)")
else:
  pre="/*"+mark+"*/\n" + "${FILTER_JS}" + "\n"
  p.write_text(pre + s, encoding="utf-8")
  print("[OK] prepended filter into bundle")
PY
  node --check "$B" && echo "[OK] bundle syntax OK"
else
  echo "[WARN] missing $B (skip bundle patch)"
fi

echo "== DONE =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R"
