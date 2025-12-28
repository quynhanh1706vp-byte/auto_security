#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

TPL="templates/vsp_dashboard_2025.html"
JS1="static/js/vsp_runs_tab_8tools_v1.js"
JS2="static/js/vsp_tools_status_from_gate_p0_v1.js"

echo "== [1/3] disable vsp_runs_tab_8tools_v1.js in template (stop parse/crash) =="
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_disable8tools_${TS}" && echo "[BACKUP] $TPL.bak_disable8tools_${TS}"

python3 - <<PY
from pathlib import Path
import re
p=Path("$TPL")
s=p.read_text(encoding="utf-8", errors="ignore")
# comment out script tag containing vsp_runs_tab_8tools_v1.js (any querystring)
pat=re.compile(r'(<script[^>]+src=["\'][^"\']*vsp_runs_tab_8tools_v1\.js[^"\']*["\'][^>]*>\s*</script>)', re.I)
s2, n = pat.subn(r'<!-- DISABLED_BY_P0_STABILIZE: \1 -->', s)
if n==0:
    # fallback: remove plain occurrence
    s2 = s.replace("vsp_runs_tab_8tools_v1.js", "vsp_runs_tab_8tools_v1.js__DISABLED")
    n = 1 if s2!=s else 0
p.write_text(s2, encoding="utf-8")
print("[OK] disabled tag count =", n)
PY

echo "== [2/3] restore vsp_runs_tab_8tools_v1.js to pre-wrap (keep file clean even if disabled) =="
if [ -f "$JS1" ]; then
  B="$(ls -1t ${JS1}.bak_gate_* 2>/dev/null | head -n1 || true)"
  if [ -n "${B:-}" ]; then
    cp -f "$JS1" "$JS1.bak_before_restore_${TS}" && echo "[BACKUP] $JS1.bak_before_restore_${TS}"
    cp -f "$B" "$JS1" && echo "[RESTORE] $JS1 <= $B"
  else
    echo "[WARN] no ${JS1}.bak_gate_* found; skip restore"
  fi
else
  echo "[WARN] missing $JS1; skip"
fi

echo "== [3/3] guard tools_status render() with try/catch (never crash on null mounts) =="
[ -f "$JS2" ] || { echo "[ERR] missing $JS2"; exit 2; }
cp -f "$JS2" "$JS2.bak_guard_render_${TS}" && echo "[BACKUP] $JS2.bak_guard_render_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# find render function (async or not)
m=re.search(r'\n\s*(async\s+)?function\s+render\s*\([^)]*\)\s*\{', s)
if not m:
    print("[ERR] cannot find function render(...) {")
    raise SystemExit(2)

start = m.end()  # position right after "{"
# naive brace matching that skips strings/templates enough for this use-case
i=start
depth=1
state="code"
quote=None
while i < len(s) and depth>0:
    ch=s[i]
    if state=="code":
        if ch in ("'", '"'):
            state="str"; quote=ch
        elif ch=="`":
            state="tpl"
        elif ch=="/" and i+1<len(s) and s[i+1]=="/":
            state="line"; i+=1
        elif ch=="/" and i+1<len(s) and s[i+1]=="*":
            state="block"; i+=1
        elif ch=="{":
            depth+=1
        elif ch=="}":
            depth-=1
    elif state=="str":
        if ch=="\\":
            i+=1
        elif ch==quote:
            state="code"
    elif state=="tpl":
        if ch=="\\":
            i+=1
        elif ch=="`":
            state="code"
        elif ch=="$" and i+1<len(s) and s[i+1]=="{":
            depth+=1
            i+=1
    elif state=="line":
        if ch=="\n":
            state="code"
    elif state=="block":
        if ch=="*" and i+1<len(s) and s[i+1]=="/":
            state="code"; i+=1
    i+=1

end=i-1  # index of the closing "}" for render
body = s[start:end].strip("\n")
if "VSP_TOOLS_STATUS_RENDER_GUARD_V1" in body:
    print("[OK] render already guarded")
    raise SystemExit(0)

guarded = "\n  /* VSP_TOOLS_STATUS_RENDER_GUARD_V1 */\n  try {\n" + body + "\n  } catch(e) {\n    try{ console.warn('[VSP_TOOLS_STATUS] render skipped (missing mounts?)', e); }catch(_){ }\n    return;\n  }\n"
s2 = s[:start] + guarded + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] guarded render() with try/catch")
PY

node --check "$JS2" >/dev/null && echo "[OK] node --check tools_status" || { echo "[ERR] tools_status syntax broken"; exit 3; }

echo "[DONE] Stabilize patch applied. Restart UI + Ctrl+Shift+R + Ctrl+0."
