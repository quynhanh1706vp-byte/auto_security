#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rule_overrides_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_guardfix_v2_${TS}" && echo "[BACKUP] $F.bak_guardfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rule_overrides_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 0) Remove literal "\1" lines introduced by bad patch
s = re.sub(r'^\s*\\1\s*$', '', s, flags=re.M)

# 1) Remove any previously injected guard block
BEGIN="/* VSP_RULEOVERRIDES_GUARD_V1_BEGIN */"
END  ="/* VSP_RULEOVERRIDES_GUARD_V1_END */"
s = re.sub(re.escape(BEGIN)+r'.*?'+re.escape(END)+r'\s*', '', s, flags=re.S)

guard = f"""
{BEGIN}
// commercial safety: don't crash if rid override hook not present
try {{
  if (!window.VSP_RID_PICKLATEST_OVERRIDE_V1) {{
    window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items) {{
      return (items && items[0]) ? items[0] : null;
    }};
  }}
}} catch(e) {{}}
{END}
""".strip("\n")

# 2) Inject safely after 'use strict'; (or near top if not found)
if "'use strict'" in s:
  pat = r"('use strict'\s*;\s*)"
  def repl(m):
    return m.group(1) + "\n" + guard + "\n"
  s, n = re.subn(pat, repl, s, count=1)
  if n == 0:
    s = guard + "\n" + s
else:
  s = guard + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] rule_overrides guard injected (safe v2)")
PY

node --check "$F" >/dev/null && echo "[OK] rule_overrides JS syntax OK"
echo "[DONE] Fix applied. Hard refresh Ctrl+Shift+R."
