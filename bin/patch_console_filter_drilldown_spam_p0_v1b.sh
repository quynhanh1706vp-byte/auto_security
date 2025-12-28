#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH CONSOLE SPAM FILTER (P0 v1b) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

python3 - <<'PY'
from pathlib import Path
import datetime, re

MARK = "VSP_CONSOLE_FILTER_DRILLDOWN_P0_V1"
FILTER_JS = r"""(function(){
  try{
    if (window.__VSP_CONSOLE_FILTER_DD_P0) return;
    window.__VSP_CONSOLE_FILTER_DD_P0 = 1;

    var needle = "drilldown real impl accepted";

    function wrap(k){
      try{
        var orig = console[k];
        if (typeof orig !== "function") return;
        console[k] = function(){
          try{
            var a0 = (arguments && arguments.length) ? String(arguments[0]) : "";
            if (a0 && a0.indexOf(needle) !== -1){
              if (window.__VSP_DD_ACCEPTED_ONCE) return;
              window.__VSP_DD_ACCEPTED_ONCE = 1;
            }
          }catch(_e){}
          return orig.apply(this, arguments);
        };
      }catch(_){}
    }

    ["log","info","debug","warn"].forEach(wrap);
  }catch(_){}
})();"""

filter_tag = f"<script>/*{MARK}*/\n{FILTER_JS}\n</script>\n"

tpl_dir = Path("templates")
patched = 0

def is_top_level_html(s: str) -> bool:
  low = s.lower()
  return ("<html" in low) and ("</body" in low)

def inject(path: Path) -> bool:
  s = path.read_text(encoding="utf-8", errors="replace")
  if not is_top_level_html(s):
    return False
  if MARK in s:
    return False

  # inject as early as possible: before </head> if exists
  if re.search(r"(?is)</head\s*>", s):
    new = re.sub(r"(?is)</head\s*>", "\n" + filter_tag + "</head>", s, count=1)
  else:
    new = filter_tag + s

  if new == s:
    return False

  ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
  bak = path.with_suffix(path.suffix + f".bak_consolefilter_{ts}")
  bak.write_text(s, encoding="utf-8")
  path.write_text(new, encoding="utf-8")
  print("[OK] injected filter into", path.as_posix())
  return True

if tpl_dir.exists():
  for p in sorted(tpl_dir.rglob("*.html")):
    try:
      if inject(p):
        patched += 1
    except Exception as e:
      print("[WARN] fail", p.as_posix(), e)

print("[DONE] templates_patched=", patched)

# Also prepend into bundle as safety
b = Path("static/js/vsp_bundle_commercial_v1.js")
if b.exists():
  bs = b.read_text(encoding="utf-8", errors="replace")
  if MARK not in bs:
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    bbak = b.with_suffix(b.suffix + f".bak_consolefilter_{ts}")
    bbak.write_text(bs, encoding="utf-8")
    b.write_text(f"/*{MARK}*/\n{FILTER_JS}\n\n" + bs, encoding="utf-8")
    print("[OK] prepended filter into bundle")
  else:
    print("[OK] bundle already has filter")
else:
  print("[WARN] bundle not found (skip)")
PY

echo "== node --check bundle =="
if [ -f static/js/vsp_bundle_commercial_v1.js ]; then
  node --check static/js/vsp_bundle_commercial_v1.js && echo "[OK] bundle syntax OK"
fi

echo "== DONE =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R"
